unit MCPTool.Serper;

{
  MCPTool.Serper  ·  mcp-serper  (port 8619)
  Google Search via Serper API (serper.dev).

  Operations:
    search       - web search (Google results)
    news         - news search
    images       - image search
    places       - local places search
    scholar      - Google Scholar academic search
    autocomplete - search query autocomplete suggestions
}

interface

uses
  uMakerAi.MCPServer.Core,
  System.JSON;

type
  TSerperParams = class
  private
    FOperation: string;
    FApiKey:    string;
    FQuery:     string;
    FNum:       Integer;
    FPage:      Integer;
    FCountry:   string;
    FLanguage:  string;
    FTimeRange: string;
    FLocation:  string;
  public
    constructor Create;

    [AiMCPSchemaDescription('Operation: search, news, images, places, scholar, autocomplete')]
    property Operation: string  read FOperation write FOperation;

    [AiMCPSchemaDescription('Serper API key (get at serper.dev)')]
    property ApiKey:    string  read FApiKey    write FApiKey;

    [AiMCPSchemaDescription('Search query')]
    property Query:     string  read FQuery     write FQuery;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Number of results (default: 10, max: 100)')]
    property Num:       Integer read FNum       write FNum;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Page number for pagination (default: 1)')]
    property Page:      Integer read FPage      write FPage;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Country code for results, e.g. us, gb, de (default: us)')]
    property Country:   string  read FCountry   write FCountry;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Language code, e.g. en, es, fr (default: en)')]
    property Language:  string  read FLanguage  write FLanguage;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Time range: qdr:h (hour), qdr:d (day), qdr:w (week), qdr:m (month), qdr:y (year)')]
    property TimeRange: string  read FTimeRange write FTimeRange;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Location for local/places search (e.g. "New York, NY")')]
    property Location:  string  read FLocation  write FLocation;
  end;

  TSerperTool = class(TAiMCPToolBase<TSerperParams>)
  private
    function ApiSearch(const Endpoint, Body, ApiKey: string): TJSONObject;
    function DoSearch(const P: TSerperParams): TJSONObject;
    function DoNews(const P: TSerperParams): TJSONObject;
    function DoImages(const P: TSerperParams): TJSONObject;
    function DoPlaces(const P: TSerperParams): TJSONObject;
    function DoScholar(const P: TSerperParams): TJSONObject;
    function DoAutocomplete(const P: TSerperParams): TJSONObject;
  protected
    function ExecuteWithParams(const AParams: TSerperParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

procedure RegisterTools(AServer: TAiMCPServer);

implementation

uses
  System.SysUtils,
  System.Classes,
  System.Net.HttpClient,
  System.Net.URLClient;

{ TSerperParams }

constructor TSerperParams.Create;
begin
  inherited;
  FNum      := 10;
  FPage     := 1;
  FCountry  := 'us';
  FLanguage := 'en';
end;

{ TSerperTool }

function TSerperTool.ApiSearch(const Endpoint, Body, ApiKey: string): TJSONObject;
var
  HTTP:   THTTPClient;
  Stream: TStringStream;
  Resp:   IHTTPResponse;
  Raw:    string;
  J:      TJSONValue;
begin
  HTTP   := THTTPClient.Create;
  Stream := TStringStream.Create(Body, TEncoding.UTF8);
  try
    Resp := HTTP.Post('https://google.serper.dev/' + Endpoint, Stream, nil,
      [TNameValuePair.Create('Content-Type', 'application/json'),
       TNameValuePair.Create('X-API-KEY',    ApiKey)]);
    Raw := Resp.ContentAsString(TEncoding.UTF8);
  finally
    Stream.Free;
    HTTP.Free;
  end;

  J := TJSONObject.ParseJSONValue(Raw);
  if Assigned(J) then
    Result := J as TJSONObject
  else
  begin
    Result := TJSONObject.Create;
    Result.AddPair('raw', TJSONString.Create(Raw));
  end;
end;

function TSerperTool.DoSearch(const P: TSerperParams): TJSONObject;
var
  Body: string;
  J:    TJSONObject;
begin
  Body := Format('{"q":"%s","num":%d,"page":%d,"gl":"%s","hl":"%s"',
    [P.Query.Replace('"', '\"'), P.Num, P.Page, P.Country, P.Language]);
  if Trim(P.TimeRange) <> '' then
    Body := Body + ',"tbs":"' + Trim(P.TimeRange) + '"';
  Body := Body + '}';

  J := ApiSearch('search', Body, Trim(P.ApiKey));
  J.AddPair('ok', TJSONTrue.Create);
  Result := J;
end;

function TSerperTool.DoNews(const P: TSerperParams): TJSONObject;
var
  Body: string;
  J:    TJSONObject;
begin
  Body := Format('{"q":"%s","num":%d,"page":%d,"gl":"%s","hl":"%s"',
    [P.Query.Replace('"', '\"'), P.Num, P.Page, P.Country, P.Language]);
  if Trim(P.TimeRange) <> '' then
    Body := Body + ',"tbs":"' + Trim(P.TimeRange) + '"';
  Body := Body + '}';

  J := ApiSearch('news', Body, Trim(P.ApiKey));
  J.AddPair('ok', TJSONTrue.Create);
  Result := J;
end;

function TSerperTool.DoImages(const P: TSerperParams): TJSONObject;
var
  Body: string;
  J:    TJSONObject;
begin
  Body := Format('{"q":"%s","num":%d,"page":%d,"gl":"%s","hl":"%s"}',
    [P.Query.Replace('"', '\"'), P.Num, P.Page, P.Country, P.Language]);
  J := ApiSearch('images', Body, Trim(P.ApiKey));
  J.AddPair('ok', TJSONTrue.Create);
  Result := J;
end;

function TSerperTool.DoPlaces(const P: TSerperParams): TJSONObject;
var
  Body: string;
  J:    TJSONObject;
begin
  Body := Format('{"q":"%s","gl":"%s","hl":"%s"',
    [P.Query.Replace('"', '\"'), P.Country, P.Language]);
  if Trim(P.Location) <> '' then
    Body := Body + ',"location":"' + Trim(P.Location).Replace('"','\"') + '"';
  Body := Body + '}';

  J := ApiSearch('places', Body, Trim(P.ApiKey));
  J.AddPair('ok', TJSONTrue.Create);
  Result := J;
end;

function TSerperTool.DoScholar(const P: TSerperParams): TJSONObject;
var
  Body: string;
  J:    TJSONObject;
begin
  Body := Format('{"q":"%s","num":%d,"page":%d}',
    [P.Query.Replace('"', '\"'), P.Num, P.Page]);
  J := ApiSearch('scholar', Body, Trim(P.ApiKey));
  J.AddPair('ok', TJSONTrue.Create);
  Result := J;
end;

function TSerperTool.DoAutocomplete(const P: TSerperParams): TJSONObject;
var
  Body: string;
  J:    TJSONObject;
begin
  Body := Format('{"q":"%s","gl":"%s","hl":"%s"}',
    [P.Query.Replace('"', '\"'), P.Country, P.Language]);
  J := ApiSearch('autocomplete', Body, Trim(P.ApiKey));
  J.AddPair('ok', TJSONTrue.Create);
  Result := J;
end;

function TSerperTool.ExecuteWithParams(const AParams: TSerperParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op: string;
  R:  TJSONObject;
begin
  try
    Op := LowerCase(Trim(AParams.Operation));
    if Op = '' then raise Exception.Create('"operation" is required');
    if Trim(AParams.ApiKey) = '' then raise Exception.Create('"apiKey" is required');
    if Trim(AParams.Query)  = '' then raise Exception.Create('"query" is required');

    if      Op = 'search'       then R := DoSearch(AParams)
    else if Op = 'news'         then R := DoNews(AParams)
    else if Op = 'images'       then R := DoImages(AParams)
    else if Op = 'places'       then R := DoPlaces(AParams)
    else if Op = 'scholar'      then R := DoScholar(AParams)
    else if Op = 'autocomplete' then R := DoAutocomplete(AParams)
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

constructor TSerperTool.Create;
begin
  inherited;
  FName        := 'mcp-serper';
  FDescription :=
    'Google Search via Serper API (serper.dev). ' +
    'Operations: search (web), news, images, places (local), scholar (academic), autocomplete. ' +
    'Required: apiKey, query. ' +
    'Optional: num (default 10), page (default 1), country (default us), ' +
    'language (default en), timeRange (qdr:h/d/w/m/y), location (for places).';
end;

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-serper',
    function: IAiMCPTool
    begin
      Result := TSerperTool.Create;
    end);
  WriteLn(ErrOutput, '[MCPService]   + mcp-serper');
end;

end.
