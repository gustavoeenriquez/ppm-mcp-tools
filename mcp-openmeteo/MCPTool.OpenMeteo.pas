unit MCPTool.OpenMeteo;

{
  MCPTool.OpenMeteo — mcp-openmeteo
  Weather via Open-Meteo API (free, no API key).

  Modes:
    forecast   — current conditions + daily forecast (1-16 days)
    hourly     — hour-by-hour data (temp, humidity, precip, wind, clouds)
    historical — ERA5 reanalysis: daily min/max/precip/wind for past dates

  Geocoding via Open-Meteo geocoding API.
  Supports city names, "City, Country", or "lat,lon" coordinates.
}

interface

uses
  uMakerAi.MCPServer.Core,
  System.SysUtils,
  System.JSON,
  System.Classes,
  System.Math,
  System.NetEncoding,
  System.Net.HttpClient;

type

  TOpenMeteoParams = class
  private
    FLocation:  string;
    FMode:      string;
    FDays:      Integer;
    FStartDate: string;
    FEndDate:   string;
    FUnits:     string;
  public
    [AiMCPSchemaDescription('City name, "City, Country", or "lat,lon" coordinates')]
    property Location:  string  read FLocation  write FLocation;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Mode: forecast (current+daily, default), hourly, historical')]
    property Mode:      string  read FMode      write FMode;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Forecast/hourly days 1-16 (default: 7)')]
    property Days:      Integer read FDays      write FDays;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Historical start date YYYY-MM-DD — mapped as "startDate" in JSON (required for historical mode)')]
    property StartDate: string  read FStartDate write FStartDate;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Historical end date YYYY-MM-DD — mapped as "endDate" in JSON (required for historical mode)')]
    property EndDate:   string  read FEndDate   write FEndDate;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Units: metric (°C, km/h, mm) or imperial (°F, mph, inch). Default: metric')]
    property Units:     string  read FUnits     write FUnits;
  end;

  TLocationInfo = record
    Name:      string;
    Country:   string;
    Latitude:  Double;
    Longitude: Double;
    Timezone:  string;
  end;

  TOpenMeteoTool = class(TAiMCPToolBase<TOpenMeteoParams>)
  protected
    function ExecuteWithParams(const AParams: TOpenMeteoParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

procedure RegisterTools(AServer: TAiMCPServer);

implementation

const
  GEO_URL      = 'https://geocoding-api.open-meteo.com/v1/search';
  FORECAST_URL = 'https://api.open-meteo.com/v1/forecast';
  HISTORY_URL  = 'https://archive-api.open-meteo.com/v1/archive';

// ── JSON helpers ──────────────────────────────────────────────────────────────

function JStr(Obj: TJSONObject; const Key: string): string;
begin
  var V := Obj.GetValue(Key);
  if (V = nil) or (V is TJSONNull) then Exit('');
  if V is TJSONString then Result := TJSONString(V).Value else Result := V.Value;
end;

function JNum(Obj: TJSONObject; const Key: string): Double;
begin
  var V := Obj.GetValue(Key);
  if (V = nil) or (V is TJSONNull) then Exit(0);
  if V is TJSONNumber then Result := TJSONNumber(V).AsDouble
  else Result := StrToFloatDef(V.Value, 0);
end;

function ArrNum(Arr: TJSONArray; Index: Integer): Double;
begin
  if (Arr = nil) or (Index >= Arr.Count) then Exit(0);
  var V := Arr.Items[Index];
  if (V = nil) or (V is TJSONNull) then Exit(0);
  if V is TJSONNumber then Result := TJSONNumber(V).AsDouble
  else Result := StrToFloatDef(V.Value, 0);
end;

function ArrInt(Arr: TJSONArray; Index: Integer): Integer;
begin
  Result := Round(ArrNum(Arr, Index));
end;

function ArrStr(Arr: TJSONArray; Index: Integer): string;
begin
  if (Arr = nil) or (Index >= Arr.Count) then Exit('');
  var V := Arr.Items[Index];
  if (V = nil) or (V is TJSONNull) then Exit('');
  if V is TJSONString then Result := TJSONString(V).Value else Result := V.Value;
end;

// ── WMO weather code ──────────────────────────────────────────────────────────

function WMODescription(Code: Integer): string;
begin
  case Code of
    0:   Result := 'Clear sky';
    1:   Result := 'Mainly clear';
    2:   Result := 'Partly cloudy';
    3:   Result := 'Overcast';
    45:  Result := 'Fog';
    48:  Result := 'Icy fog';
    51:  Result := 'Light drizzle';
    53:  Result := 'Moderate drizzle';
    55:  Result := 'Dense drizzle';
    61:  Result := 'Slight rain';
    63:  Result := 'Moderate rain';
    65:  Result := 'Heavy rain';
    71:  Result := 'Slight snow';
    73:  Result := 'Moderate snow';
    75:  Result := 'Heavy snow';
    77:  Result := 'Snow grains';
    80:  Result := 'Slight rain showers';
    81:  Result := 'Moderate rain showers';
    82:  Result := 'Violent rain showers';
    85:  Result := 'Slight snow showers';
    86:  Result := 'Heavy snow showers';
    95:  Result := 'Thunderstorm';
    96:  Result := 'Thunderstorm with slight hail';
    99:  Result := 'Thunderstorm with heavy hail';
  else
    Result := Format('Code %d', [Code]);
  end;
end;

// ── HTTP helper ───────────────────────────────────────────────────────────────

function FetchJSON(const URL: string): TJSONObject;
begin
  var Client := THTTPClient.Create;
  try
    Client.ConnectionTimeout := 15000;
    Client.ResponseTimeout   := 20000;
    Client.CustomHeaders['Accept'] := 'application/json';
    var Resp := Client.Get(URL);
    if Resp.StatusCode <> 200 then
      raise Exception.CreateFmt('HTTP %d: %s', [Resp.StatusCode, Resp.ContentAsString]);
    var JV := TJSONObject.ParseJSONValue(Resp.ContentAsString(TEncoding.UTF8));
    if not (JV is TJSONObject) then
      raise Exception.Create('Invalid JSON response');
    Result := JV as TJSONObject;
  finally
    Client.Free;
  end;
end;

// ── Location resolution ───────────────────────────────────────────────────────

function LatLonStr(V: Double): string;
begin
  Result := FloatToStrF(V, ffFixed, 15, 6, TFormatSettings.Invariant);
end;

function IsLatLon(const S: string; out Lat, Lon: Double): Boolean;
var
  Parts: TArray<string>;
  FS: TFormatSettings;
begin
  Result := False;
  Parts := S.Trim.Split([',']);
  if Length(Parts) <> 2 then Exit;
  FS := TFormatSettings.Invariant;
  Result := TryStrToFloat(Trim(Parts[0]), Lat, FS) and
            TryStrToFloat(Trim(Parts[1]), Lon, FS);
end;

function ResolveLocation(const LocationStr: string): TLocationInfo;
var
  Lat, Lon: Double;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Name     := LocationStr;
  Result.Timezone := 'auto';

  if IsLatLon(LocationStr, Lat, Lon) then
  begin
    Result.Latitude  := Lat;
    Result.Longitude := Lon;
    Exit;
  end;

  var Encoded := TNetEncoding.URL.Encode(Trim(LocationStr));
  var URL := Format('%s?name=%s&count=1&language=en&format=json', [GEO_URL, Encoded]);
  var JRoot := FetchJSON(URL);
  try
    var Results := JRoot.GetValue('results') as TJSONArray;
    if (not Assigned(Results)) or (Results.Count = 0) then
      raise Exception.CreateFmt('Location not found: "%s"', [LocationStr]);
    var First := Results.Items[0] as TJSONObject;
    Result.Name      := JStr(First, 'name');
    Result.Country   := JStr(First, 'country');
    Result.Latitude  := JNum(First, 'latitude');
    Result.Longitude := JNum(First, 'longitude');
    Result.Timezone  := JStr(First, 'timezone');
    if Result.Timezone = '' then Result.Timezone := 'auto';
  finally
    JRoot.Free;
  end;
end;

// ── Unit helpers ──────────────────────────────────────────────────────────────

procedure GetUnitParams(Metric: Boolean;
  out TempUnit, WindUnit, PrecUnit: string);
begin
  if Metric then
  begin
    TempUnit := 'celsius';
    WindUnit := 'kmh';
    PrecUnit := 'mm';
  end
  else
  begin
    TempUnit := 'fahrenheit';
    WindUnit := 'mph';
    PrecUnit := 'inch';
  end;
end;

// ── Forecast mode ─────────────────────────────────────────────────────────────

procedure BuildForecast(const Loc: TLocationInfo; Days: Integer;
  Metric: Boolean; R: TJSONObject);
var
  TempUnit, WindUnit, PrecUnit: string;
  JRoot, JCur, JDailyRoot: TJSONObject;
  TimeArr, MaxArr, MinArr, PrecArr, ProbArr, WindArr,
  WCodeArr, SriseArr, SsetArr: TJSONArray;
  FcstArr: TJSONArray;
  DayObj, CurObj: TJSONObject;
  Sunrise, Sunset: string;
  WCode, i: Integer;
begin
  GetUnitParams(Metric, TempUnit, WindUnit, PrecUnit);
  if Days < 1 then Days := 7;
  if Days > 16 then Days := 16;

  var URL := Format('%s?latitude=%s&longitude=%s'
    + '&current_weather=true'
    + '&daily=temperature_2m_max,temperature_2m_min,precipitation_sum,'
    +        'precipitation_probability_max,windspeed_10m_max,weathercode,'
    +        'sunrise,sunset'
    + '&timezone=auto&forecast_days=%d'
    + '&temperature_unit=%s&windspeed_unit=%s&precipitation_unit=%s',
    [FORECAST_URL, LatLonStr(Loc.Latitude), LatLonStr(Loc.Longitude),
     Days, TempUnit, WindUnit, PrecUnit]);

  JRoot := FetchJSON(URL);
  try
    // Current conditions
    CurObj := TJSONObject.Create;
    var JCurV := JRoot.GetValue('current_weather');
    if JCurV is TJSONObject then
    begin
      JCur  := JCurV as TJSONObject;
      WCode := Round(JNum(JCur, 'weathercode'));
      if Metric then
      begin
        CurObj.AddPair('temperature_c', TJSONNumber.Create(JNum(JCur, 'temperature')));
        CurObj.AddPair('windspeed_kmh', TJSONNumber.Create(JNum(JCur, 'windspeed')));
      end
      else
      begin
        CurObj.AddPair('temperature_f', TJSONNumber.Create(JNum(JCur, 'temperature')));
        CurObj.AddPair('windspeed_mph', TJSONNumber.Create(JNum(JCur, 'windspeed')));
      end;
      CurObj.AddPair('wind_direction_deg', TJSONNumber.Create(JNum(JCur, 'winddirection')));
      CurObj.AddPair('is_day',             TJSONNumber.Create(Round(JNum(JCur, 'is_day'))));
      CurObj.AddPair('weathercode',        TJSONNumber.Create(WCode));
      CurObj.AddPair('description',        WMODescription(WCode));
    end;
    R.AddPair('current', CurObj);

    // Daily forecast
    FcstArr    := TJSONArray.Create;
    JDailyRoot := JRoot.GetValue('daily') as TJSONObject;
    if Assigned(JDailyRoot) then
    begin
      TimeArr  := JDailyRoot.GetValue('time')                          as TJSONArray;
      MaxArr   := JDailyRoot.GetValue('temperature_2m_max')            as TJSONArray;
      MinArr   := JDailyRoot.GetValue('temperature_2m_min')            as TJSONArray;
      PrecArr  := JDailyRoot.GetValue('precipitation_sum')             as TJSONArray;
      ProbArr  := JDailyRoot.GetValue('precipitation_probability_max') as TJSONArray;
      WindArr  := JDailyRoot.GetValue('windspeed_10m_max')             as TJSONArray;
      WCodeArr := JDailyRoot.GetValue('weathercode')                   as TJSONArray;
      SriseArr := JDailyRoot.GetValue('sunrise')                       as TJSONArray;
      SsetArr  := JDailyRoot.GetValue('sunset')                        as TJSONArray;

      var Count := 0;
      if Assigned(TimeArr) then Count := TimeArr.Count;
      for i := 0 to Count - 1 do
      begin
        DayObj := TJSONObject.Create;
        DayObj.AddPair('date', ArrStr(TimeArr, i));
        WCode := ArrInt(WCodeArr, i);

        if Metric then
        begin
          DayObj.AddPair('max_c',             TJSONNumber.Create(ArrNum(MaxArr,  i)));
          DayObj.AddPair('min_c',             TJSONNumber.Create(ArrNum(MinArr,  i)));
          DayObj.AddPair('precipitation_mm',  TJSONNumber.Create(ArrNum(PrecArr, i)));
          DayObj.AddPair('windspeed_max_kmh', TJSONNumber.Create(ArrNum(WindArr, i)));
        end
        else
        begin
          DayObj.AddPair('max_f',               TJSONNumber.Create(ArrNum(MaxArr,  i)));
          DayObj.AddPair('min_f',               TJSONNumber.Create(ArrNum(MinArr,  i)));
          DayObj.AddPair('precipitation_inch',  TJSONNumber.Create(ArrNum(PrecArr, i)));
          DayObj.AddPair('windspeed_max_mph',   TJSONNumber.Create(ArrNum(WindArr, i)));
        end;

        DayObj.AddPair('precipitation_probability_max_pct',
          TJSONNumber.Create(ArrInt(ProbArr, i)));
        DayObj.AddPair('weathercode', TJSONNumber.Create(WCode));
        DayObj.AddPair('description', WMODescription(WCode));

        // Open-Meteo returns sunrise/sunset as "YYYY-MM-DDTHH:MM" — keep just HH:MM
        Sunrise := ArrStr(SriseArr, i);
        Sunset  := ArrStr(SsetArr,  i);
        if Length(Sunrise) > 11 then Sunrise := Copy(Sunrise, 12, 5);
        if Length(Sunset)  > 11 then Sunset  := Copy(Sunset,  12, 5);
        DayObj.AddPair('sunrise', Sunrise);
        DayObj.AddPair('sunset',  Sunset);

        FcstArr.AddElement(DayObj);
      end;
    end;
    R.AddPair('daily', FcstArr);
  finally
    JRoot.Free;
  end;
end;

// ── Hourly mode ───────────────────────────────────────────────────────────────

procedure BuildHourly(const Loc: TLocationInfo; Days: Integer;
  Metric: Boolean; R: TJSONObject);
var
  TempUnit, WindUnit, PrecUnit: string;
  JRoot, JHourly: TJSONObject;
  TimeArr, TempArr, HumArr, ProbArr, PrecArr,
  CloudArr, WindArr, WCodeArr: TJSONArray;
  HourlyArr: TJSONArray;
  HObj: TJSONObject;
  WCode, i: Integer;
begin
  GetUnitParams(Metric, TempUnit, WindUnit, PrecUnit);
  if Days < 1 then Days := 3;
  if Days > 16 then Days := 16;

  var URL := Format('%s?latitude=%s&longitude=%s'
    + '&hourly=temperature_2m,relativehumidity_2m,precipitation_probability,'
    +         'precipitation,cloudcover,windspeed_10m,weathercode'
    + '&timezone=auto&forecast_days=%d'
    + '&temperature_unit=%s&windspeed_unit=%s&precipitation_unit=%s',
    [FORECAST_URL, LatLonStr(Loc.Latitude), LatLonStr(Loc.Longitude),
     Days, TempUnit, WindUnit, PrecUnit]);

  JRoot := FetchJSON(URL);
  try
    HourlyArr := TJSONArray.Create;
    JHourly   := JRoot.GetValue('hourly') as TJSONObject;
    if Assigned(JHourly) then
    begin
      TimeArr  := JHourly.GetValue('time')                       as TJSONArray;
      TempArr  := JHourly.GetValue('temperature_2m')             as TJSONArray;
      HumArr   := JHourly.GetValue('relativehumidity_2m')        as TJSONArray;
      ProbArr  := JHourly.GetValue('precipitation_probability')  as TJSONArray;
      PrecArr  := JHourly.GetValue('precipitation')              as TJSONArray;
      CloudArr := JHourly.GetValue('cloudcover')                 as TJSONArray;
      WindArr  := JHourly.GetValue('windspeed_10m')              as TJSONArray;
      WCodeArr := JHourly.GetValue('weathercode')                as TJSONArray;

      var Count := 0;
      if Assigned(TimeArr) then Count := TimeArr.Count;
      for i := 0 to Count - 1 do
      begin
        HObj  := TJSONObject.Create;
        WCode := ArrInt(WCodeArr, i);
        HObj.AddPair('time', ArrStr(TimeArr, i));
        if Metric then
        begin
          HObj.AddPair('temperature_c',    TJSONNumber.Create(ArrNum(TempArr, i)));
          HObj.AddPair('precipitation_mm', TJSONNumber.Create(ArrNum(PrecArr, i)));
          HObj.AddPair('windspeed_kmh',    TJSONNumber.Create(ArrNum(WindArr, i)));
        end
        else
        begin
          HObj.AddPair('temperature_f',      TJSONNumber.Create(ArrNum(TempArr, i)));
          HObj.AddPair('precipitation_inch', TJSONNumber.Create(ArrNum(PrecArr, i)));
          HObj.AddPair('windspeed_mph',      TJSONNumber.Create(ArrNum(WindArr, i)));
        end;
        HObj.AddPair('humidity_pct',                  TJSONNumber.Create(ArrInt(HumArr,   i)));
        HObj.AddPair('precipitation_probability_pct', TJSONNumber.Create(ArrInt(ProbArr,  i)));
        HObj.AddPair('cloudcover_pct',                TJSONNumber.Create(ArrInt(CloudArr, i)));
        HObj.AddPair('weathercode',                   TJSONNumber.Create(WCode));
        HObj.AddPair('description',                   WMODescription(WCode));
        HourlyArr.AddElement(HObj);
      end;
    end;
    R.AddPair('hourly', HourlyArr);
  finally
    JRoot.Free;
  end;
end;

// ── Historical mode ───────────────────────────────────────────────────────────

procedure BuildHistorical(const Loc: TLocationInfo;
  const StartDate, EndDate: string; Metric: Boolean; R: TJSONObject);
var
  TempUnit, WindUnit, PrecUnit: string;
  JRoot, JDaily: TJSONObject;
  TimeArr, MaxArr, MinArr, PrecArr, WindArr, WCodeArr: TJSONArray;
  HistArr: TJSONArray;
  DayObj: TJSONObject;
  WCode, i: Integer;
begin
  GetUnitParams(Metric, TempUnit, WindUnit, PrecUnit);

  var URL := Format('%s?latitude=%s&longitude=%s'
    + '&start_date=%s&end_date=%s'
    + '&daily=temperature_2m_max,temperature_2m_min,precipitation_sum,'
    +        'windspeed_10m_max,weathercode'
    + '&timezone=auto'
    + '&temperature_unit=%s&windspeed_unit=%s&precipitation_unit=%s',
    [HISTORY_URL, LatLonStr(Loc.Latitude), LatLonStr(Loc.Longitude),
     StartDate, EndDate, TempUnit, WindUnit, PrecUnit]);

  JRoot := FetchJSON(URL);
  try
    HistArr := TJSONArray.Create;
    JDaily  := JRoot.GetValue('daily') as TJSONObject;
    if Assigned(JDaily) then
    begin
      TimeArr  := JDaily.GetValue('time')               as TJSONArray;
      MaxArr   := JDaily.GetValue('temperature_2m_max') as TJSONArray;
      MinArr   := JDaily.GetValue('temperature_2m_min') as TJSONArray;
      PrecArr  := JDaily.GetValue('precipitation_sum')  as TJSONArray;
      WindArr  := JDaily.GetValue('windspeed_10m_max')  as TJSONArray;
      WCodeArr := JDaily.GetValue('weathercode')        as TJSONArray;

      var Count := 0;
      if Assigned(TimeArr) then Count := TimeArr.Count;
      for i := 0 to Count - 1 do
      begin
        DayObj := TJSONObject.Create;
        DayObj.AddPair('date', ArrStr(TimeArr, i));
        WCode := ArrInt(WCodeArr, i);
        if Metric then
        begin
          DayObj.AddPair('max_c',             TJSONNumber.Create(ArrNum(MaxArr,  i)));
          DayObj.AddPair('min_c',             TJSONNumber.Create(ArrNum(MinArr,  i)));
          DayObj.AddPair('precipitation_mm',  TJSONNumber.Create(ArrNum(PrecArr, i)));
          DayObj.AddPair('windspeed_max_kmh', TJSONNumber.Create(ArrNum(WindArr, i)));
        end
        else
        begin
          DayObj.AddPair('max_f',               TJSONNumber.Create(ArrNum(MaxArr,  i)));
          DayObj.AddPair('min_f',               TJSONNumber.Create(ArrNum(MinArr,  i)));
          DayObj.AddPair('precipitation_inch',  TJSONNumber.Create(ArrNum(PrecArr, i)));
          DayObj.AddPair('windspeed_max_mph',   TJSONNumber.Create(ArrNum(WindArr, i)));
        end;
        DayObj.AddPair('weathercode', TJSONNumber.Create(WCode));
        DayObj.AddPair('description', WMODescription(WCode));
        HistArr.AddElement(DayObj);
      end;
    end;
    R.AddPair('historical', HistArr);
  finally
    JRoot.Free;
  end;
end;

// ── Tool execution ────────────────────────────────────────────────────────────

function TOpenMeteoTool.ExecuteWithParams(const AParams: TOpenMeteoParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Loc: TLocationInfo;
  Mode, UnitsStr: string;
  Metric: Boolean;
  Days: Integer;
  R, LocObj: TJSONObject;
begin
  try
    if Trim(AParams.Location) = '' then
      raise Exception.Create('"location" is required');

    Mode     := LowerCase(Trim(AParams.Mode));
    if Mode = '' then Mode := 'forecast';
    UnitsStr := LowerCase(Trim(AParams.Units));
    if UnitsStr = '' then UnitsStr := 'metric';
    Metric := UnitsStr <> 'imperial';
    Days   := AParams.Days;
    if Days <= 0 then Days := 7;

    Loc := ResolveLocation(Trim(AParams.Location));

    LocObj := TJSONObject.Create;
    LocObj.AddPair('name',      Loc.Name);
    LocObj.AddPair('country',   Loc.Country);
    LocObj.AddPair('latitude',  TJSONNumber.Create(Loc.Latitude));
    LocObj.AddPair('longitude', TJSONNumber.Create(Loc.Longitude));
    LocObj.AddPair('timezone',  Loc.Timezone);

    R := TJSONObject.Create;
    R.AddPair('location', LocObj);
    R.AddPair('units', UnitsStr);

    if Mode = 'hourly' then
      BuildHourly(Loc, Days, Metric, R)
    else if Mode = 'historical' then
    begin
      var SD := Trim(AParams.StartDate);
      var ED := Trim(AParams.EndDate);
      if SD = '' then raise Exception.Create('"start_date" required for historical mode');
      if ED = '' then raise Exception.Create('"end_date" required for historical mode');
      BuildHistorical(Loc, SD, ED, Metric, R);
    end
    else
      BuildForecast(Loc, Days, Metric, R);

    Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
    R.Free;

  except
    on E: Exception do
      Result := TAiMCPResponseBuilder.New
        .AddText('Error [mcp-openmeteo]: ' + E.Message)
        .Build;
  end;
end;

constructor TOpenMeteoTool.Create;
begin
  inherited;
  FName        := 'mcp-openmeteo';
  FDescription :=
    'Detailed weather via Open-Meteo (free, no API key). ' +
    'Modes: forecast = current conditions + daily up to 16 days; ' +
    'hourly = hour-by-hour temperature/precipitation/wind/clouds; ' +
    'historical = ERA5 past data by date range. ' +
    'location: city name or "lat,lon". units: metric (default) or imperial.';
end;

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-openmeteo',
    function: IAiMCPTool
    begin
      Result := TOpenMeteoTool.Create;
    end);
  WriteLn(ErrOutput, '[mcp-openmeteo] ready');
end;

end.
