unit MCPTool.Jina;

{
  MCPTool.Jina  ·  mcp-jina  (port 8622)
  Jina AI: web reader, search, embeddings and reranking via Jina API.

  Operations:
    read      - read/scrape a URL → clean markdown (r.jina.ai)
    search    - web search with page content (s.jina.ai)
    embed     - generate text embeddings (api.jina.ai/v1/embeddings)
    rerank    - rerank documents by query relevance (api.jina.ai/v1/rerank)
    classify  - zero-shot text classification (api.jina.ai/v1/classify)
    segment   - tokenize/segment text (api.jina.ai/v1/segment)
}

interface

uses
  uMakerAi.MCPServer.Core,
  System.JSON,
  System.Net.URLClient;

type
  TJinaParams = class
  private
    FOperation:  string;
    FApiKey:     string;
    FURL:        string;
    FQuery:      string;
    FTexts:      string;
    FModel:      string;
    FDocuments:  string;
    FTopN:       Integer;
    FLabels:     string;
    FReturnFull: Boolean;
    FWithLinks:  Boolean;
    FWithImages: Boolean;
    FTimeout:    Integer;
  public
    constructor Create;

    [AiMCPSchemaDescription('Operation: read, search, embed, rerank, classify, segment')]
    property Operation:  string  read FOperation  write FOperation;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Jina API key (free tier available at jina.ai)')]
    property ApiKey:     string  read FApiKey     write FApiKey;

    [AiMCPOptional]
    [AiMCPSchemaDescription('URL to read (for read operation)')]
    property URL:        string  read FURL        write FURL;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Search query (for search/rerank) or text to segment')]
    property Query:      string  read FQuery      write FQuery;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Texts as JSON string array: ["text1","text2"] (for embed/classify)')]
    property Texts:      string  read FTexts      write FTexts;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Embedding/reranking model (e.g. jina-embeddings-v3, jina-reranker-v2-base-multilingual)')]
    property Model:      string  read FModel      write FModel;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Documents to rerank as JSON string array: ["doc1","doc2"] (for rerank)')]
    property Documents:  string  read FDocuments  write FDocuments;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Number of top results for rerank (default: all)')]
    property TopN:       Integer read FTopN       write FTopN;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Class labels as JSON string array: ["label1","label2"] (for classify)')]
    property Labels:     string  read FLabels     write FLabels;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Return full document content in rerank results (default: false)')]
    property ReturnFull: Boolean read FReturnFull write FReturnFull;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Include links in reader output (default: false)')]
    property WithLinks:  Boolean read FWithLinks  write FWithLinks;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Include image captions in reader output (default: false)')]
    property WithImages: Boolean read FWithImages write FWithImages;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Request timeout in seconds (default: 30)')]
    property Timeout:    Integer read FTimeout    write FTimeout;
  end;

  TJinaTool = class(TAiMCPToolBase<TJinaParams>)
  private
    function ApiGet(const URL: string; const Headers: TArray<TNameValuePair>): string;
    function ApiPost(const URL, Body: string; const Headers: TArray<TNameValuePair>): string;
    function AuthHeader(const ApiKey: string): TNameValuePair;
    function DoRead(const P: TJinaParams): TJSONObject;
    function DoSearch(const P: TJinaParams): TJSONObject;
    function DoEmbed(const P: TJinaParams): TJSONObject;
    function DoRerank(const P: TJinaParams): TJSONObject;
    function DoClassify(const P: TJinaParams): TJSONObject;
    function DoSegment(const P: TJinaParams): TJSONObject;
  protected
    function ExecuteWithParams(const AParams: TJinaParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

procedure RegisterTools(AServer: TAiMCPServer);

implementation

uses
  System.SysUtils,
  System.Classes,
  System.Net.HttpClient;

{ TJinaParams }

constructor TJinaParams.Create;
begin
  inherited;
  FReturnFull := False;
  FWithLinks  := False;
  FWithImages := False;
  FTimeout    := 30;
end;

{ TJinaTool }

function TJinaTool.AuthHeader(const ApiKey: string): TNameValuePair;
begin
  Result := TNameValuePair.Create('Authorization', 'Bearer ' + ApiKey);
end;

function TJinaTool.ApiGet(const URL: string;
  const Headers: TArray<TNameValuePair>): string;
var
  HTTP: THTTPClient;
  Resp: IHTTPResponse;
begin
  HTTP := THTTPClient.Create;
  try
    Resp   := HTTP.Get(URL, nil, Headers);
    Result := Resp.ContentAsString(TEncoding.UTF8);
  finally
    HTTP.Free;
  end;
end;

function TJinaTool.ApiPost(const URL, Body: string;
  const Headers: TArray<TNameValuePair>): string;
var
  HTTP:   THTTPClient;
  Stream: TStringStream;
  Resp:   IHTTPResponse;
begin
  HTTP   := THTTPClient.Create;
  Stream := TStringStream.Create(Body, TEncoding.UTF8);
  try
    Resp   := HTTP.Post(URL, Stream, nil, Headers);
    Result := Resp.ContentAsString(TEncoding.UTF8);
  finally
    Stream.Free;
    HTTP.Free;
  end;
end;

function TJinaTool.DoRead(const P: TJinaParams): TJSONObject;
var
  URL, Raw: string;
  Headers:  TArray<TNameValuePair>;
  J:        TJSONValue;
begin
  if Trim(P.URL) = '' then raise Exception.Create('"url" required for read');

  URL := 'https://r.jina.ai/' + Trim(P.URL);

  if Trim(P.ApiKey) <> '' then
  begin
    Headers := [AuthHeader(Trim(P.ApiKey)),
                TNameValuePair.Create('Accept', 'application/json'),
                TNameValuePair.Create('X-Return-Format', 'markdown')];
    if P.WithLinks  then
      Headers := Headers + [TNameValuePair.Create('X-With-Links-Summary', 'true')];
    if P.WithImages then
      Headers := Headers + [TNameValuePair.Create('X-With-Images-Summary', 'true')];
  end
  else
    Headers := [TNameValuePair.Create('Accept', 'application/json')];

  Raw := ApiGet(URL, Headers);
  J   := TJSONObject.ParseJSONValue(Raw);
  try
    Result := TJSONObject.Create;
    if Assigned(J) then
      Result.AddPair('result', J.Clone as TJSONValue)
    else
      Result.AddPair('content', TJSONString.Create(Raw));
    Result.AddPair('ok', TJSONTrue.Create);
  finally
    J.Free;
  end;
end;

function TJinaTool.DoSearch(const P: TJinaParams): TJSONObject;
var
  URL, Raw, Q: string;
  Headers: TArray<TNameValuePair>;
  J: TJSONValue;
begin
  Q := Trim(P.Query);
  if Q = '' then raise Exception.Create('"query" required for search');

  URL := 'https://s.jina.ai/' + Q.Replace(' ', '%20').Replace('"','%22');

  Headers := [TNameValuePair.Create('Accept', 'application/json')];
  if Trim(P.ApiKey) <> '' then
    Headers := Headers + [AuthHeader(Trim(P.ApiKey))];
  if P.WithLinks then
    Headers := Headers + [TNameValuePair.Create('X-With-Links-Summary', 'true')];

  Raw := ApiGet(URL, Headers);
  J   := TJSONObject.ParseJSONValue(Raw);
  try
    Result := TJSONObject.Create;
    if Assigned(J) then
      Result.AddPair('result', J.Clone as TJSONValue)
    else
      Result.AddPair('content', TJSONString.Create(Raw));
    Result.AddPair('ok', TJSONTrue.Create);
  finally
    J.Free;
  end;
end;

function TJinaTool.DoEmbed(const P: TJinaParams): TJSONObject;
var
  Model, Body, Raw: string;
  J: TJSONValue;
begin
  if Trim(P.Texts) = '' then raise Exception.Create('"texts" required: JSON string array');
  Model := Trim(P.Model);
  if Model = '' then Model := 'jina-embeddings-v3';

  Body := Format('{"model":"%s","input":%s}', [Model, Trim(P.Texts)]);
  Raw  := ApiPost('https://api.jina.ai/v1/embeddings', Body,
    [TNameValuePair.Create('Content-Type', 'application/json'),
     AuthHeader(Trim(P.ApiKey))]);

  J := TJSONObject.ParseJSONValue(Raw);
  try
    Result := TJSONObject.Create;
    if Assigned(J) then
    begin
      var Data := J.FindValue('data');
      if Assigned(Data) then
        Result.AddPair('embeddings', Data.Clone as TJSONValue)
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

function TJinaTool.DoRerank(const P: TJinaParams): TJSONObject;
var
  Model, Body, Raw, RF: string;
  J: TJSONValue;
begin
  if Trim(P.Query)     = '' then raise Exception.Create('"query" required for rerank');
  if Trim(P.Documents) = '' then raise Exception.Create('"documents" required: JSON string array');
  Model := Trim(P.Model);
  if Model = '' then Model := 'jina-reranker-v2-base-multilingual';
  if P.ReturnFull then RF := 'true' else RF := 'false';

  Body := Format('{"model":"%s","query":"%s","documents":%s,"return_documents":%s',
    [Model, P.Query.Replace('"','\"'), Trim(P.Documents), RF]);
  if P.TopN > 0 then
    Body := Body + Format(',"top_n":%d', [P.TopN]);
  Body := Body + '}';

  Raw := ApiPost('https://api.jina.ai/v1/rerank', Body,
    [TNameValuePair.Create('Content-Type', 'application/json'),
     AuthHeader(Trim(P.ApiKey))]);

  J := TJSONObject.ParseJSONValue(Raw);
  try
    Result := TJSONObject.Create;
    if Assigned(J) then
    begin
      var Results := J.FindValue('results');
      if Assigned(Results) then
        Result.AddPair('results', Results.Clone as TJSONValue)
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

function TJinaTool.DoClassify(const P: TJinaParams): TJSONObject;
var
  Model, Body, Raw: string;
  J: TJSONValue;
begin
  if Trim(P.Texts)  = '' then raise Exception.Create('"texts" required: JSON string array');
  if Trim(P.Labels) = '' then raise Exception.Create('"labels" required: JSON string array');
  Model := Trim(P.Model);
  if Model = '' then Model := 'jina-embeddings-v3';

  Body := Format('{"model":"%s","input":%s,"labels":%s}',
    [Model, Trim(P.Texts), Trim(P.Labels)]);

  Raw := ApiPost('https://api.jina.ai/v1/classify', Body,
    [TNameValuePair.Create('Content-Type', 'application/json'),
     AuthHeader(Trim(P.ApiKey))]);

  J := TJSONObject.ParseJSONValue(Raw);
  try
    Result := TJSONObject.Create;
    if Assigned(J) then
    begin
      var Data := J.FindValue('data');
      if Assigned(Data) then
        Result.AddPair('classifications', Data.Clone as TJSONValue)
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

function TJinaTool.DoSegment(const P: TJinaParams): TJSONObject;
var
  Content, Body, Raw: string;
  J: TJSONValue;
begin
  Content := Trim(P.Query);
  if Content = '' then raise Exception.Create('"query" (text to segment) required');

  Body := Format('{"content":"%s","return_tokens":true,"return_chunks":true}',
    [Content.Replace('\','\\').Replace('"','\"').Replace(#10,'\n').Replace(#13,'')]);

  Raw := ApiPost('https://api.jina.ai/v1/segment', Body,
    [TNameValuePair.Create('Content-Type', 'application/json'),
     AuthHeader(Trim(P.ApiKey))]);

  J := TJSONObject.ParseJSONValue(Raw);
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

function TJinaTool.ExecuteWithParams(const AParams: TJinaParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op: string;
  R:  TJSONObject;
begin
  try
    Op := LowerCase(Trim(AParams.Operation));
    if Op = '' then raise Exception.Create('"operation" is required');

    if      Op = 'read'     then R := DoRead(AParams)
    else if Op = 'search'   then R := DoSearch(AParams)
    else if Op = 'embed'    then R := DoEmbed(AParams)
    else if Op = 'rerank'   then R := DoRerank(AParams)
    else if Op = 'classify' then R := DoClassify(AParams)
    else if Op = 'segment'  then R := DoSegment(AParams)
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

constructor TJinaTool.Create;
begin
  inherited;
  FName        := 'mcp-jina';
  FDescription :=
    'Jina AI: web reader, search, embeddings, reranking and classification. ' +
    'Operations: read (params: url, withLinks?, withImages?) → clean markdown, ' +
    'search (params: query, withLinks?) → web search with content, ' +
    'embed (params: texts=JSON array, model?) → text embeddings, ' +
    'rerank (params: query, documents=JSON array, model?, topN?, returnFull?) → relevance ranking, ' +
    'classify (params: texts=JSON array, labels=JSON array, model?) → zero-shot classification, ' +
    'segment (params: query=text) → tokenization and chunking. ' +
    'apiKey optional for read/search (rate limited without key), required for embed/rerank/classify/segment.';
end;

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-jina',
    function: IAiMCPTool
    begin
      Result := TJinaTool.Create;
    end);
  WriteLn(ErrOutput, '[MCPService]   + mcp-jina');
end;

end.
