unit MCPTool.Weather;

{
  MCPTool.Weather
  MCP tool: mcp-weather

  Fetches weather data via wttr.in (no API key required).
  Supports city names, airport codes, and "lat,lon" coordinates.

  Returns:
    current    - temperature, humidity, wind, UV, description
    forecast   - 3-day daily forecast (if forecast=true)
    location   - resolved place name and coordinates
}

interface

uses
  uMakerAi.MCPServer.Core,
  System.SysUtils,
  System.JSON,
  System.Classes,
  System.Math,
  System.NetEncoding,
  System.Net.HttpClient,
  System.Net.URLClient;

type

  // ── Parameters ─────────────────────────────────────────────────────────────

  TWeatherParams = class
  private
    FLocation: string;
    FUnits:    string;
    FForecast: Boolean;
  public
    [AiMCPSchemaDescription('Location: city name, airport code, or "lat,lon" coordinates')]
    property Location: string read FLocation write FLocation;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Unit system: metric (default) or imperial')]
    property Units: string read FUnits write FUnits;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Include 3-day daily forecast (default: false)')]
    property Forecast: Boolean read FForecast write FForecast;
  end;

  // ── Tool ───────────────────────────────────────────────────────────────────

  TWeatherTool = class(TAiMCPToolBase<TWeatherParams>)
  protected
    function ExecuteWithParams(const AParams: TWeatherParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

procedure RegisterTools(AServer: TAiMCPServer);

implementation

// ── Helpers ─────────────────────────────────────────────────────────────────

function JStr(Obj: TJSONObject; const Key: string): string;
begin
  var V := Obj.GetValue(Key);
  if Assigned(V) then Result := V.Value else Result := '';
end;

function JNum(Obj: TJSONObject; const Key: string): Double;
begin
  var V := Obj.GetValue(Key);
  if Assigned(V) then Result := StrToFloatDef(V.Value, 0) else Result := 0;
end;

function FirstStr(JV: TJSONValue; const Key: string): string;
// Gets arr[0].Key from a TJSONArray stored under key in an outer object
begin
  Result := '';
  if not (JV is TJSONArray) then Exit;
  var Arr := TJSONArray(JV);
  if Arr.Count = 0 then Exit;
  if Arr.Items[0] is TJSONObject then
    Result := JStr(TJSONObject(Arr.Items[0]), Key);
end;

// ── Main execution ──────────────────────────────────────────────────────────

function TWeatherTool.ExecuteWithParams(const AParams: TWeatherParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  R: TJSONObject;
begin
  try
    if AParams.Location = '' then
      raise Exception.Create('"location" is required');

    var Metric := LowerCase(Trim(AParams.Units)) <> 'imperial';

    // Fetch from wttr.in JSON API
    var Loc := TNetEncoding.URL.Encode(Trim(AParams.Location));
    var URL := Format('https://wttr.in/%s?format=j1', [Loc]);

    var Client := THTTPClient.Create;
    var RawJSON: string;
    try
      Client.ConnectionTimeout := 15000;
      Client.ResponseTimeout   := 15000;
      Client.CustomHeaders['User-Agent'] := 'mcp-weather/1.0';
      var Resp := Client.Get(URL);
      if Resp.StatusCode <> 200 then
        raise Exception.CreateFmt('wttr.in error %d', [Resp.StatusCode]);
      RawJSON := Resp.ContentAsString(TEncoding.UTF8);
    finally
      Client.Free;
    end;

    var JRootV := TJSONObject.ParseJSONValue(RawJSON);
    if not Assigned(JRootV) then
      raise Exception.Create('Invalid JSON response from wttr.in');
    var JRoot := JRootV as TJSONObject;
    try
      // ── Location ─────────────────────────────────────────────────────────
      var NearestArr := JRoot.GetValue('nearest_area') as TJSONArray;
      var PlaceName  := '';
      var Country    := '';
      var Lat        := '';
      var Lon        := '';
      if Assigned(NearestArr) and (NearestArr.Count > 0) then
      begin
        var NA := NearestArr.Items[0] as TJSONObject;
        PlaceName := FirstStr(NA.GetValue('areaName'),  'value');
        Country   := FirstStr(NA.GetValue('country'),   'value');
        Lat       := JStr(NA, 'latitude');
        Lon       := JStr(NA, 'longitude');
      end;

      var LocationObj := TJSONObject.Create;
      LocationObj.AddPair('name',      PlaceName);
      LocationObj.AddPair('country',   Country);
      LocationObj.AddPair('latitude',  Lat);
      LocationObj.AddPair('longitude', Lon);

      // ── Current conditions ────────────────────────────────────────────────
      var CurArr := JRoot.GetValue('current_condition') as TJSONArray;
      var CurObj := TJSONObject.Create;

      if Assigned(CurArr) and (CurArr.Count > 0) then
      begin
        var C := CurArr.Items[0] as TJSONObject;

        var TempC      := JNum(C, 'temp_C');
        var TempF      := JNum(C, 'temp_F');
        var FeelsC     := JNum(C, 'FeelsLikeC');
        var FeelsF     := JNum(C, 'FeelsLikeF');
        var Humidity   := JNum(C, 'humidity');
        var WindKmph   := JNum(C, 'windspeedKmph');
        var WindMph    := JNum(C, 'windspeedMiles');
        var WindDir    := JStr(C, 'winddir16Point');
        var Visibility := JNum(C, 'visibility');
        var Pressure   := JNum(C, 'pressure');
        var UVIndex    := JNum(C, 'uvIndex');
        var Desc       := FirstStr(C.GetValue('weatherDesc'), 'value');

        if Metric then
        begin
          CurObj.AddPair('temperature_c',  TJSONNumber.Create(TempC));
          CurObj.AddPair('feels_like_c',   TJSONNumber.Create(FeelsC));
          CurObj.AddPair('wind_kmph',      TJSONNumber.Create(WindKmph));
          CurObj.AddPair('visibility_km',  TJSONNumber.Create(Visibility));
          CurObj.AddPair('pressure_hpa',   TJSONNumber.Create(Pressure));
        end
        else
        begin
          CurObj.AddPair('temperature_f',  TJSONNumber.Create(TempF));
          CurObj.AddPair('feels_like_f',   TJSONNumber.Create(FeelsF));
          CurObj.AddPair('wind_mph',       TJSONNumber.Create(WindMph));
          CurObj.AddPair('visibility_mi',  TJSONNumber.Create(Visibility * 0.621371));
          CurObj.AddPair('pressure_hpa',   TJSONNumber.Create(Pressure));
        end;

        CurObj.AddPair('humidity_pct',   TJSONNumber.Create(Humidity));
        CurObj.AddPair('wind_direction', WindDir);
        CurObj.AddPair('uv_index',       TJSONNumber.Create(UVIndex));
        CurObj.AddPair('description',    Desc);
      end;

      R := TJSONObject.Create;
      R.AddPair('location', LocationObj);
      if Metric then R.AddPair('units', 'metric') else R.AddPair('units', 'imperial');
      R.AddPair('current',  CurObj);

      // ── 3-day forecast (optional) ─────────────────────────────────────────
      if AParams.Forecast then
      begin
        var WeatherArr := JRoot.GetValue('weather') as TJSONArray;
        var FcstArr    := TJSONArray.Create;

        if Assigned(WeatherArr) then
          for var i := 0 to WeatherArr.Count - 1 do
          begin
            var Day  := WeatherArr.Items[i] as TJSONObject;
            var DObj := TJSONObject.Create;
            DObj.AddPair('date',     JStr(Day, 'date'));
            if Metric then
            begin
              DObj.AddPair('max_c', TJSONNumber.Create(JNum(Day, 'maxtempC')));
              DObj.AddPair('min_c', TJSONNumber.Create(JNum(Day, 'mintempC')));
              DObj.AddPair('avg_c', TJSONNumber.Create(JNum(Day, 'avgtempC')));
            end
            else
            begin
              DObj.AddPair('max_f', TJSONNumber.Create(JNum(Day, 'maxtempF')));
              DObj.AddPair('min_f', TJSONNumber.Create(JNum(Day, 'mintempF')));
              DObj.AddPair('avg_f', TJSONNumber.Create(JNum(Day, 'avgtempF')));
            end;
            DObj.AddPair('uv_index',  TJSONNumber.Create(JNum(Day, 'uvIndex')));
            DObj.AddPair('sun_hour',  TJSONNumber.Create(JNum(Day, 'sunHour')));

            var HrArr := Day.GetValue('hourly') as TJSONArray;
            if Assigned(HrArr) and (HrArr.Count > 0) then
            begin
              // pick noon (index 4 = 12:00)
              var Noon := Min(4, HrArr.Count - 1);
              var H    := HrArr.Items[Noon] as TJSONObject;
              DObj.AddPair('desc_noon',
                FirstStr(H.GetValue('weatherDesc'), 'value'));
            end;

            FcstArr.AddElement(DObj);
          end;

        R.AddPair('forecast', FcstArr);
      end;

    finally
      JRootV.Free;
    end;

    Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
    R.Free;

  except
    on E: Exception do
      Result := TAiMCPResponseBuilder.New
        .AddText('Error [mcp-weather]: ' + E.Message)
        .Build;
  end;
end;

constructor TWeatherTool.Create;
begin
  inherited;
  FName        := 'mcp-weather';
  FDescription :=
    'Current weather and 3-day forecast via wttr.in (no API key required). ' +
    'location: city name, airport code (e.g. SFO), or "lat,lon" coordinates. ' +
    'units: metric (default) or imperial. ' +
    'forecast: set true to include 3-day daily forecast. ' +
    'Returns: location info, current conditions ' +
    '(temperature, feels_like, humidity, wind, UV, description), ' +
    'and optional forecast array.';
end;

// ── Registration ─────────────────────────────────────────────────────────────

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-weather',
    function: IAiMCPTool
    begin
      Result := TWeatherTool.Create;
    end);
  WriteLn(ErrOutput, '[mcp-weather] ready');
end;

end.
