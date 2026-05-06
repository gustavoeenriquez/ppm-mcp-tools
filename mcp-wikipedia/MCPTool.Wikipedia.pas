unit MCPTool.Wikipedia;

{
  MCPTool.Wikipedia  ·  mcp-wikipedia

  Wikipedia article search and retrieval via the Wikipedia REST API (free, no key).

  Operations:
    search  - search for articles by query
    summary - get a short summary of an article by title
    content - get full article extract (plain text)
    random  - get a random article summary
    langs   - list available Wikipedia language editions
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

  TWikiParams = class
  private
    FOperation: string;
    FQuery:     string;
    FTitle:     string;
    FLang:      string;
    FLimit:     Integer;
  public
    constructor Create;

    [AiMCPSchemaDescription('Operation: search, summary, content, random, langs')]
    property Operation: string  read FOperation write FOperation;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Search query (for search)')]
    property Query:     string  read FQuery     write FQuery;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Article title (for summary and content)')]
    property Title:     string  read FTitle     write FTitle;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Wikipedia language edition (default: en)')]
    property Lang:      string  read FLang      write FLang;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Maximum number of search results (default: 5)')]
    property Limit:     Integer read FLimit     write FLimit;
  end;

  TWikiTool = class(TAiMCPToolBase<TWikiParams>)
  private
    function HttpGet(const URL, UserAgent: string): string;
    function UrlEncode(const S: string): string;
    function DoSearch(const P: TWikiParams): TJSONObject;
    function DoSummary(const P: TWikiParams): TJSONObject;
    function DoContent(const P: TWikiParams): TJSONObject;
    function DoRandom(const P: TWikiParams): TJSONObject;
    function DoLangs(const P: TWikiParams): TJSONObject;
  protected
    function ExecuteWithParams(const AParams: TWikiParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

procedure RegisterTools(AServer: TAiMCPServer);

implementation

{ TWikiParams }

constructor TWikiParams.Create;
begin
  inherited;
  FLang  := 'en';
  FLimit := 5;
end;

{ TWikiTool }

function TWikiTool.HttpGet(const URL, UserAgent: string): string;
var
  HTTP: THTTPClient;
  Resp: IHTTPResponse;
begin
  HTTP := THTTPClient.Create;
  try
    HTTP.ConnectionTimeout := 10000;
    HTTP.ResponseTimeout   := 20000;
    Resp := HTTP.Get(URL, nil, [TNameValuePair.Create('User-Agent', UserAgent)]);
    if Resp.StatusCode = 404 then
      raise Exception.Create('Article not found');
    if Resp.StatusCode <> 200 then
      raise Exception.CreateFmt('HTTP %d', [Resp.StatusCode]);
    Result := Resp.ContentAsString;
  finally
    HTTP.Free;
  end;
end;

function TWikiTool.UrlEncode(const S: string): string;
begin
  Result := TNetEncoding.URL.EncodeQuery(S);
end;

function TWikiTool.DoSearch(const P: TWikiParams): TJSONObject;
var
  Lang:    string;
  Limit:   Integer;
  URL:     string;
  RespStr: string;
  Parsed:  TJSONValue;
  Search:  TJSONArray;
  Arr:     TJSONArray;
  i:       Integer;
begin
  if P.Query = '' then raise Exception.Create('"query" required for search');
  Lang  := LowerCase(Trim(P.Lang));
  if Lang = '' then Lang := 'en';
  Limit := P.Limit;
  if Limit <= 0 then Limit := 5;

  URL := Format('https://%s.wikipedia.org/w/api.php?action=query&list=search' +
    '&srsearch=%s&format=json&srlimit=%d&srprop=snippet|titlesnippet',
    [Lang, UrlEncode(P.Query), Limit]);

  RespStr := HttpGet(URL, 'mcp-wikipedia/1.0');
  Parsed  := TJSONObject.ParseJSONValue(RespStr);
  try
    Arr    := TJSONArray.Create;
    Search := nil;
    var QueryObj: TJSONObject := nil;
    if (Parsed is TJSONObject) then
      (Parsed as TJSONObject).TryGetValue<TJSONObject>('query', QueryObj);
    if QueryObj <> nil then
      QueryObj.TryGetValue<TJSONArray>('search', Search);

    if Search <> nil then
      for i := 0 to Search.Count - 1 do
      begin
        var Item := Search.Items[i] as TJSONObject;
        var R    := TJSONObject.Create;
        R.AddPair('title',   Item.GetValue<string>('title', ''));
        R.AddPair('snippet', Item.GetValue<string>('snippet', '').Replace('<span class="searchmatch">', '').Replace('</span>', ''));
        R.AddPair('pageid',  TJSONNumber.Create(Item.GetValue<Integer>('pageid', 0)));
        Arr.AddElement(R);
      end;

    Result := TJSONObject.Create;
    Result.AddPair('query',   P.Query);
    Result.AddPair('lang',    Lang);
    Result.AddPair('results', Arr);
    Result.AddPair('count',   TJSONNumber.Create(Arr.Count));
    Result.AddPair('ok',      TJSONTrue.Create);
  finally
    Parsed.Free;
  end;
end;

function TWikiTool.DoSummary(const P: TWikiParams): TJSONObject;
var
  Lang:    string;
  Title:   string;
  URL:     string;
  RespStr: string;
  Parsed:  TJSONValue;
  J:       TJSONObject;
begin
  if P.Title = '' then raise Exception.Create('"title" required for summary');
  Lang  := LowerCase(Trim(P.Lang));
  if Lang = '' then Lang := 'en';
  Title := UrlEncode(P.Title);

  URL     := Format('https://%s.wikipedia.org/api/rest_v1/page/summary/%s', [Lang, Title]);
  RespStr := HttpGet(URL, 'mcp-wikipedia/1.0');
  Parsed  := TJSONObject.ParseJSONValue(RespStr);
  try
    if not (Parsed is TJSONObject) then
      raise Exception.Create('Invalid response');
    J := Parsed as TJSONObject;

    Result := TJSONObject.Create;
    Result.AddPair('title',    J.GetValue<string>('title', ''));
    Result.AddPair('extract',  J.GetValue<string>('extract', ''));
    Result.AddPair('lang',     Lang);
    var PageURL := '';
    var ContentUrls: TJSONObject := nil;
    if J.TryGetValue<TJSONObject>('content_urls', ContentUrls) then
    begin
      var Desktop: TJSONObject := nil;
      if ContentUrls.TryGetValue<TJSONObject>('desktop', Desktop) then
        PageURL := Desktop.GetValue<string>('page', '');
    end;
    if PageURL <> '' then
      Result.AddPair('url', PageURL);
    Result.AddPair('ok', TJSONTrue.Create);
  finally
    Parsed.Free;
  end;
end;

function TWikiTool.DoContent(const P: TWikiParams): TJSONObject;
var
  Lang:    string;
  Title:   string;
  URL:     string;
  RespStr: string;
  Parsed:  TJSONValue;
  J:       TJSONObject;
  Pages:   TJSONObject;
  Extract: string;
begin
  if P.Title = '' then raise Exception.Create('"title" required for content');
  Lang  := LowerCase(Trim(P.Lang));
  if Lang = '' then Lang := 'en';
  Title := UrlEncode(P.Title);

  URL := Format('https://%s.wikipedia.org/w/api.php?action=query&titles=%s' +
    '&prop=extracts&exintro=false&explaintext=true&format=json', [Lang, Title]);
  RespStr := HttpGet(URL, 'mcp-wikipedia/1.0');
  Parsed  := TJSONObject.ParseJSONValue(RespStr);
  try
    if not (Parsed is TJSONObject) then
      raise Exception.Create('Invalid response');
    J := Parsed as TJSONObject;

    Extract := '';
    var QueryObj: TJSONObject := nil;
    if J.TryGetValue<TJSONObject>('query', QueryObj) then
    begin
      Pages := nil;
      if QueryObj.TryGetValue<TJSONObject>('pages', Pages) and (Pages.Count > 0) then
      begin
        var Page := Pages.Pairs[0].JsonValue as TJSONObject;
        Extract  := Page.GetValue<string>('extract', '');
      end;
    end;

    Result := TJSONObject.Create;
    Result.AddPair('title',   P.Title);
    Result.AddPair('lang',    Lang);
    Result.AddPair('extract', Extract);
    Result.AddPair('length',  TJSONNumber.Create(Length(Extract)));
    Result.AddPair('ok',      TJSONTrue.Create);
  finally
    Parsed.Free;
  end;
end;

function TWikiTool.DoRandom(const P: TWikiParams): TJSONObject;
var
  Lang:    string;
  URL:     string;
  RespStr: string;
  Parsed:  TJSONValue;
  J:       TJSONObject;
begin
  Lang := LowerCase(Trim(P.Lang));
  if Lang = '' then Lang := 'en';

  URL     := Format('https://%s.wikipedia.org/api/rest_v1/page/random/summary', [Lang]);
  RespStr := HttpGet(URL, 'mcp-wikipedia/1.0');
  Parsed  := TJSONObject.ParseJSONValue(RespStr);
  try
    if not (Parsed is TJSONObject) then
      raise Exception.Create('Invalid response');
    J := Parsed as TJSONObject;

    Result := TJSONObject.Create;
    Result.AddPair('title',   J.GetValue<string>('title', ''));
    Result.AddPair('extract', J.GetValue<string>('extract', ''));
    Result.AddPair('lang',    Lang);
    Result.AddPair('ok',      TJSONTrue.Create);
  finally
    Parsed.Free;
  end;
end;

function TWikiTool.DoLangs(const P: TWikiParams): TJSONObject;
var
  Arr: TJSONArray;
begin
  // Return the most common Wikipedia language editions
  Arr := TJSONArray.Create;
  Arr.Add('en'); Arr.Add('de'); Arr.Add('fr'); Arr.Add('es'); Arr.Add('it');
  Arr.Add('pt'); Arr.Add('ru'); Arr.Add('ja'); Arr.Add('zh'); Arr.Add('ar');
  Arr.Add('pl'); Arr.Add('nl'); Arr.Add('sv'); Arr.Add('uk'); Arr.Add('he');
  Arr.Add('fa'); Arr.Add('ko'); Arr.Add('ca'); Arr.Add('no'); Arr.Add('fi');

  Result := TJSONObject.Create;
  Result.AddPair('langs', Arr);
  Result.AddPair('note',  'Use lang code as "lang" parameter. Full list: https://meta.wikimedia.org/wiki/List_of_Wikipedias');
  Result.AddPair('ok',    TJSONTrue.Create);
end;

function TWikiTool.ExecuteWithParams(const AParams: TWikiParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op: string;
  R:  TJSONObject;
begin
  try
    Op := LowerCase(Trim(AParams.Operation));
    if Op = '' then raise Exception.Create('"operation" is required');

    if      Op = 'search'  then R := DoSearch(AParams)
    else if Op = 'summary' then R := DoSummary(AParams)
    else if Op = 'content' then R := DoContent(AParams)
    else if Op = 'random'  then R := DoRandom(AParams)
    else if Op = 'langs'   then R := DoLangs(AParams)
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

constructor TWikiTool.Create;
begin
  inherited;
  FName        := 'mcp-wikipedia';
  FDescription :=
    'Wikipedia article search and retrieval (free, no API key required). ' +
    'Operations: ' +
    'search (search articles; params: query, lang?, limit?), ' +
    'summary (get article summary; params: title, lang?), ' +
    'content (get full article text; params: title, lang?), ' +
    'random (get random article summary; param: lang?), ' +
    'langs (list available language editions). ' +
    'Default language: en. Supports 300+ language editions.';
end;

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-wikipedia',
    function: IAiMCPTool
    begin
      Result := TWikiTool.Create;
    end);
  WriteLn(ErrOutput, '[mcp-wikipedia] ready');
end;

end.
