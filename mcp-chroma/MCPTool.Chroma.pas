unit MCPTool.Chroma;

{
  MCPTool.Chroma  ·  mcp-chroma  (port 8617)
  ChromaDB vector database via REST API v1 (ChromaDB 0.4.x+).

  Operations:
    list_collections   - list all collections
    create_collection  - create a new collection
    get_collection     - get collection info (returns id, name, metadata)
    delete_collection  - delete a collection by name
    count              - count documents in a collection
    add                - add documents with optional embeddings and metadata
    upsert             - add or update documents
    query              - vector similarity search
    get_documents      - retrieve documents by IDs or filter
    delete_documents   - delete documents by IDs or filter
}

interface

uses
  uMakerAi.MCPServer.Core,
  System.JSON;

type
  TChromaParams = class
  private
    FOperation:      string;
    FHost:           string;
    FPort:           Integer;
    FToken:          string;
    FCollection:     string;
    FIds:            string;
    FDocuments:      string;
    FEmbeddings:     string;
    FMetadatas:      string;
    FWhere:          string;
    FQueryEmbedding: string;
    FNResults:       Integer;
    FInclude:        string;
    FLimit:          Integer;
    FOffset:         Integer;
    FMetadata:       string;
    FGetOrCreate:    Boolean;
  public
    constructor Create;

    [AiMCPSchemaDescription('Operation: list_collections, create_collection, get_collection, delete_collection, count, add, upsert, query, get_documents, delete_documents')]
    property Operation:      string  read FOperation      write FOperation;

    [AiMCPSchemaDescription('ChromaDB host (default: localhost)')]
    property Host:           string  read FHost           write FHost;

    [AiMCPOptional]
    [AiMCPSchemaDescription('ChromaDB port (default: 8000)')]
    property Port:           Integer read FPort           write FPort;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Bearer token for authentication (optional)')]
    property Token:          string  read FToken          write FToken;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Collection name')]
    property Collection:     string  read FCollection     write FCollection;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Document IDs as JSON string array: ["id1","id2"]')]
    property Ids:            string  read FIds            write FIds;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Documents (text content) as JSON string array: ["text1","text2"]')]
    property Documents:      string  read FDocuments      write FDocuments;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Embeddings as JSON array of float arrays: [[0.1,0.2,...],[...]]')]
    property Embeddings:     string  read FEmbeddings     write FEmbeddings;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Metadata as JSON array of objects: [{"source":"file1"},...]')]
    property Metadatas:      string  read FMetadatas      write FMetadatas;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Where filter as JSON: {"source":{"$eq":"file1"}}')]
    property Where:          string  read FWhere          write FWhere;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Query embedding as JSON float array: [0.1, 0.2, ...] (for query)')]
    property QueryEmbedding: string  read FQueryEmbedding write FQueryEmbedding;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Number of results for query (default: 10)')]
    property NResults:       Integer read FNResults       write FNResults;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Fields to include (comma-sep): documents,embeddings,metadatas,distances (default: documents,metadatas,distances)')]
    property Include:        string  read FInclude        write FInclude;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Max documents to return for get_documents (default: 100)')]
    property Limit:          Integer read FLimit          write FLimit;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Offset for get_documents pagination')]
    property Offset:         Integer read FOffset         write FOffset;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Collection metadata as JSON object (for create_collection)')]
    property Metadata:       string  read FMetadata       write FMetadata;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Return existing collection if name already exists (default: true)')]
    property GetOrCreate:    Boolean read FGetOrCreate    write FGetOrCreate;
  end;

  TChromaTool = class(TAiMCPToolBase<TChromaParams>)
  private
    function BaseURL(const P: TChromaParams): string;
    function ApiGet(const URL, Token: string): string;
    function ApiPost(const URL, Body, Token: string): string;
    function ApiDelete(const URL, Token: string): string;
    function ResolveCollectionId(const P: TChromaParams): string;
    function BuildIncludeArray(const Include: string): string;
    function DoListCollections(const P: TChromaParams): TJSONObject;
    function DoCreateCollection(const P: TChromaParams): TJSONObject;
    function DoGetCollection(const P: TChromaParams): TJSONObject;
    function DoDeleteCollection(const P: TChromaParams): TJSONObject;
    function DoCount(const P: TChromaParams): TJSONObject;
    function DoAdd(const P: TChromaParams): TJSONObject;
    function DoUpsert(const P: TChromaParams): TJSONObject;
    function DoQuery(const P: TChromaParams): TJSONObject;
    function DoGetDocuments(const P: TChromaParams): TJSONObject;
    function DoDeleteDocuments(const P: TChromaParams): TJSONObject;
  protected
    function ExecuteWithParams(const AParams: TChromaParams;
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

{ TChromaParams }

constructor TChromaParams.Create;
begin
  inherited;
  FHost        := 'localhost';
  FPort        := 8000;
  FNResults    := 10;
  FLimit       := 100;
  FGetOrCreate := True;
  FInclude     := 'documents,metadatas,distances';
end;

{ TChromaTool }

function TChromaTool.BaseURL(const P: TChromaParams): string;
var
  Port: Integer;
begin
  Port := P.Port;
  if Port <= 0 then Port := 8000;
  Result := Format('http://%s:%d/api/v1', [Trim(P.Host), Port]);
end;

function TChromaTool.ApiGet(const URL, Token: string): string;
var
  HTTP: THTTPClient;
  Resp: IHTTPResponse;
begin
  HTTP := THTTPClient.Create;
  try
    if Token <> '' then
      Resp := HTTP.Get(URL, nil,
        [TNameValuePair.Create('Authorization', 'Bearer ' + Token)])
    else
      Resp := HTTP.Get(URL);
    Result := Resp.ContentAsString(TEncoding.UTF8);
  finally
    HTTP.Free;
  end;
end;

function TChromaTool.ApiPost(const URL, Body, Token: string): string;
var
  HTTP:   THTTPClient;
  Stream: TStringStream;
  Resp:   IHTTPResponse;
begin
  HTTP   := THTTPClient.Create;
  Stream := TStringStream.Create(Body, TEncoding.UTF8);
  try
    if Token <> '' then
      Resp := HTTP.Post(URL, Stream, nil,
        [TNameValuePair.Create('Content-Type', 'application/json'),
         TNameValuePair.Create('Authorization', 'Bearer ' + Token)])
    else
      Resp := HTTP.Post(URL, Stream, nil,
        [TNameValuePair.Create('Content-Type', 'application/json')]);
    Result := Resp.ContentAsString(TEncoding.UTF8);
  finally
    Stream.Free;
    HTTP.Free;
  end;
end;

function TChromaTool.ApiDelete(const URL, Token: string): string;
var
  HTTP: THTTPClient;
  Resp: IHTTPResponse;
begin
  HTTP := THTTPClient.Create;
  try
    if Token <> '' then
      Resp := HTTP.Delete(URL, nil,
        [TNameValuePair.Create('Authorization', 'Bearer ' + Token)])
    else
      Resp := HTTP.Delete(URL);
    Result := Resp.ContentAsString(TEncoding.UTF8);
  finally
    HTTP.Free;
  end;
end;

function TChromaTool.ResolveCollectionId(const P: TChromaParams): string;
var
  Raw: string;
  J:   TJSONValue;
  Id:  TJSONValue;
begin
  if Trim(P.Collection) = '' then
    raise Exception.Create('"collection" required');
  Raw := ApiGet(BaseURL(P) + '/collections/' + Trim(P.Collection), Trim(P.Token));
  J   := TJSONObject.ParseJSONValue(Raw);
  try
    if not Assigned(J) then
      raise Exception.Create('Could not resolve collection: ' + Raw);
    Id := J.FindValue('id');
    if not Assigned(Id) then
      raise Exception.CreateFmt('Collection "%s" not found', [P.Collection]);
    Result := Id.Value;
  finally
    J.Free;
  end;
end;

function TChromaTool.BuildIncludeArray(const Include: string): string;
var
  Parts: TArray<string>;
  i: Integer;
begin
  if Trim(Include) = '' then
    Exit('["documents","metadatas","distances"]');
  Parts  := Trim(Include).Split([',']);
  Result := '[';
  for i := 0 to High(Parts) do
  begin
    if i > 0 then Result := Result + ',';
    Result := Result + '"' + Trim(Parts[i]) + '"';
  end;
  Result := Result + ']';
end;

function TChromaTool.DoListCollections(const P: TChromaParams): TJSONObject;
var
  Raw: string;
  J:   TJSONValue;
begin
  Raw := ApiGet(BaseURL(P) + '/collections', Trim(P.Token));
  J   := TJSONObject.ParseJSONValue(Raw);
  try
    Result := TJSONObject.Create;
    if Assigned(J) and (J is TJSONArray) then
    begin
      Result.AddPair('collections', J.Clone as TJSONValue);
      Result.AddPair('count', TJSONNumber.Create((J as TJSONArray).Count));
    end
    else
      Result.AddPair('raw', TJSONString.Create(Raw));
    Result.AddPair('ok', TJSONTrue.Create);
  finally
    J.Free;
  end;
end;

function TChromaTool.DoCreateCollection(const P: TChromaParams): TJSONObject;
var
  Body, Raw, Meta: string;
  GOC: string;
begin
  if Trim(P.Collection) = '' then
    raise Exception.Create('"collection" required for create_collection');
  if P.GetOrCreate then GOC := 'true' else GOC := 'false';
  Meta := Trim(P.Metadata);
  if Meta = '' then Meta := '{}';
  Body := Format('{"name":"%s","metadata":%s,"get_or_create":%s}',
                 [Trim(P.Collection), Meta, GOC]);
  Raw  := ApiPost(BaseURL(P) + '/collections', Body, Trim(P.Token));
  Result := TJSONObject.Create;
  var J := TJSONObject.ParseJSONValue(Raw);
  if Assigned(J) then
  begin
    Result.AddPair('collection', J.Clone as TJSONValue);
    J.Free;
  end
  else
    Result.AddPair('raw', TJSONString.Create(Raw));
  Result.AddPair('ok', TJSONTrue.Create);
end;

function TChromaTool.DoGetCollection(const P: TChromaParams): TJSONObject;
var
  Raw: string;
  J:   TJSONValue;
begin
  if Trim(P.Collection) = '' then
    raise Exception.Create('"collection" required for get_collection');
  Raw := ApiGet(BaseURL(P) + '/collections/' + Trim(P.Collection), Trim(P.Token));
  J   := TJSONObject.ParseJSONValue(Raw);
  try
    Result := TJSONObject.Create;
    if Assigned(J) then
      Result.AddPair('collection', J.Clone as TJSONValue)
    else
      Result.AddPair('raw', TJSONString.Create(Raw));
    Result.AddPair('ok', TJSONTrue.Create);
  finally
    J.Free;
  end;
end;

function TChromaTool.DoDeleteCollection(const P: TChromaParams): TJSONObject;
var
  Raw: string;
begin
  if Trim(P.Collection) = '' then
    raise Exception.Create('"collection" required for delete_collection');
  Raw := ApiDelete(BaseURL(P) + '/collections/' + Trim(P.Collection), Trim(P.Token));
  Result := TJSONObject.Create;
  Result.AddPair('collection', P.Collection);
  Result.AddPair('response',   Raw);
  Result.AddPair('ok',         TJSONTrue.Create);
end;

function TChromaTool.DoCount(const P: TChromaParams): TJSONObject;
var
  UUID, Raw: string;
  J:         TJSONValue;
begin
  UUID := ResolveCollectionId(P);
  Raw  := ApiGet(BaseURL(P) + '/collections/' + UUID + '/count', Trim(P.Token));
  J    := TJSONObject.ParseJSONValue(Raw);
  try
    Result := TJSONObject.Create;
    if Assigned(J) then
      Result.AddPair('count', J.Clone as TJSONValue)
    else
      Result.AddPair('count', TJSONNumber.Create(0));
    Result.AddPair('ok', TJSONTrue.Create);
  finally
    J.Free;
  end;
end;

function TChromaTool.DoAdd(const P: TChromaParams): TJSONObject;
var
  UUID, Body, Raw: string;
  Ids, Docs, Embs, Metas: string;
begin
  UUID  := ResolveCollectionId(P);
  Ids   := Trim(P.Ids);
  Docs  := Trim(P.Documents);
  Embs  := Trim(P.Embeddings);
  Metas := Trim(P.Metadatas);

  if Ids = '' then
    raise Exception.Create('"ids" required for add');
  if (Docs = '') and (Embs = '') then
    raise Exception.Create('"documents" or "embeddings" required for add');

  Body := '{"ids":' + Ids;
  if Docs  <> '' then Body := Body + ',"documents":' + Docs;
  if Embs  <> '' then Body := Body + ',"embeddings":' + Embs;
  if Metas <> '' then Body := Body + ',"metadatas":' + Metas;
  Body := Body + '}';

  Raw := ApiPost(BaseURL(P) + '/collections/' + UUID + '/add', Body, Trim(P.Token));
  Result := TJSONObject.Create;
  Result.AddPair('response', Raw);
  Result.AddPair('ok',       TJSONTrue.Create);
end;

function TChromaTool.DoUpsert(const P: TChromaParams): TJSONObject;
var
  UUID, Body, Raw: string;
  Ids, Docs, Embs, Metas: string;
begin
  UUID  := ResolveCollectionId(P);
  Ids   := Trim(P.Ids);
  Docs  := Trim(P.Documents);
  Embs  := Trim(P.Embeddings);
  Metas := Trim(P.Metadatas);

  if Ids = '' then
    raise Exception.Create('"ids" required for upsert');

  Body := '{"ids":' + Ids;
  if Docs  <> '' then Body := Body + ',"documents":' + Docs;
  if Embs  <> '' then Body := Body + ',"embeddings":' + Embs;
  if Metas <> '' then Body := Body + ',"metadatas":' + Metas;
  Body := Body + '}';

  Raw := ApiPost(BaseURL(P) + '/collections/' + UUID + '/upsert', Body, Trim(P.Token));
  Result := TJSONObject.Create;
  Result.AddPair('response', Raw);
  Result.AddPair('ok',       TJSONTrue.Create);
end;

function TChromaTool.DoQuery(const P: TChromaParams): TJSONObject;
var
  UUID, Body, Raw, QE, Inc: string;
  N: Integer;
  J: TJSONValue;
begin
  UUID := ResolveCollectionId(P);
  QE   := Trim(P.QueryEmbedding);
  if QE = '' then
    raise Exception.Create('"queryEmbedding" required: JSON float array');

  N   := P.NResults;
  if N <= 0 then N := 10;
  Inc := BuildIncludeArray(P.Include);

  Body := Format('{"query_embeddings":[%s],"n_results":%d,"include":%s', [QE, N, Inc]);
  if Trim(P.Where) <> '' then
    Body := Body + ',"where":' + Trim(P.Where);
  Body := Body + '}';

  Raw := ApiPost(BaseURL(P) + '/collections/' + UUID + '/query', Body, Trim(P.Token));
  J   := TJSONObject.ParseJSONValue(Raw);
  try
    Result := TJSONObject.Create;
    if Assigned(J) then
      Result.AddPair('results', J.Clone as TJSONValue)
    else
      Result.AddPair('raw', TJSONString.Create(Raw));
    Result.AddPair('ok', TJSONTrue.Create);
  finally
    J.Free;
  end;
end;

function TChromaTool.DoGetDocuments(const P: TChromaParams): TJSONObject;
var
  UUID, Body, Raw, Inc: string;
  J: TJSONValue;
begin
  UUID := ResolveCollectionId(P);
  Inc  := BuildIncludeArray(P.Include);
  Body := '{"include":' + Inc;
  if Trim(P.Ids)   <> '' then Body := Body + ',"ids":'   + Trim(P.Ids);
  if Trim(P.Where) <> '' then Body := Body + ',"where":' + Trim(P.Where);
  if P.Limit  > 0  then Body := Body + Format(',"limit":%d',  [P.Limit]);
  if P.Offset > 0  then Body := Body + Format(',"offset":%d', [P.Offset]);
  Body := Body + '}';

  Raw := ApiPost(BaseURL(P) + '/collections/' + UUID + '/get', Body, Trim(P.Token));
  J   := TJSONObject.ParseJSONValue(Raw);
  try
    Result := TJSONObject.Create;
    if Assigned(J) then
      Result.AddPair('results', J.Clone as TJSONValue)
    else
      Result.AddPair('raw', TJSONString.Create(Raw));
    Result.AddPair('ok', TJSONTrue.Create);
  finally
    J.Free;
  end;
end;

function TChromaTool.DoDeleteDocuments(const P: TChromaParams): TJSONObject;
var
  UUID, Body, Raw: string;
begin
  UUID := ResolveCollectionId(P);
  if (Trim(P.Ids) = '') and (Trim(P.Where) = '') then
    raise Exception.Create('"ids" or "where" required for delete_documents');
  Body := '{';
  if Trim(P.Ids)   <> '' then Body := Body + '"ids":'   + Trim(P.Ids);
  if Trim(P.Where) <> '' then
  begin
    if Body <> '{' then Body := Body + ',';
    Body := Body + '"where":' + Trim(P.Where);
  end;
  Body := Body + '}';

  Raw := ApiPost(BaseURL(P) + '/collections/' + UUID + '/delete', Body, Trim(P.Token));
  Result := TJSONObject.Create;
  Result.AddPair('response', Raw);
  Result.AddPair('ok',       TJSONTrue.Create);
end;

function TChromaTool.ExecuteWithParams(const AParams: TChromaParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op: string;
  R:  TJSONObject;
begin
  try
    Op := LowerCase(Trim(AParams.Operation));
    if Op = '' then raise Exception.Create('"operation" is required');

    if      Op = 'list_collections'  then R := DoListCollections(AParams)
    else if Op = 'create_collection' then R := DoCreateCollection(AParams)
    else if Op = 'get_collection'    then R := DoGetCollection(AParams)
    else if Op = 'delete_collection' then R := DoDeleteCollection(AParams)
    else if Op = 'count'             then R := DoCount(AParams)
    else if Op = 'add'               then R := DoAdd(AParams)
    else if Op = 'upsert'            then R := DoUpsert(AParams)
    else if Op = 'query'             then R := DoQuery(AParams)
    else if Op = 'get_documents'     then R := DoGetDocuments(AParams)
    else if Op = 'delete_documents'  then R := DoDeleteDocuments(AParams)
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

constructor TChromaTool.Create;
begin
  inherited;
  FName        := 'mcp-chroma';
  FDescription :=
    'ChromaDB vector database via REST API v1 (ChromaDB 0.4.x+). ' +
    'Operations: list_collections, create_collection (params: collection, metadata?, getOrCreate?), ' +
    'get_collection (params: collection), delete_collection (params: collection), ' +
    'count (params: collection), ' +
    'add (params: collection, ids, documents? or embeddings?, metadatas?), ' +
    'upsert (params: collection, ids, documents?, embeddings?, metadatas?), ' +
    'query (params: collection, queryEmbedding, nResults?, where?, include?), ' +
    'get_documents (params: collection, ids?, where?, limit?, offset?, include?), ' +
    'delete_documents (params: collection, ids? or where=JSON filter). ' +
    'Required: host. Optional: port (default 8000), token.';
end;

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-chroma',
    function: IAiMCPTool
    begin
      Result := TChromaTool.Create;
    end);
  WriteLn(ErrOutput, '[MCPService]   + mcp-chroma');
end;

end.
