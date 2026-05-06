unit MCPTool.Firecrawl;

{
  MCPTool.Firecrawl  ·  mcp-firecrawl  (port 8621)
  Web scraping and crawling via Firecrawl API (api.firecrawl.dev).

  Operations:
    scrape      - scrape a single URL → clean markdown/HTML
    crawl       - crawl a website and return multiple pages
    crawl_check - check status of an async crawl job
    map         - get all URLs from a website sitemap
    extract     - extract structured data from a URL using AI schema
    search      - search the web and scrape top results
}

interface

uses
  uMakerAi.MCPServer.Core,
  System.JSON;

type
  TFirecrawlParams = class
  private
    FOperation:     string;
    FApiKey:        string;
    FURL:           string;
    FJobId:         string;
    FFormats:       string;
    FOnlyMainContent: Boolean;
    FIncludeTags:   string;
    FExcludeTags:   string;
    FLimit:         Integer;
    FMaxDepth:      Integer;
    FAllowBackwardLinks: Boolean;
    FSchema:        string;
    FQuery:         string;
    FWaitFor:       Integer;
  public
    constructor Create;

    [AiMCPSchemaDescription('Operation: scrape, crawl, crawl_check, map, extract, search')]
    property Operation:     string  read FOperation     write FOperation;

    [AiMCPSchemaDescription('Firecrawl API key (get at firecrawl.dev)')]
    property ApiKey:        string  read FApiKey        write FApiKey;

    [AiMCPOptional]
    [AiMCPSchemaDescription('URL to scrape/crawl/map')]
    property URL:           string  read FURL           write FURL;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Crawl job ID (for crawl_check)')]
    property JobId:         string  read FJobId         write FJobId;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Output formats: markdown,html,rawHtml,links,screenshot (comma-sep, default: markdown)')]
    property Formats:       string  read FFormats       write FFormats;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Extract only main content, skip nav/footer/ads (default: true)')]
    property OnlyMainContent: Boolean read FOnlyMainContent write FOnlyMainContent;

    [AiMCPOptional]
    [AiMCPSchemaDescription('HTML tags to include (comma-sep, e.g. article,main)')]
    property IncludeTags:   string  read FIncludeTags   write FIncludeTags;

    [AiMCPOptional]
    [AiMCPSchemaDescription('HTML tags to exclude (comma-sep, e.g. nav,footer,aside)')]
    property ExcludeTags:   string  read FExcludeTags   write FExcludeTags;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Max pages for crawl / max results for search (default: 10)')]
    property Limit:         Integer read FLimit         write FLimit;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Max crawl depth from start URL (default: 2)')]
    property MaxDepth:      Integer read FMaxDepth      write FMaxDepth;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Allow crawling links that go up to parent paths (default: false)')]
    property AllowBackwardLinks: Boolean read FAllowBackwardLinks write FAllowBackwardLinks;

    [AiMCPOptional]
    [AiMCPSchemaDescription('JSON schema for structured extraction (for extract operation)')]
    property Schema:        string  read FSchema        write FSchema;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Search query (for search operation)')]
    property Query:         string  read FQuery         write FQuery;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Wait time in ms for dynamic pages (default: 0)')]
    property WaitFor:       Integer read FWaitFor       write FWaitFor;
  end;

  TFirecrawlTool = class(TAiMCPToolBase<TFirecrawlParams>)
  private
    function ApiPost(const Endpoint, Body, ApiKey: string): string;
    function ApiGet(const Endpoint, ApiKey: string): string;
    function BuildFormatsArray(const Formats: string): string;
    function BuildTagsArray(const Tags: string): string;
    function DoScrape(const P: TFirecrawlParams): TJSONObject;
    function DoCrawl(const P: TFirecrawlParams): TJSONObject;
    function DoCrawlCheck(const P: TFirecrawlParams): TJSONObject;
    function DoMap(const P: TFirecrawlParams): TJSONObject;
    function DoExtract(const P: TFirecrawlParams): TJSONObject;
    function DoSearch(const P: TFirecrawlParams): TJSONObject;
  protected
    function ExecuteWithParams(const AParams: TFirecrawlParams;
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

const
  BASE_URL = 'https://api.firecrawl.dev/v1';

{ TFirecrawlParams }

constructor TFirecrawlParams.Create;
begin
  inherited;
  FFormats         := 'markdown';
  FOnlyMainContent := True;
  FLimit           := 10;
  FMaxDepth        := 2;
  FAllowBackwardLinks := False;
end;

{ TFirecrawlTool }

function TFirecrawlTool.ApiPost(const Endpoint, Body, ApiKey: string): string;
var
  HTTP:   THTTPClient;
  Stream: TStringStream;
  Resp:   IHTTPResponse;
begin
  HTTP   := THTTPClient.Create;
  Stream := TStringStream.Create(Body, TEncoding.UTF8);
  try
    Resp := HTTP.Post(BASE_URL + Endpoint, Stream, nil,
      [TNameValuePair.Create('Content-Type',  'application/json'),
       TNameValuePair.Create('Authorization', 'Bearer ' + ApiKey)]);
    Result := Resp.ContentAsString(TEncoding.UTF8);
  finally
    Stream.Free;
    HTTP.Free;
  end;
end;

function TFirecrawlTool.ApiGet(const Endpoint, ApiKey: string): string;
var
  HTTP: THTTPClient;
  Resp: IHTTPResponse;
begin
  HTTP := THTTPClient.Create;
  try
    Resp := HTTP.Get(BASE_URL + Endpoint, nil,
      [TNameValuePair.Create('Authorization', 'Bearer ' + ApiKey)]);
    Result := Resp.ContentAsString(TEncoding.UTF8);
  finally
    HTTP.Free;
  end;
end;

function TFirecrawlTool.BuildFormatsArray(const Formats: string): string;
var
  Parts: TArray<string>;
  i: Integer;
begin
  if Trim(Formats) = '' then Exit('["markdown"]');
  Parts  := Trim(Formats).Split([',']);
  Result := '[';
  for i := 0 to High(Parts) do
  begin
    if i > 0 then Result := Result + ',';
    Result := Result + '"' + Trim(Parts[i]) + '"';
  end;
  Result := Result + ']';
end;

function TFirecrawlTool.BuildTagsArray(const Tags: string): string;
var
  Parts: TArray<string>;
  i: Integer;
begin
  if Trim(Tags) = '' then Exit('');
  Parts  := Trim(Tags).Split([',']);
  Result := '[';
  for i := 0 to High(Parts) do
  begin
    if i > 0 then Result := Result + ',';
    Result := Result + '"' + Trim(Parts[i]) + '"';
  end;
  Result := Result + ']';
end;

function TFirecrawlTool.DoScrape(const P: TFirecrawlParams): TJSONObject;
var
  Fmts, OMC, Body, Raw: string;
  J: TJSONValue;
begin
  if Trim(P.URL) = '' then raise Exception.Create('"url" required for scrape');
  Fmts := BuildFormatsArray(P.Formats);
  if P.OnlyMainContent then OMC := 'true' else OMC := 'false';

  Body := Format('{"url":"%s","formats":%s,"onlyMainContent":%s',
    [Trim(P.URL).Replace('"','\"'), Fmts, OMC]);

  var Inc := BuildTagsArray(P.IncludeTags);
  var Exc := BuildTagsArray(P.ExcludeTags);
  if Inc <> '' then Body := Body + ',"includeTags":' + Inc;
  if Exc <> '' then Body := Body + ',"excludeTags":' + Exc;
  if P.WaitFor > 0 then Body := Body + Format(',"waitFor":%d', [P.WaitFor]);
  Body := Body + '}';

  Raw := ApiPost('/scrape', Body, Trim(P.ApiKey));
  J   := TJSONObject.ParseJSONValue(Raw);
  try
    Result := TJSONObject.Create;
    if Assigned(J) then
      Result.AddPair('result', J.Clone as TJSONValue)
    else
      Result.AddPair('raw', TJSONString.Create(Raw));
    Result.AddPair('ok', TJSONTrue.Create);
  finally
    J.Free;
  end;
end;

function TFirecrawlTool.DoCrawl(const P: TFirecrawlParams): TJSONObject;
var
  Fmts, OMC, BL, Body, Raw: string;
  J: TJSONValue;
begin
  if Trim(P.URL) = '' then raise Exception.Create('"url" required for crawl');
  Fmts := BuildFormatsArray(P.Formats);
  if P.OnlyMainContent     then OMC := 'true' else OMC := 'false';
  if P.AllowBackwardLinks  then BL  := 'true' else BL  := 'false';

  Body := Format('{"url":"%s","limit":%d,"maxDepth":%d,"allowBackwardLinks":%s,' +
    '"scrapeOptions":{"formats":%s,"onlyMainContent":%s}}',
    [Trim(P.URL).Replace('"','\"'), P.Limit, P.MaxDepth, BL, Fmts, OMC]);

  Raw := ApiPost('/crawl', Body, Trim(P.ApiKey));
  J   := TJSONObject.ParseJSONValue(Raw);
  try
    Result := TJSONObject.Create;
    if Assigned(J) then
      Result.AddPair('result', J.Clone as TJSONValue)
    else
      Result.AddPair('raw', TJSONString.Create(Raw));
    Result.AddPair('ok', TJSONTrue.Create);
  finally
    J.Free;
  end;
end;

function TFirecrawlTool.DoCrawlCheck(const P: TFirecrawlParams): TJSONObject;
var
  Raw: string;
  J:   TJSONValue;
begin
  if Trim(P.JobId) = '' then raise Exception.Create('"jobId" required for crawl_check');
  Raw := ApiGet('/crawl/' + Trim(P.JobId), Trim(P.ApiKey));
  J   := TJSONObject.ParseJSONValue(Raw);
  try
    Result := TJSONObject.Create;
    if Assigned(J) then
      Result.AddPair('result', J.Clone as TJSONValue)
    else
      Result.AddPair('raw', TJSONString.Create(Raw));
    Result.AddPair('ok', TJSONTrue.Create);
  finally
    J.Free;
  end;
end;

function TFirecrawlTool.DoMap(const P: TFirecrawlParams): TJSONObject;
var
  Body, Raw: string;
  J:         TJSONValue;
begin
  if Trim(P.URL) = '' then raise Exception.Create('"url" required for map');
  Body := Format('{"url":"%s","limit":%d}',
    [Trim(P.URL).Replace('"','\"'), P.Limit]);

  Raw := ApiPost('/map', Body, Trim(P.ApiKey));
  J   := TJSONObject.ParseJSONValue(Raw);
  try
    Result := TJSONObject.Create;
    if Assigned(J) then
    begin
      var Links := J.FindValue('links');
      if Assigned(Links) then
        Result.AddPair('links', Links.Clone as TJSONValue)
      else
        Result.AddPair('result', J.Clone as TJSONValue);
    end
    else
      Result.AddPair('raw', TJSONString.Create(Raw));
    Result.AddPair('ok', TJSONTrue.Create);
  finally
    J.Free;
  end;
end;

function TFirecrawlTool.DoExtract(const P: TFirecrawlParams): TJSONObject;
var
  Schema, Body, Raw: string;
  J: TJSONValue;
begin
  if Trim(P.URL) = '' then raise Exception.Create('"url" required for extract');
  Schema := Trim(P.Schema);

  Body := Format('{"urls":["%s"]', [Trim(P.URL).Replace('"','\"')]);
  if Schema <> '' then
    Body := Body + ',"schema":' + Schema;
  Body := Body + '}';

  Raw := ApiPost('/extract', Body, Trim(P.ApiKey));
  J   := TJSONObject.ParseJSONValue(Raw);
  try
    Result := TJSONObject.Create;
    if Assigned(J) then
      Result.AddPair('result', J.Clone as TJSONValue)
    else
      Result.AddPair('raw', TJSONString.Create(Raw));
    Result.AddPair('ok', TJSONTrue.Create);
  finally
    J.Free;
  end;
end;

function TFirecrawlTool.DoSearch(const P: TFirecrawlParams): TJSONObject;
var
  Fmts, OMC, Body, Raw: string;
  J: TJSONValue;
begin
  if Trim(P.Query) = '' then raise Exception.Create('"query" required for search');
  Fmts := BuildFormatsArray(P.Formats);
  if P.OnlyMainContent then OMC := 'true' else OMC := 'false';

  Body := Format('{"query":"%s","limit":%d,"scrapeOptions":{"formats":%s,"onlyMainContent":%s}}',
    [Trim(P.Query).Replace('"','\"'), P.Limit, Fmts, OMC]);

  Raw := ApiPost('/search', Body, Trim(P.ApiKey));
  J   := TJSONObject.ParseJSONValue(Raw);
  try
    Result := TJSONObject.Create;
    if Assigned(J) then
    begin
      var Data := J.FindValue('data');
      if Assigned(Data) then
        Result.AddPair('results', Data.Clone as TJSONValue)
      else
        Result.AddPair('result', J.Clone as TJSONValue);
    end
    else
      Result.AddPair('raw', TJSONString.Create(Raw));
    Result.AddPair('ok', TJSONTrue.Create);
  finally
    J.Free;
  end;
end;

function TFirecrawlTool.ExecuteWithParams(const AParams: TFirecrawlParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op: string;
  R:  TJSONObject;
begin
  try
    Op := LowerCase(Trim(AParams.Operation));
    if Op = '' then raise Exception.Create('"operation" is required');
    if Trim(AParams.ApiKey) = '' then raise Exception.Create('"apiKey" is required');

    if      Op = 'scrape'      then R := DoScrape(AParams)
    else if Op = 'crawl'       then R := DoCrawl(AParams)
    else if Op = 'crawl_check' then R := DoCrawlCheck(AParams)
    else if Op = 'map'         then R := DoMap(AParams)
    else if Op = 'extract'     then R := DoExtract(AParams)
    else if Op = 'search'      then R := DoSearch(AParams)
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

constructor TFirecrawlTool.Create;
begin
  inherited;
  FName        := 'mcp-firecrawl';
  FDescription :=
    'Web scraping and crawling via Firecrawl API. ' +
    'Operations: scrape (params: url, formats?, onlyMainContent?, includeTags?, excludeTags?, waitFor?), ' +
    'crawl (params: url, limit?, maxDepth?, allowBackwardLinks?, formats?) → returns jobId for async crawl, ' +
    'crawl_check (params: jobId) → get crawl status and results, ' +
    'map (params: url, limit?) → all URLs from site, ' +
    'extract (params: url, schema=JSON schema) → AI structured extraction, ' +
    'search (params: query, limit?, formats?) → web search + scrape. ' +
    'Required: apiKey. Formats: markdown,html,rawHtml,links,screenshot.';
end;

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-firecrawl',
    function: IAiMCPTool
    begin
      Result := TFirecrawlTool.Create;
    end);
  WriteLn(ErrOutput, '[MCPService]   + mcp-firecrawl');
end;

end.
