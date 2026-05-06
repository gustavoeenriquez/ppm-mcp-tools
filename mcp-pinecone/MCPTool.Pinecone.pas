unit MCPTool.Pinecone;

{
  MCPTool.Pinecone  ·  mcp-pinecone  (port 8618)
  Pinecone vector database via REST API.

  Control plane (api.pinecone.io):
    list_indexes      - list all indexes
    describe_index    - get index details

  Data plane (index-specific host):
    query             - vector similarity search
    upsert            - insert or update vectors
    fetch             - retrieve vectors by IDs
    delete            - delete vectors by IDs, filter, or all
    list_vectors      - list vector IDs in a namespace
    describe_stats    - index statistics (namespaces, dimensions, counts)
}

interface

uses
  uMakerAi.MCPServer.Core,
  System.JSON;

type
  TPineconeParams = class
  private
    FOperation:        string;
    FApiKey:           string;
    FIndexName:        string;
    FIndexHost:        string;
    FVector:           string;
    FTopK:             Integer;
    FNamespace:        string;
    FFilter:           string;
    FIds:              string;
    FVectors:          string;
    FIncludeValues:    Boolean;
    FIncludeMetadata:  Boolean;
    FDeleteAll:        Boolean;
    FLimit:            Integer;
    FPaginationToken:  string;
  public
    constructor Create;

    [AiMCPSchemaDescription('Operation: list_indexes, describe_index, query, upsert, fetch, delete, list_vectors, describe_stats')]
    property Operation:       string  read FOperation       write FOperation;

    [AiMCPSchemaDescription('Pinecone API key')]
    property ApiKey:          string  read FApiKey          write FApiKey;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Index name (for list_indexes, describe_index)')]
    property IndexName:       string  read FIndexName       write FIndexName;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Index host URL for data operations (e.g. https://my-index-abc.svc.us-east-1.pinecone.io)')]
    property IndexHost:       string  read FIndexHost       write FIndexHost;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Query vector as JSON float array: [0.1, 0.2, ...] (for query)')]
    property Vector:          string  read FVector          write FVector;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Number of results to return (default: 10)')]
    property TopK:            Integer read FTopK            write FTopK;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Namespace to query/upsert/delete within (optional)')]
    property Namespace:       string  read FNamespace       write FNamespace;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Metadata filter as JSON: {"genre":{"$eq":"action"}}')]
    property Filter:          string  read FFilter          write FFilter;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Vector IDs as JSON string array: ["id1","id2"] (for fetch/delete)')]
    property Ids:             string  read FIds             write FIds;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Vectors to upsert as JSON array: [{"id":"id1","values":[0.1,...],"metadata":{...}},...]')]
    property Vectors:         string  read FVectors         write FVectors;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Include vector values in results (default: false)')]
    property IncludeValues:   Boolean read FIncludeValues   write FIncludeValues;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Include metadata in results (default: true)')]
    property IncludeMetadata: Boolean read FIncludeMetadata write FIncludeMetadata;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Delete all vectors in namespace (for delete with deleteAll=true)')]
    property DeleteAll:       Boolean read FDeleteAll       write FDeleteAll;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Max vector IDs to return for list_vectors (default: 100)')]
    property Limit:           Integer read FLimit           write FLimit;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Pagination token for list_vectors (from previous response)')]
    property PaginationToken: string  read FPaginationToken write FPaginationToken;
  end;

  TPineconeTool = class(TAiMCPToolBase<TPineconeParams>)
  private
    function ControlURL: string;
    function DataURL(const P: TPineconeParams): string;
    function ApiGet(const URL, ApiKey: string): string;
    function ApiPost(const URL, Body, ApiKey: string): string;
    function DoListIndexes(const P: TPineconeParams): TJSONObject;
    function DoDescribeIndex(const P: TPineconeParams): TJSONObject;
    function DoQuery(const P: TPineconeParams): TJSONObject;
    function DoUpsert(const P: TPineconeParams): TJSONObject;
    function DoFetch(const P: TPineconeParams): TJSONObject;
    function DoDelete(const P: TPineconeParams): TJSONObject;
    function DoListVectors(const P: TPineconeParams): TJSONObject;
    function DoDescribeStats(const P: TPineconeParams): TJSONObject;
  protected
    function ExecuteWithParams(const AParams: TPineconeParams;
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

{ TPineconeParams }

constructor TPineconeParams.Create;
begin
  inherited;
  FTopK            := 10;
  FLimit           := 100;
  FIncludeValues   := False;
  FIncludeMetadata := True;
end;

{ TPineconeTool }

function TPineconeTool.ControlURL: string;
begin
  Result := 'https://api.pinecone.io';
end;

function TPineconeTool.DataURL(const P: TPineconeParams): string;
var
  H: string;
begin
  H := Trim(P.IndexHost);
  if H = '' then
    raise Exception.Create('"indexHost" required for data operations');
  // Ensure no trailing slash
  while (H <> '') and (H[High(H)] = '/') do
    Delete(H, High(H), 1);
  Result := H;
end;

function TPineconeTool.ApiGet(const URL, ApiKey: string): string;
var
  HTTP: THTTPClient;
  Resp: IHTTPResponse;
begin
  HTTP := THTTPClient.Create;
  try
    Resp := HTTP.Get(URL, nil,
      [TNameValuePair.Create('Api-Key',      ApiKey),
       TNameValuePair.Create('X-Pinecone-API-Version', '2024-07')]);
    Result := Resp.ContentAsString(TEncoding.UTF8);
  finally
    HTTP.Free;
  end;
end;

function TPineconeTool.ApiPost(const URL, Body, ApiKey: string): string;
var
  HTTP:   THTTPClient;
  Stream: TStringStream;
  Resp:   IHTTPResponse;
begin
  HTTP   := THTTPClient.Create;
  Stream := TStringStream.Create(Body, TEncoding.UTF8);
  try
    Resp := HTTP.Post(URL, Stream, nil,
      [TNameValuePair.Create('Content-Type',  'application/json'),
       TNameValuePair.Create('Api-Key',       ApiKey),
       TNameValuePair.Create('X-Pinecone-API-Version', '2024-07')]);
    Result := Resp.ContentAsString(TEncoding.UTF8);
  finally
    Stream.Free;
    HTTP.Free;
  end;
end;

function TPineconeTool.DoListIndexes(const P: TPineconeParams): TJSONObject;
var
  Raw: string;
  J:   TJSONValue;
begin
  Raw := ApiGet(ControlURL + '/indexes', Trim(P.ApiKey));
  J   := TJSONObject.ParseJSONValue(Raw);
  try
    Result := TJSONObject.Create;
    if Assigned(J) then
    begin
      var Idxs := J.FindValue('indexes');
      if Assigned(Idxs) then
      begin
        Result.AddPair('indexes', Idxs.Clone as TJSONValue);
        if Idxs is TJSONArray then
          Result.AddPair('count', TJSONNumber.Create((Idxs as TJSONArray).Count));
      end
      else
        Result.AddPair('raw', TJSONString.Create(Raw));
    end
    else
      Result.AddPair('raw', TJSONString.Create(Raw));
    Result.AddPair('ok', TJSONTrue.Create);
  finally
    J.Free;
  end;
end;

function TPineconeTool.DoDescribeIndex(const P: TPineconeParams): TJSONObject;
var
  Raw: string;
  J:   TJSONValue;
begin
  if Trim(P.IndexName) = '' then
    raise Exception.Create('"indexName" required for describe_index');
  Raw := ApiGet(ControlURL + '/indexes/' + Trim(P.IndexName), Trim(P.ApiKey));
  J   := TJSONObject.ParseJSONValue(Raw);
  try
    Result := TJSONObject.Create;
    if Assigned(J) then
      Result.AddPair('index', J.Clone as TJSONValue)
    else
      Result.AddPair('raw', TJSONString.Create(Raw));
    Result.AddPair('ok', TJSONTrue.Create);
  finally
    J.Free;
  end;
end;

function TPineconeTool.DoQuery(const P: TPineconeParams): TJSONObject;
var
  Vec, Body, Raw, IV, IM: string;
  TopK: Integer;
  J:    TJSONValue;
begin
  Vec  := Trim(P.Vector);
  if Vec = '' then
    raise Exception.Create('"vector" required: JSON float array');
  TopK := P.TopK;
  if TopK <= 0 then TopK := 10;
  if P.IncludeValues   then IV := 'true' else IV := 'false';
  if P.IncludeMetadata then IM := 'true' else IM := 'false';

  Body := Format('{"vector":%s,"topK":%d,"includeValues":%s,"includeMetadata":%s',
                 [Vec, TopK, IV, IM]);
  if Trim(P.Namespace) <> '' then
    Body := Body + ',"namespace":"' + Trim(P.Namespace) + '"';
  if Trim(P.Filter) <> '' then
    Body := Body + ',"filter":' + Trim(P.Filter);
  Body := Body + '}';

  Raw := ApiPost(DataURL(P) + '/query', Body, Trim(P.ApiKey));
  J   := TJSONObject.ParseJSONValue(Raw);
  try
    Result := TJSONObject.Create;
    if Assigned(J) then
    begin
      var Matches := J.FindValue('matches');
      if Assigned(Matches) then
        Result.AddPair('matches', Matches.Clone as TJSONValue)
      else
        Result.AddPair('raw', TJSONString.Create(Raw));
    end
    else
      Result.AddPair('raw', TJSONString.Create(Raw));
    Result.AddPair('ok', TJSONTrue.Create);
  finally
    J.Free;
  end;
end;

function TPineconeTool.DoUpsert(const P: TPineconeParams): TJSONObject;
var
  Vecs, Body, Raw: string;
  J:               TJSONValue;
begin
  Vecs := Trim(P.Vectors);
  if Vecs = '' then
    raise Exception.Create('"vectors" required: JSON array of {id,values,metadata?}');
  Body := '{"vectors":' + Vecs;
  if Trim(P.Namespace) <> '' then
    Body := Body + ',"namespace":"' + Trim(P.Namespace) + '"';
  Body := Body + '}';

  Raw := ApiPost(DataURL(P) + '/vectors/upsert', Body, Trim(P.ApiKey));
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

function TPineconeTool.DoFetch(const P: TPineconeParams): TJSONObject;
var
  Ids:     TJSONArray;
  IdsStr:  TJSONValue;
  URL, NS, Raw: string;
  i:       Integer;
  J:       TJSONValue;
begin
  if Trim(P.Ids) = '' then
    raise Exception.Create('"ids" required: JSON string array');
  IdsStr := TJSONObject.ParseJSONValue(Trim(P.Ids));
  try
    if not (IdsStr is TJSONArray) then
      raise Exception.Create('"ids" must be a JSON array of strings');
    Ids := IdsStr as TJSONArray;
    URL := DataURL(P) + '/vectors/fetch?';
    for i := 0 to Ids.Count - 1 do
    begin
      if i > 0 then URL := URL + '&';
      URL := URL + 'ids=' + Ids.Items[i].Value;
    end;
    NS := Trim(P.Namespace);
    if NS <> '' then URL := URL + '&namespace=' + NS;
  finally
    IdsStr.Free;
  end;

  Raw := ApiGet(URL, Trim(P.ApiKey));
  J   := TJSONObject.ParseJSONValue(Raw);
  try
    Result := TJSONObject.Create;
    if Assigned(J) then
      Result.AddPair('vectors', J.Clone as TJSONValue)
    else
      Result.AddPair('raw', TJSONString.Create(Raw));
    Result.AddPair('ok', TJSONTrue.Create);
  finally
    J.Free;
  end;
end;

function TPineconeTool.DoDelete(const P: TPineconeParams): TJSONObject;
var
  Body, Raw, DA: string;
  J:             TJSONValue;
begin
  if P.DeleteAll then DA := 'true' else DA := 'false';
  if not P.DeleteAll and (Trim(P.Ids) = '') and (Trim(P.Filter) = '') then
    raise Exception.Create('"ids", "filter" or deleteAll=true required for delete');

  Body := '{';
  if P.DeleteAll then
    Body := Body + '"deleteAll":true'
  else
  begin
    if Trim(P.Ids) <> '' then
      Body := Body + '"ids":' + Trim(P.Ids);
    if Trim(P.Filter) <> '' then
    begin
      if Body <> '{' then Body := Body + ',';
      Body := Body + '"filter":' + Trim(P.Filter);
    end;
  end;
  if Trim(P.Namespace) <> '' then
  begin
    if Body <> '{' then Body := Body + ',';
    Body := Body + '"namespace":"' + Trim(P.Namespace) + '"';
  end;
  Body := Body + '}';

  Raw := ApiPost(DataURL(P) + '/vectors/delete', Body, Trim(P.ApiKey));
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

function TPineconeTool.DoListVectors(const P: TPineconeParams): TJSONObject;
var
  URL, NS, Raw: string;
  Lim:          Integer;
  J:            TJSONValue;
begin
  Lim := P.Limit;
  if Lim <= 0 then Lim := 100;
  URL := DataURL(P) + '/vectors/list?limit=' + IntToStr(Lim);
  NS  := Trim(P.Namespace);
  if NS <> '' then URL := URL + '&namespace=' + NS;
  if Trim(P.PaginationToken) <> '' then
    URL := URL + '&paginationToken=' + Trim(P.PaginationToken);

  Raw := ApiGet(URL, Trim(P.ApiKey));
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

function TPineconeTool.DoDescribeStats(const P: TPineconeParams): TJSONObject;
var
  Raw: string;
  J:   TJSONValue;
begin
  Raw := ApiGet(DataURL(P) + '/describe_index_stats', Trim(P.ApiKey));
  J   := TJSONObject.ParseJSONValue(Raw);
  try
    Result := TJSONObject.Create;
    if Assigned(J) then
      Result.AddPair('stats', J.Clone as TJSONValue)
    else
      Result.AddPair('raw', TJSONString.Create(Raw));
    Result.AddPair('ok', TJSONTrue.Create);
  finally
    J.Free;
  end;
end;

function TPineconeTool.ExecuteWithParams(const AParams: TPineconeParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op: string;
  R:  TJSONObject;
begin
  try
    Op := LowerCase(Trim(AParams.Operation));
    if Op = '' then raise Exception.Create('"operation" is required');
    if Trim(AParams.ApiKey) = '' then raise Exception.Create('"apiKey" is required');

    if      Op = 'list_indexes'    then R := DoListIndexes(AParams)
    else if Op = 'describe_index'  then R := DoDescribeIndex(AParams)
    else if Op = 'query'           then R := DoQuery(AParams)
    else if Op = 'upsert'          then R := DoUpsert(AParams)
    else if Op = 'fetch'           then R := DoFetch(AParams)
    else if Op = 'delete'          then R := DoDelete(AParams)
    else if Op = 'list_vectors'    then R := DoListVectors(AParams)
    else if Op = 'describe_stats'  then R := DoDescribeStats(AParams)
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

constructor TPineconeTool.Create;
begin
  inherited;
  FName        := 'mcp-pinecone';
  FDescription :=
    'Pinecone vector database via REST API. ' +
    'Control plane (requires indexName): list_indexes, describe_index. ' +
    'Data plane (requires indexHost = index URL like https://my-index.svc.pinecone.io): ' +
    'query (params: vector=float array, topK?, namespace?, filter?, includeMetadata?, includeValues?), ' +
    'upsert (params: vectors=JSON array of {id,values,metadata?}, namespace?), ' +
    'fetch (params: ids=JSON string array, namespace?), ' +
    'delete (params: ids? or filter? or deleteAll=true, namespace?), ' +
    'list_vectors (params: namespace?, limit?, paginationToken?), ' +
    'describe_stats. ' +
    'Required always: apiKey.';
end;

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-pinecone',
    function: IAiMCPTool
    begin
      Result := TPineconeTool.Create;
    end);
  WriteLn(ErrOutput, '[MCPService]   + mcp-pinecone');
end;

end.
