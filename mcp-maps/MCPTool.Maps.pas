unit MCPTool.Maps;

{
  MCPTool.Maps  ·  mcp-maps

  Geocoding and place search via Nominatim (OpenStreetMap). Free, no API key.

  Operations:
    geocode         - convert address or place name to coordinates
    reverse_geocode - convert coordinates to address
    search          - search for places by category/query near a location
}

interface

uses
  uMakerAi.MCPServer.Core,
  System.SysUtils,
  System.JSON,
  System.Classes,
  System.Net.HttpClient,
  System.Net.URLClient,
  System.NetEncoding;

type

  TMapsParams = class
  private
    FOperation: string;
    FAddress:   string;
    FQuery:     string;
    FLat:       Double;
    FLon:       Double;
    FLimit:     Integer;
    FLang:      string;
    FCountry:   string;
  public
    constructor Create;

    [AiMCPSchemaDescription('Operation: geocode, reverse_geocode, search')]
    property Operation: string  read FOperation write FOperation;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Address or place name to geocode (for geocode)')]
    property Address:   string  read FAddress   write FAddress;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Search query, e.g. "coffee shop" (for search)')]
    property Query:     string  read FQuery     write FQuery;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Latitude (for reverse_geocode and search)')]
    property Lat:       Double  read FLat       write FLat;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Longitude (for reverse_geocode and search)')]
    property Lon:       Double  read FLon       write FLon;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Maximum results (default: 5)')]
    property Limit:     Integer read FLimit     write FLimit;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Language for results, e.g. en, es, fr (default: en)')]
    property Lang:      string  read FLang      write FLang;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Restrict results to country code, e.g. US, DE (for geocode/search)')]
    property Country:   string  read FCountry   write FCountry;
  end;

  TMapsTool = class(TAiMCPToolBase<TMapsParams>)
  private
    function HttpGet(const URL: string): string;
    function UrlEncode(const S: string): string;
    function FormatDouble(const D: Double): string;
    function ParsePlace(Item: TJSONObject): TJSONObject;
    function DoGeocode(const P: TMapsParams): TJSONObject;
    function DoReverseGeocode(const P: TMapsParams): TJSONObject;
    function DoSearch(const P: TMapsParams): TJSONObject;
  protected
    function ExecuteWithParams(const AParams: TMapsParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

procedure RegisterTools(AServer: TAiMCPServer);

implementation

const
  NOMINATIM = 'https://nominatim.openstreetmap.org';
  USER_AGENT = 'mcp-maps/1.0 (pascalai.org)';

{ TMapsParams }

constructor TMapsParams.Create;
begin
  inherited;
  FLimit := 5;
  FLang  := 'en';
end;

{ TMapsTool }

function TMapsTool.HttpGet(const URL: string): string;
var
  HTTP: THTTPClient;
  Resp: IHTTPResponse;
begin
  HTTP := THTTPClient.Create;
  try
    HTTP.ConnectionTimeout := 10000;
    HTTP.ResponseTimeout   := 20000;
    Resp := HTTP.Get(URL, nil, [TNameValuePair.Create('User-Agent', USER_AGENT),
                                TNameValuePair.Create('Accept-Language', 'en')]);
    if Resp.StatusCode <> 200 then
      raise Exception.CreateFmt('HTTP %d', [Resp.StatusCode]);
    Result := Resp.ContentAsString;
  finally
    HTTP.Free;
  end;
end;

function TMapsTool.UrlEncode(const S: string): string;
begin
  Result := TNetEncoding.URL.EncodeQuery(S);
end;

function TMapsTool.FormatDouble(const D: Double): string;
begin
  Result := FormatFloat('0.######', D);
end;

function TMapsTool.ParsePlace(Item: TJSONObject): TJSONObject;
var
  Addr:    TJSONObject;
  AddrOut: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('display_name', Item.GetValue<string>('display_name', ''));
  Result.AddPair('lat',          Item.GetValue<string>('lat', ''));
  Result.AddPair('lon',          Item.GetValue<string>('lon', ''));
  Result.AddPair('type',         Item.GetValue<string>('type', ''));
  Result.AddPair('class',        Item.GetValue<string>('class', ''));

  // Structured address
  Addr := nil;
  if Item.TryGetValue<TJSONObject>('address', Addr) then
  begin
    AddrOut := TJSONObject.Create;
    for var Field in ['road','house_number','suburb','city','town','village',
                      'municipality','state','postcode','country','country_code'] do
    begin
      var V := Addr.GetValue<string>(Field, '');
      if V <> '' then AddrOut.AddPair(Field, V);
    end;
    Result.AddPair('address', AddrOut);
  end;
end;

function TMapsTool.DoGeocode(const P: TMapsParams): TJSONObject;
var
  Query:   string;
  URL:     string;
  RespStr: string;
  Parsed:  TJSONValue;
  Arr:     TJSONArray;
  Results: TJSONArray;
  Limit:   Integer;
  i:       Integer;
begin
  Query := Trim(P.Address);
  if Query = '' then
    Query := Trim(P.Query);
  if Query = '' then raise Exception.Create('"address" required for geocode');

  Limit := P.Limit;
  if Limit <= 0 then Limit := 5;

  URL := Format('%s/search?q=%s&format=json&limit=%d&addressdetails=1',
    [NOMINATIM, UrlEncode(Query), Limit]);
  if P.Country <> '' then
    URL := URL + '&countrycodes=' + LowerCase(P.Country);
  if P.Lang <> '' then
    URL := URL + '&accept-language=' + P.Lang;

  RespStr := HttpGet(URL);
  Parsed  := TJSONObject.ParseJSONValue(RespStr);
  try
    Results := TJSONArray.Create;
    if Parsed is TJSONArray then
    begin
      Arr := Parsed as TJSONArray;
      for i := 0 to Arr.Count - 1 do
        if Arr.Items[i] is TJSONObject then
          Results.AddElement(ParsePlace(Arr.Items[i] as TJSONObject));
    end;

    Result := TJSONObject.Create;
    Result.AddPair('query',   Query);
    Result.AddPair('results', Results);
    Result.AddPair('count',   TJSONNumber.Create(Results.Count));
    Result.AddPair('ok',      TJSONTrue.Create);
  finally
    Parsed.Free;
  end;
end;

function TMapsTool.DoReverseGeocode(const P: TMapsParams): TJSONObject;
var
  URL:     string;
  RespStr: string;
  Parsed:  TJSONValue;
  Place:   TJSONObject;
begin
  if (P.Lat = 0) and (P.Lon = 0) then
    raise Exception.Create('"lat" and "lon" required for reverse_geocode');

  URL := Format('%s/reverse?lat=%s&lon=%s&format=json&addressdetails=1',
    [NOMINATIM, FormatDouble(P.Lat), FormatDouble(P.Lon)]);
  if P.Lang <> '' then
    URL := URL + '&accept-language=' + P.Lang;

  RespStr := HttpGet(URL);
  Parsed  := TJSONObject.ParseJSONValue(RespStr);
  try
    if not (Parsed is TJSONObject) then
      raise Exception.Create('Location not found');

    var J := Parsed as TJSONObject;
    var ErrMsg := J.GetValue<string>('error', '');
    if ErrMsg <> '' then
      raise Exception.Create('Nominatim: ' + ErrMsg);

    Place := ParsePlace(J);

    Result := TJSONObject.Create;
    Result.AddPair('lat',   FormatDouble(P.Lat));
    Result.AddPair('lon',   FormatDouble(P.Lon));
    Result.AddPair('place', Place);
    Result.AddPair('ok',    TJSONTrue.Create);
  finally
    Parsed.Free;
  end;
end;

function TMapsTool.DoSearch(const P: TMapsParams): TJSONObject;
var
  Query:   string;
  URL:     string;
  RespStr: string;
  Parsed:  TJSONValue;
  Arr:     TJSONArray;
  Results: TJSONArray;
  Limit:   Integer;
  i:       Integer;
begin
  Query := Trim(P.Query);
  if Query = '' then Query := Trim(P.Address);
  if Query = '' then raise Exception.Create('"query" required for search');

  Limit := P.Limit;
  if Limit <= 0 then Limit := 5;

  URL := Format('%s/search?q=%s&format=json&limit=%d&addressdetails=1',
    [NOMINATIM, UrlEncode(Query), Limit]);
  if (P.Lat <> 0) or (P.Lon <> 0) then
    URL := URL + Format('&viewbox=%s,%s,%s,%s&bounded=0',
      [FormatDouble(P.Lon - 0.5), FormatDouble(P.Lat + 0.5),
       FormatDouble(P.Lon + 0.5), FormatDouble(P.Lat - 0.5)]);
  if P.Country <> '' then
    URL := URL + '&countrycodes=' + LowerCase(P.Country);
  if P.Lang <> '' then
    URL := URL + '&accept-language=' + P.Lang;

  RespStr := HttpGet(URL);
  Parsed  := TJSONObject.ParseJSONValue(RespStr);
  try
    Results := TJSONArray.Create;
    if Parsed is TJSONArray then
    begin
      Arr := Parsed as TJSONArray;
      for i := 0 to Arr.Count - 1 do
        if Arr.Items[i] is TJSONObject then
          Results.AddElement(ParsePlace(Arr.Items[i] as TJSONObject));
    end;

    Result := TJSONObject.Create;
    Result.AddPair('query',   Query);
    Result.AddPair('results', Results);
    Result.AddPair('count',   TJSONNumber.Create(Results.Count));
    Result.AddPair('ok',      TJSONTrue.Create);
  finally
    Parsed.Free;
  end;
end;

function TMapsTool.ExecuteWithParams(const AParams: TMapsParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op: string;
  R:  TJSONObject;
begin
  try
    Op := LowerCase(Trim(AParams.Operation));
    if Op = '' then raise Exception.Create('"operation" is required');

    if      Op = 'geocode'         then R := DoGeocode(AParams)
    else if Op = 'reverse_geocode' then R := DoReverseGeocode(AParams)
    else if Op = 'search'          then R := DoSearch(AParams)
    else raise Exception.CreateFmt('Unknown operation "%s"', [Op]);

    Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
    R.Free;
  except
    on E: Exception do
      Result := TAiMCPResponseBuilder.New
        .AddText('{"ok":false,"error":"' +
          E.Message.Replace('\','\\').Replace('"','\"')
                   .Replace(#10,'\n').Replace(#13,'') + '"}')
        .Build;
  end;
end;

constructor TMapsTool.Create;
begin
  inherited;
  FName        := 'mcp-maps';
  FDescription :=
    'Geocoding and place search via OpenStreetMap Nominatim (free, no key required). ' +
    'Operations: ' +
    'geocode (address/name to coordinates; params: address, limit?, country?, lang?), ' +
    'reverse_geocode (coordinates to address; params: lat, lon, lang?), ' +
    'search (search places; params: query, lat?, lon?, limit?, country?, lang?). ' +
    'Returns coordinates, structured address, place type.';
end;

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-maps',
    function: IAiMCPTool
    begin
      Result := TMapsTool.Create;
    end);
  WriteLn(ErrOutput, '[mcp-maps] ready');
end;

end.
