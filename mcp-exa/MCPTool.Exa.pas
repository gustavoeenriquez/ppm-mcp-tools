unit MCPTool.Exa;

{
  MCPTool.Exa  ·  mcp-exa

  Exa AI-powered web search (exa.ai). Requires API key.

  Operations:
    search       - semantic or keyword web search
    get_contents - retrieve full page contents by URL or ID list
    find_similar - find pages similar to a given URL
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

  TExaParams = class
  private
    FOperation:          string;
    FApiKey:             string;
    FQuery:              string;
    FNumResults:         Integer;
    FSearchType:         string;
    FCategory:           string;
    FStartPublishedDate: string;
    FEndPublishedDate:   string;
    FIncludeDomains:     string;
    FExcludeDomains:     string;
    FIncludeText:        Boolean;
    FUrl:                string;
    FIds:                string;
    FMaxChars:           Integer;
  public
    constructor Create;

    [AiMCPSchemaDescription('Operation: search, get_contents, find_similar')]
    property Operation:          string  read FOperation          write FOperation;

    [AiMCPSchemaDescription('Exa API key')]
    property ApiKey:             string  read FApiKey             write FApiKey;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Search query (for search, find_similar)')]
    property Query:              string  read FQuery              write FQuery;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Number of results to return (default: 10, max: 100)')]
    property NumResults:         Integer read FNumResults         write FNumResults;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Search type: neural (semantic, default) or keyword')]
    property SearchType:         string  read FSearchType         write FSearchType;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Content category filter: news, research paper, github, tweet, movie, song, personal site, pdf')]
    property Category:           string  read FCategory           write FCategory;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Filter results published after this date (ISO 8601, e.g. 2024-01-01)')]
    property StartPublishedDate: string  read FStartPublishedDate write FStartPublishedDate;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Filter results published before this date (ISO 8601)')]
    property EndPublishedDate:   string  read FEndPublishedDate   write FEndPublishedDate;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Comma-separated domains to restrict search to (e.g. "github.com,arxiv.org")')]
    property IncludeDomains:     string  read FIncludeDomains     write FIncludeDomains;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Comma-separated domains to exclude from results')]
    property ExcludeDomains:     string  read FExcludeDomains     write FExcludeDomains;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Include full page text in results (default: false)')]
    property IncludeText:        Boolean read FIncludeText        write FIncludeText;

    [AiMCPOptional]
    [AiMCPSchemaDescription('URL to find similar pages for (for find_similar and get_contents)')]
    property Url:                string  read FUrl                write FUrl;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Comma-separated Exa document IDs to retrieve contents for (for get_contents)')]
    property Ids:                string  read FIds                write FIds;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Max characters of text to return per result (default: 2000, for get_contents)')]
    property MaxChars:           Integer read FMaxChars           write FMaxChars;
  end;

  TExaTool = class(TAiMCPToolBase<TExaParams>)
  private
    function ApiPost(const Endpoint, ApiKey, Body: string): string;
    function BuildDomainsArray(const Csv: string): TJSONArray;
    function DoSearch(const P: TExaParams): TJSONObject;
    function DoGetContents(const P: TExaParams): TJSONObject;
    function DoFindSimilar(const P: TExaParams): TJSONObject;
    function FormatResults(const RespStr: string): TJSONObject;
  protected
    function ExecuteWithParams(const AParams: TExaParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

procedure RegisterTools(AServer: TAiMCPServer);

implementation

const
  EXA_BASE = 'https://api.exa.ai';

{ TExaParams }

constructor TExaParams.Create;
begin
  inherited;
  FNumResults  := 10;
  FSearchType  := 'neural';
  FMaxChars    := 2000;
  FIncludeText := False;
end;

{ TExaTool }

function TExaTool.ApiPost(const Endpoint, ApiKey, Body: string): string;
var
  HTTP:   THTTPClient;
  Resp:   IHTTPResponse;
  Stream: TStringStream;
begin
  HTTP   := THTTPClient.Create;
  Stream := TStringStream.Create(Body, TEncoding.UTF8);
  try
    HTTP.ConnectionTimeout := 15000;
    HTTP.ResponseTimeout   := 30000;
    Resp := HTTP.Post(EXA_BASE + Endpoint, Stream, nil, [
      TNameValuePair.Create('x-api-key',    ApiKey),
      TNameValuePair.Create('Content-Type', 'application/json'),
      TNameValuePair.Create('Accept',       'application/json')
    ]);
    Result := Resp.ContentAsString;
    if Resp.StatusCode >= 400 then
      raise Exception.CreateFmt('Exa API HTTP %d: %s',
        [Resp.StatusCode, Result.Substring(0, 300)]);
  finally
    Stream.Free;
    HTTP.Free;
  end;
end;

function TExaTool.BuildDomainsArray(const Csv: string): TJSONArray;
var
  Parts: TArray<string>;
  S:     string;
begin
  Result := TJSONArray.Create;
  if Trim(Csv) = '' then Exit;
  Parts := Csv.Split([',']);
  for S in Parts do
    if Trim(S) <> '' then
      Result.Add(Trim(S));
end;

function TExaTool.FormatResults(const RespStr: string): TJSONObject;
var
  Parsed:  TJSONValue;
  Results: TJSONArray;
  Items:   TJSONArray;
  i:       Integer;
  Item:    TJSONObject;
  Out:     TJSONObject;
begin
  Result := TJSONObject.Create;
  Parsed := TJSONObject.ParseJSONValue(RespStr);
  try
    if not (Parsed is TJSONObject) then
    begin
      Result.AddPair('results', TJSONArray.Create);
      Result.AddPair('count',   TJSONNumber.Create(0));
      Result.AddPair('ok',      TJSONTrue.Create);
      Exit;
    end;

    var J := Parsed as TJSONObject;

    // Check for error
    var ErrMsg := J.GetValue<string>('error', '');
    if ErrMsg <> '' then
      raise Exception.Create('Exa: ' + ErrMsg);

    Items   := TJSONArray.Create;
    Results := nil;
    J.TryGetValue<TJSONArray>('results', Results);

    if Results <> nil then
      for i := 0 to Results.Count - 1 do
        if Results.Items[i] is TJSONObject then
        begin
          Item := Results.Items[i] as TJSONObject;
          Out  := TJSONObject.Create;
          Out.AddPair('id',            Item.GetValue<string>('id',            ''));
          Out.AddPair('url',           Item.GetValue<string>('url',           ''));
          Out.AddPair('title',         Item.GetValue<string>('title',         ''));
          Out.AddPair('score',         TJSONNumber.Create(Item.GetValue<Double>('score', 0)));
          Out.AddPair('publishedDate', Item.GetValue<string>('publishedDate', ''));
          Out.AddPair('author',        Item.GetValue<string>('author',        ''));
          // text content (if requested)
          var TextVal := Item.GetValue<string>('text', '');
          if TextVal <> '' then
            Out.AddPair('text', TextVal);
          // highlights
          var HL: TJSONArray := nil;
          if Item.TryGetValue<TJSONArray>('highlights', HL) and (HL <> nil) then
            Out.AddPair('highlights', HL.Clone as TJSONArray);
          Items.AddElement(Out);
        end;

    Result.AddPair('results', Items);
    Result.AddPair('count',   TJSONNumber.Create(Items.Count));
    Result.AddPair('ok',      TJSONTrue.Create);
  finally
    Parsed.Free;
  end;
end;

function TExaTool.DoSearch(const P: TExaParams): TJSONObject;
var
  Body:       TJSONObject;
  Num:        Integer;
  InclArr:    TJSONArray;
  ExclArr:    TJSONArray;
  ContentsObj: TJSONObject;
begin
  if Trim(P.Query) = '' then raise Exception.Create('"query" required for search');

  Num := P.NumResults;
  if Num <= 0 then Num := 10;

  Body := TJSONObject.Create;
  Body.AddPair('query',      P.Query);
  Body.AddPair('numResults', TJSONNumber.Create(Num));
  Body.AddPair('type',       LowerCase(Trim(P.SearchType)));

  if P.Category           <> '' then Body.AddPair('category',           P.Category);
  if P.StartPublishedDate <> '' then Body.AddPair('startPublishedDate', P.StartPublishedDate);
  if P.EndPublishedDate   <> '' then Body.AddPair('endPublishedDate',   P.EndPublishedDate);

  InclArr := BuildDomainsArray(P.IncludeDomains);
  if InclArr.Count > 0 then Body.AddPair('includeDomains', InclArr)
  else InclArr.Free;

  ExclArr := BuildDomainsArray(P.ExcludeDomains);
  if ExclArr.Count > 0 then Body.AddPair('excludeDomains', ExclArr)
  else ExclArr.Free;

  if P.IncludeText then
  begin
    ContentsObj := TJSONObject.Create;
    ContentsObj.AddPair('text', TJSONObject.Create.AddPair('maxCharacters',
      TJSONNumber.Create(P.MaxChars)) as TJSONValue);
    Body.AddPair('contents', ContentsObj);
  end;

  var RespStr := ApiPost('/search', P.ApiKey, Body.ToJSON);
  Body.Free;
  Result := FormatResults(RespStr);
end;

function TExaTool.DoGetContents(const P: TExaParams): TJSONObject;
var
  Body:    TJSONObject;
  IdsArr:  TJSONArray;
  Parts:   TArray<string>;
  S:       string;
  MaxCh:   Integer;
  ContObj: TJSONObject;
begin
  if (Trim(P.Ids) = '') and (Trim(P.Url) = '') then
    raise Exception.Create('"ids" or "url" required for get_contents');

  MaxCh := P.MaxChars;
  if MaxCh <= 0 then MaxCh := 2000;

  IdsArr := TJSONArray.Create;
  if Trim(P.Ids) <> '' then
  begin
    Parts := P.Ids.Split([',']);
    for S in Parts do
      if Trim(S) <> '' then IdsArr.Add(Trim(S));
  end;
  if Trim(P.Url) <> '' then
    IdsArr.Add(Trim(P.Url));

  ContObj := TJSONObject.Create;
  ContObj.AddPair('text', TJSONObject.Create.AddPair('maxCharacters',
    TJSONNumber.Create(MaxCh)) as TJSONValue);
  ContObj.AddPair('highlights', TJSONObject.Create.AddPair('numSentences',
    TJSONNumber.Create(3)) as TJSONValue);

  Body := TJSONObject.Create;
  Body.AddPair('ids',      IdsArr);
  Body.AddPair('contents', ContObj);

  var RespStr := ApiPost('/contents', P.ApiKey, Body.ToJSON);
  Body.Free;
  Result := FormatResults(RespStr);
end;

function TExaTool.DoFindSimilar(const P: TExaParams): TJSONObject;
var
  Body:       TJSONObject;
  Num:        Integer;
  InclArr:    TJSONArray;
  ExclArr:    TJSONArray;
  ContentsObj: TJSONObject;
begin
  if Trim(P.Url) = '' then raise Exception.Create('"url" required for find_similar');

  Num := P.NumResults;
  if Num <= 0 then Num := 10;

  Body := TJSONObject.Create;
  Body.AddPair('url',        P.Url);
  Body.AddPair('numResults', TJSONNumber.Create(Num));

  if P.StartPublishedDate <> '' then Body.AddPair('startPublishedDate', P.StartPublishedDate);
  if P.EndPublishedDate   <> '' then Body.AddPair('endPublishedDate',   P.EndPublishedDate);

  InclArr := BuildDomainsArray(P.IncludeDomains);
  if InclArr.Count > 0 then Body.AddPair('includeDomains', InclArr)
  else InclArr.Free;

  ExclArr := BuildDomainsArray(P.ExcludeDomains);
  if ExclArr.Count > 0 then Body.AddPair('excludeDomains', ExclArr)
  else ExclArr.Free;

  if P.IncludeText then
  begin
    ContentsObj := TJSONObject.Create;
    ContentsObj.AddPair('text', TJSONObject.Create.AddPair('maxCharacters',
      TJSONNumber.Create(P.MaxChars)) as TJSONValue);
    Body.AddPair('contents', ContentsObj);
  end;

  var RespStr := ApiPost('/findSimilar', P.ApiKey, Body.ToJSON);
  Body.Free;
  Result := FormatResults(RespStr);
end;

function TExaTool.ExecuteWithParams(const AParams: TExaParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op: string;
  R:  TJSONObject;
begin
  try
    if Trim(AParams.ApiKey) = '' then
      raise Exception.Create('"apiKey" is required');

    Op := LowerCase(Trim(AParams.Operation));
    if Op = '' then raise Exception.Create('"operation" is required');

    if      Op = 'search'       then R := DoSearch(AParams)
    else if Op = 'get_contents' then R := DoGetContents(AParams)
    else if Op = 'find_similar' then R := DoFindSimilar(AParams)
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

constructor TExaTool.Create;
begin
  inherited;
  FName        := 'mcp-exa';
  FDescription :=
    'Exa AI-powered semantic web search (exa.ai). Requires API key. ' +
    'Operations: ' +
    'search (semantic/keyword search; params: query, numResults?, searchType?, category?, ' +
    'startPublishedDate?, endPublishedDate?, includeDomains?, excludeDomains?, includeText?, maxChars?), ' +
    'get_contents (retrieve full page text; params: ids?, url?, maxChars?), ' +
    'find_similar (find pages similar to a URL; params: url, numResults?, includeDomains?, ' +
    'excludeDomains?, includeText?, maxChars?). ' +
    'searchType: neural (semantic, default) or keyword. ' +
    'category: news, research paper, github, tweet, movie, song, personal site, pdf.';
end;

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-exa',
    function: IAiMCPTool
    begin
      Result := TExaTool.Create;
    end);
  WriteLn(ErrOutput, '[MCPService]   + mcp-exa');
end;

end.
