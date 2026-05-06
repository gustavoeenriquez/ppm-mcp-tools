unit MCPTool.BraveSearch;

{
  MCPTool.BraveSearch
  MCP tool: mcp-brave-search

  Wraps the Brave Search API (https://api.search.brave.com).
  Requires a Brave Search API key (free tier available at brave.com/search/api).

  Operations:
    web   - web search results
    news  - news search results
    image - image search results (returns metadata, not image data)

  The apiKey parameter can be omitted if the BRAVE_SEARCH_API_KEY environment
  variable is set on the server.
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

  TBraveSearchParams = class
  private
    FQuery:    string;
    FApiKey:   string;
    FCount:    Integer;
    FOffset:   Integer;
    FCountry:  string;
    FLanguage: string;
    FType:     string;
  public
    [AiMCPSchemaDescription('Search query')]
    property Query: string read FQuery write FQuery;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Brave Search API key (or set BRAVE_SEARCH_API_KEY env var)')]
    property ApiKey: string read FApiKey write FApiKey;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Number of results to return (1-20, default: 10)')]
    property Count: Integer read FCount write FCount;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Result offset for pagination (default: 0)')]
    property Offset: Integer read FOffset write FOffset;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Country code for results (e.g. US, GB, DE). Default: US')]
    property Country: string read FCountry write FCountry;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Language code (e.g. en, es, de). Default: en')]
    property Language: string read FLanguage write FLanguage;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Search type: web, news, image (default: web)')]
    property SearchType: string read FType write FType;
  end;

  // ── Tool ───────────────────────────────────────────────────────────────────

  TBraveSearchTool = class(TAiMCPToolBase<TBraveSearchParams>)
  private
    function FetchJSON(const URL, ApiKey: string): TJSONValue;
    function ParseWebResults(JData: TJSONValue; const Query: string; Count: Integer): TJSONObject;
    function ParseNewsResults(JData: TJSONValue; const Query: string; Count: Integer): TJSONObject;
    function ParseImageResults(JData: TJSONValue; const Query: string; Count: Integer): TJSONObject;
  protected
    function ExecuteWithParams(const AParams: TBraveSearchParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

procedure RegisterTools(AServer: TAiMCPServer);

implementation

// ── Helpers ─────────────────────────────────────────────────────────────────

function TBraveSearchTool.FetchJSON(const URL, ApiKey: string): TJSONValue;
var
  Client: THTTPClient;
  Resp:   IHTTPResponse;
begin
  Client := THTTPClient.Create;
  try
    Client.ConnectionTimeout := 15000;
    Client.ResponseTimeout   := 15000;
    Client.CustomHeaders['Accept']               := 'application/json';
    Client.CustomHeaders['X-Subscription-Token'] := ApiKey;
    Resp := Client.Get(URL);
    if Resp.StatusCode <> 200 then
      raise Exception.CreateFmt('Brave API error %d: %s',
        [Resp.StatusCode, Resp.ContentAsString]);
    Result := TJSONObject.ParseJSONValue(Resp.ContentAsString(TEncoding.UTF8));
  finally
    Client.Free;
  end;
end;

function SafeStr(JV: TJSONValue; const Path: string): string;
var
  Parts: TArray<string>;
  Cur:   TJSONValue;
begin
  Result := '';
  Parts := Path.Split(['.']);
  Cur   := JV;
  for var P in Parts do
  begin
    if Cur is TJSONObject then
      Cur := TJSONObject(Cur).GetValue(P)
    else if Cur is TJSONArray then
    begin
      var Idx := StrToIntDef(P, -1);
      if (Idx >= 0) and (Idx < TJSONArray(Cur).Count) then
        Cur := TJSONArray(Cur).Items[Idx]
      else
        Cur := nil;
    end
    else
      Cur := nil;
    if not Assigned(Cur) then Exit;
  end;
  if Assigned(Cur) then
    Result := Cur.Value;
end;

function TBraveSearchTool.ParseWebResults(JData: TJSONValue; const Query: string;
  Count: Integer): TJSONObject;
var
  Results: TJSONArray;
  WebArr:  TJSONValue;
begin
  Results := TJSONArray.Create;
  WebArr  := nil;

  if JData is TJSONObject then
  begin
    var Web := TJSONObject(JData).GetValue('web');
    if Web is TJSONObject then
      WebArr := TJSONObject(Web).GetValue('results');
  end;

  if WebArr is TJSONArray then
    for var i := 0 to Min(TJSONArray(WebArr).Count, Count) - 1 do
    begin
      var Item := TJSONArray(WebArr).Items[i];
      var R    := TJSONObject.Create;
      R.AddPair('title',       SafeStr(Item, 'title'));
      R.AddPair('url',         SafeStr(Item, 'url'));
      R.AddPair('description', SafeStr(Item, 'description'));
      R.AddPair('age',         SafeStr(Item, 'age'));
      R.AddPair('source',      SafeStr(Item, 'profile.name'));
      Results.AddElement(R);
    end;

  Result := TJSONObject.Create;
  Result.AddPair('query',   Query);
  Result.AddPair('type',    'web');
  Result.AddPair('count',   TJSONNumber.Create(Results.Count));
  Result.AddPair('results', Results);
end;

function TBraveSearchTool.ParseNewsResults(JData: TJSONValue; const Query: string;
  Count: Integer): TJSONObject;
var
  Results: TJSONArray;
  NewsArr: TJSONValue;
begin
  Results := TJSONArray.Create;
  NewsArr := nil;

  if JData is TJSONObject then
  begin
    var News := TJSONObject(JData).GetValue('news');
    if News is TJSONObject then
      NewsArr := TJSONObject(News).GetValue('results');
  end;

  if NewsArr is TJSONArray then
    for var i := 0 to Min(TJSONArray(NewsArr).Count, Count) - 1 do
    begin
      var Item := TJSONArray(NewsArr).Items[i];
      var R    := TJSONObject.Create;
      R.AddPair('title',       SafeStr(Item, 'title'));
      R.AddPair('url',         SafeStr(Item, 'url'));
      R.AddPair('description', SafeStr(Item, 'description'));
      R.AddPair('age',         SafeStr(Item, 'age'));
      R.AddPair('source',      SafeStr(Item, 'meta_url.netloc'));
      Results.AddElement(R);
    end;

  Result := TJSONObject.Create;
  Result.AddPair('query',   Query);
  Result.AddPair('type',    'news');
  Result.AddPair('count',   TJSONNumber.Create(Results.Count));
  Result.AddPair('results', Results);
end;

function TBraveSearchTool.ParseImageResults(JData: TJSONValue; const Query: string;
  Count: Integer): TJSONObject;
var
  Results:  TJSONArray;
  ImgArr:   TJSONValue;
begin
  Results := TJSONArray.Create;
  ImgArr  := nil;

  if JData is TJSONObject then
  begin
    var Imgs := TJSONObject(JData).GetValue('images');
    if Imgs is TJSONObject then
      ImgArr := TJSONObject(Imgs).GetValue('results');
  end;

  if ImgArr is TJSONArray then
    for var i := 0 to Min(TJSONArray(ImgArr).Count, Count) - 1 do
    begin
      var Item := TJSONArray(ImgArr).Items[i];
      var R    := TJSONObject.Create;
      R.AddPair('title',    SafeStr(Item, 'title'));
      R.AddPair('url',      SafeStr(Item, 'url'));
      R.AddPair('source',   SafeStr(Item, 'source'));
      R.AddPair('img_src',  SafeStr(Item, 'properties.url'));
      R.AddPair('width',    SafeStr(Item, 'properties.width'));
      R.AddPair('height',   SafeStr(Item, 'properties.height'));
      Results.AddElement(R);
    end;

  Result := TJSONObject.Create;
  Result.AddPair('query',   Query);
  Result.AddPair('type',    'image');
  Result.AddPair('count',   TJSONNumber.Create(Results.Count));
  Result.AddPair('results', Results);
end;

// ── Main execution ──────────────────────────────────────────────────────────

function TBraveSearchTool.ExecuteWithParams(const AParams: TBraveSearchParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  R: TJSONObject;
begin
  try
    if AParams.Query = '' then
      raise Exception.Create('"query" is required');

    var ApiKey := AParams.ApiKey;
    if ApiKey = '' then
      ApiKey := GetEnvironmentVariable('BRAVE_SEARCH_API_KEY');
    if ApiKey = '' then
      raise Exception.Create(
        'Brave API key required: pass "apiKey" or set BRAVE_SEARCH_API_KEY env var');

    var SType   := LowerCase(Trim(AParams.SearchType));
    if SType = '' then SType := 'web';

    var Count  := AParams.Count;
    if Count <= 0 then Count := 10;
    Count := Min(Count, 20);

    var Offset   := Max(0, AParams.Offset);
    var Country  := AParams.Country;
    if Country = '' then Country := 'US';
    var Language := AParams.Language;
    if Language = '' then Language := 'en';

    var Q        := TNetEncoding.URL.Encode(AParams.Query);
    var Endpoint := 'https://api.search.brave.com/res/v1/';

    var URL: string;
    if SType = 'news' then
      URL := Format('%snews/search?q=%s&count=%d&offset=%d&country=%s&search_lang=%s',
        [Endpoint, Q, Count, Offset, Country, Language])
    else if SType = 'image' then
      URL := Format('%simages/search?q=%s&count=%d&country=%s&search_lang=%s',
        [Endpoint, Q, Count, Country, Language])
    else
      URL := Format('%sweb/search?q=%s&count=%d&offset=%d&country=%s&search_lang=%s',
        [Endpoint, Q, Count, Offset, Country, Language]);

    var JData := FetchJSON(URL, ApiKey);
    try
      if SType = 'news' then
        R := ParseNewsResults(JData, AParams.Query, Count)
      else if SType = 'image' then
        R := ParseImageResults(JData, AParams.Query, Count)
      else
        R := ParseWebResults(JData, AParams.Query, Count);
    finally
      JData.Free;
    end;

    Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
    R.Free;

  except
    on E: Exception do
      Result := TAiMCPResponseBuilder.New
        .AddText('Error [mcp-brave-search]: ' + E.Message)
        .Build;
  end;
end;

constructor TBraveSearchTool.Create;
begin
  inherited;
  FName        := 'mcp-brave-search';
  FDescription :=
    'Search the web using the Brave Search API. ' +
    'query: search terms (required). ' +
    'apiKey: Brave Search API key (or BRAVE_SEARCH_API_KEY env var). ' +
    'searchType: web (default), news, or image. ' +
    'count: results per page (1-20, default 10). ' +
    'offset: pagination offset (default 0). ' +
    'country: result country code (default US). ' +
    'language: result language code (default en). ' +
    'Returns: array of {title, url, description, age, source}.';
end;

// ── Registration ─────────────────────────────────────────────────────────────

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-brave-search',
    function: IAiMCPTool
    begin
      Result := TBraveSearchTool.Create;
    end);
  WriteLn(ErrOutput, '[MCPService]   + mcp-brave-search');
end;

end.
