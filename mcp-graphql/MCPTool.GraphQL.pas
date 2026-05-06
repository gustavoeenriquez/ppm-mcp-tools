unit MCPTool.GraphQL;

(*
  MCPTool.GraphQL  *  mcp-graphql  (port 8654)

  Execute GraphQL queries and mutations against any GraphQL endpoint.

  All operations use HTTP POST with a JSON body to the target endpoint.

  Operations:
    query            - execute a GraphQL query
    mutation         - execute a GraphQL mutation
    introspect       - fetch the full GraphQL schema via introspection
    introspect_type  - get details for a specific named type
    list_queries     - list all available Query fields from the schema
    list_mutations   - list all available Mutation fields from the schema
    batch            - execute multiple operations in one request
    ping             - connectivity check via {__typename}

  Auth options (applied as request headers):
    BearerToken  -> Authorization: Bearer {token}
    Username     -> Authorization: Basic base64(Username:Password)
    ApiKey       -> {ApiKeyHeader}: {ApiKey}  (default header: X-Api-Key)
    ExtraHeaders -> arbitrary JSON object of additional headers

  Variables are accepted as a JSON string and merged into the POST body.
*)

interface

uses
  uMakerAi.MCPServer.Core,
  System.JSON,
  System.Net.URLClient;

type

  // -- Parameters -------------------------------------------------------------

  TGraphQLParams = class
  private
    FOperation:       string;
    FEndpoint:        string;
    FGraphQLQuery:    string;
    FVariables:       string;
    FTypeName:        string;
    FBatchOperations: string;
    FBearerToken:     string;
    FApiKey:          string;
    FApiKeyHeader:    string;
    FUsername:        string;
    FPassword:        string;
    FExtraHeaders:    string;
  public
    [AiMCPSchemaDescription('Operation: query, mutation, introspect, introspect_type, list_queries, list_mutations, batch, ping')]
    property Operation:       string read FOperation       write FOperation;

    [AiMCPSchemaDescription('GraphQL endpoint URL, e.g. https://api.example.com/graphql')]
    property Endpoint:        string read FEndpoint        write FEndpoint;

    [AiMCPOptional]
    [AiMCPSchemaDescription('GraphQL query or mutation string (required for query, mutation)')]
    property GraphQLQuery:    string read FGraphQLQuery    write FGraphQLQuery;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Variables as JSON string, e.g. {"id":"123"} (optional)')]
    property Variables:       string read FVariables       write FVariables;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Type name to inspect (required for introspect_type)')]
    property TypeName:        string read FTypeName        write FTypeName;

    [AiMCPOptional]
    [AiMCPSchemaDescription('JSON array string of batch operations: [{"query":"...","variables":{}}] (required for batch)')]
    property BatchOperations: string read FBatchOperations write FBatchOperations;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Bearer token for Authorization: Bearer {token} header')]
    property BearerToken:     string read FBearerToken     write FBearerToken;

    [AiMCPOptional]
    [AiMCPSchemaDescription('API key value (sent as ApiKeyHeader: {ApiKey})')]
    property ApiKey:          string read FApiKey          write FApiKey;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Header name for the API key (default: X-Api-Key)')]
    property ApiKeyHeader:    string read FApiKeyHeader    write FApiKeyHeader;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Username for Basic auth (used together with Password)')]
    property Username:        string read FUsername        write FUsername;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Password for Basic auth')]
    property Password:        string read FPassword        write FPassword;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Additional headers as JSON object, e.g. {"X-Custom":"value"}')]
    property ExtraHeaders:    string read FExtraHeaders    write FExtraHeaders;
  end;

  // -- Tool -------------------------------------------------------------------

  TGraphQLTool = class(TAiMCPToolBase<TGraphQLParams>)
  private
    function BuildAuthHeader(const P: TGraphQLParams): string;
    function BuildApiKeyHeader(const P: TGraphQLParams): TNameValuePair;
    function PostGraphQL(const Endpoint, Body: string;
      const AuthHeader: string;
      const ExtraHeadersJSON: string;
      const ApiKeyPair: TNameValuePair;
      const HasApiKey: Boolean): TJSONObject;
    function ParseGQLResponse(const Raw: string): TJSONObject;
    function RunIntrospection(const P: TGraphQLParams): TJSONObject;
    function ExtractTypeFields(const Schema: TJSONObject;
      const TypeName: string): TJSONArray;
    function DoQuery(const P: TGraphQLParams): TJSONObject;
    function DoMutation(const P: TGraphQLParams): TJSONObject;
    function DoIntrospect(const P: TGraphQLParams): TJSONObject;
    function DoIntrospectType(const P: TGraphQLParams): TJSONObject;
    function DoListQueries(const P: TGraphQLParams): TJSONObject;
    function DoListMutations(const P: TGraphQLParams): TJSONObject;
    function DoBatch(const P: TGraphQLParams): TJSONObject;
    function DoPing(const P: TGraphQLParams): TJSONObject;
  protected
    function ExecuteWithParams(const AParams: TGraphQLParams;
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
  System.NetEncoding;

const
  INTROSPECTION_QUERY =
    'query IntrospectionQuery { ' +
    '  __schema { ' +
    '    types { ' +
    '      name kind description ' +
    '      fields { name description type { name kind ofType { name kind } } } ' +
    '    } ' +
    '  } ' +
    '}';

{ TGraphQLTool }

constructor TGraphQLTool.Create;
begin
  inherited;
  FName        := 'mcp-graphql';
  FDescription :=
    'Execute GraphQL queries and mutations against any GraphQL endpoint. ' +
    'Operations: query (params: endpoint, graphQLQuery, variables?), ' +
    'mutation (params: endpoint, graphQLQuery, variables?), ' +
    'introspect (params: endpoint) — fetch full schema, ' +
    'introspect_type (params: endpoint, typeName) — inspect one type, ' +
    'list_queries (params: endpoint) — list Query fields, ' +
    'list_mutations (params: endpoint) — list Mutation fields, ' +
    'batch (params: endpoint, batchOperations JSON array), ' +
    'ping (params: endpoint) — connectivity check. ' +
    'Auth: bearerToken, apiKey+apiKeyHeader, username+password (Basic), extraHeaders JSON object.';
end;

// -- Auth helpers -------------------------------------------------------------

function TGraphQLTool.BuildAuthHeader(const P: TGraphQLParams): string;
var
  Raw: string;
begin
  Result := '';
  if Trim(P.BearerToken) <> '' then
    Result := 'Bearer ' + Trim(P.BearerToken)
  else if Trim(P.Username) <> '' then
  begin
    Raw    := Trim(P.Username) + ':' + P.Password;
    Result := 'Basic ' + TNetEncoding.Base64.Encode(Raw);
  end;
end;

function TGraphQLTool.BuildApiKeyHeader(const P: TGraphQLParams): TNameValuePair;
var
  HeaderName: string;
begin
  if Trim(P.ApiKeyHeader) <> '' then
    HeaderName := Trim(P.ApiKeyHeader)
  else
    HeaderName := 'X-Api-Key';
  Result := TNameValuePair.Create(HeaderName, Trim(P.ApiKey));
end;

// -- HTTP POST ----------------------------------------------------------------

function TGraphQLTool.PostGraphQL(const Endpoint, Body: string;
  const AuthHeader: string;
  const ExtraHeadersJSON: string;
  const ApiKeyPair: TNameValuePair;
  const HasApiKey: Boolean): TJSONObject;
var
  HTTP:    THTTPClient;
  Stream:  TStringStream;
  Resp:    IHTTPResponse;
  Raw:     string;
  JV:      TJSONValue;
  JO:      TJSONObject;
  Pair:    TJSONPair;
  Headers: TArray<TNameValuePair>;
  HIdx:    Integer;
begin
  // Build headers array dynamically
  SetLength(Headers, 2);
  Headers[0] := TNameValuePair.Create('Content-Type', 'application/json');
  Headers[1] := TNameValuePair.Create('Accept', 'application/json');
  HIdx := 2;

  if AuthHeader <> '' then
  begin
    SetLength(Headers, HIdx + 1);
    Headers[HIdx] := TNameValuePair.Create('Authorization', AuthHeader);
    Inc(HIdx);
  end;

  if HasApiKey then
  begin
    SetLength(Headers, HIdx + 1);
    Headers[HIdx] := TNameValuePair.Create(ApiKeyPair.Name, ApiKeyPair.Value);
    Inc(HIdx);
  end;

  if Trim(ExtraHeadersJSON) <> '' then
  begin
    JV := TJSONObject.ParseJSONValue(ExtraHeadersJSON);
    if Assigned(JV) then
    try
      if JV is TJSONObject then
      begin
        JO := TJSONObject(JV);
        for Pair in JO do
        begin
          SetLength(Headers, HIdx + 1);
          Headers[HIdx] := TNameValuePair.Create(Pair.JsonString.Value, Pair.JsonValue.Value);
          Inc(HIdx);
        end;
      end;
    finally
      JV.Free;
    end;
  end;

  HTTP := THTTPClient.Create;
  try
    HTTP.ConnectionTimeout := 30000;
    HTTP.ResponseTimeout   := 60000;
    HTTP.HandleRedirects   := True;

    Stream := TStringStream.Create(Body, TEncoding.UTF8);
    try
      Resp := HTTP.Post(Endpoint, Stream, nil, Headers);
    finally
      Stream.Free;
    end;

    Raw := Resp.ContentAsString(TEncoding.UTF8);
    Result := ParseGQLResponse(Raw);
    Result.AddPair('http_status', TJSONNumber.Create(Resp.StatusCode));
  finally
    HTTP.Free;
  end;
end;

function TGraphQLTool.ParseGQLResponse(const Raw: string): TJSONObject;
var
  JV: TJSONValue;
begin
  JV := TJSONObject.ParseJSONValue(Raw);
  if Assigned(JV) then
  begin
    if JV is TJSONObject then
      Result := TJSONObject(JV)
    else
    begin
      Result := TJSONObject.Create;
      Result.AddPair('data', JV);
    end;
  end
  else
  begin
    Result := TJSONObject.Create;
    Result.AddPair('raw', TJSONString.Create(Raw));
  end;
end;

// -- Introspection helper -----------------------------------------------------

function TGraphQLTool.RunIntrospection(const P: TGraphQLParams): TJSONObject;
var
  Body:       string;
  AuthHeader: string;
  ApiKeyPair: TNameValuePair;
  HasApiKey:  Boolean;
  BodyObj:    TJSONObject;
begin
  BodyObj := TJSONObject.Create;
  try
    BodyObj.AddPair('query', TJSONString.Create(INTROSPECTION_QUERY));
    Body := BodyObj.ToJSON;
  finally
    BodyObj.Free;
  end;

  AuthHeader := BuildAuthHeader(P);
  HasApiKey  := Trim(P.ApiKey) <> '';
  if HasApiKey then
    ApiKeyPair := BuildApiKeyHeader(P)
  else
    ApiKeyPair := TNameValuePair.Create('', '');

  Result := PostGraphQL(Trim(P.Endpoint), Body, AuthHeader,
    P.ExtraHeaders, ApiKeyPair, HasApiKey);
end;

function TGraphQLTool.ExtractTypeFields(const Schema: TJSONObject;
  const TypeName: string): TJSONArray;
var
  DataNode:    TJSONValue;
  SchemaNode:  TJSONValue;
  TypesNode:   TJSONValue;
  TypesArr:    TJSONArray;
  I:           Integer;
  TypeItem:    TJSONValue;
  TypeObj:     TJSONObject;
  NameVal:     TJSONValue;
  FieldsVal:   TJSONValue;
begin
  Result := TJSONArray.Create;

  DataNode := Schema.FindValue('data');
  if not Assigned(DataNode) then
    Exit;

  SchemaNode := TJSONObject(DataNode).FindValue('__schema');
  if not Assigned(SchemaNode) then
    Exit;

  TypesNode := TJSONObject(SchemaNode).FindValue('types');
  if not (TypesNode is TJSONArray) then
    Exit;

  TypesArr := TJSONArray(TypesNode);
  for I := 0 to TypesArr.Count - 1 do
  begin
    TypeItem := TypesArr.Items[I];
    if not (TypeItem is TJSONObject) then
      Continue;
    TypeObj := TJSONObject(TypeItem);

    NameVal := TypeObj.FindValue('name');
    if not Assigned(NameVal) then
      Continue;
    if NameVal.Value <> TypeName then
      Continue;

    FieldsVal := TypeObj.FindValue('fields');
    if FieldsVal is TJSONArray then
    begin
      Result.Free;
      Result := TJSONArray(FieldsVal.Clone);
      Exit;
    end;
  end;
end;

// -- Operations ---------------------------------------------------------------

function TGraphQLTool.DoQuery(const P: TGraphQLParams): TJSONObject;
var
  GQL:        string;
  Body:       string;
  BodyObj:    TJSONObject;
  VarsVal:    TJSONValue;
  AuthHeader: string;
  ApiKeyPair: TNameValuePair;
  HasApiKey:  Boolean;
begin
  GQL := Trim(P.GraphQLQuery);
  if GQL = '' then
    raise Exception.Create('"graphQLQuery" is required for query operation');

  BodyObj := TJSONObject.Create;
  try
    BodyObj.AddPair('query', TJSONString.Create(GQL));
    if Trim(P.Variables) <> '' then
    begin
      VarsVal := TJSONObject.ParseJSONValue(P.Variables);
      if Assigned(VarsVal) then
        BodyObj.AddPair('variables', VarsVal)
      else
        BodyObj.AddPair('variables', TJSONString.Create(P.Variables));
    end;
    Body := BodyObj.ToJSON;
  finally
    BodyObj.Free;
  end;

  AuthHeader := BuildAuthHeader(P);
  HasApiKey  := Trim(P.ApiKey) <> '';
  if HasApiKey then
    ApiKeyPair := BuildApiKeyHeader(P)
  else
    ApiKeyPair := TNameValuePair.Create('', '');

  Result := PostGraphQL(Trim(P.Endpoint), Body, AuthHeader,
    P.ExtraHeaders, ApiKeyPair, HasApiKey);
end;

function TGraphQLTool.DoMutation(const P: TGraphQLParams): TJSONObject;
var
  GQL:        string;
  Body:       string;
  BodyObj:    TJSONObject;
  VarsVal:    TJSONValue;
  AuthHeader: string;
  ApiKeyPair: TNameValuePair;
  HasApiKey:  Boolean;
begin
  GQL := Trim(P.GraphQLQuery);
  if GQL = '' then
    raise Exception.Create('"graphQLQuery" is required for mutation operation');

  BodyObj := TJSONObject.Create;
  try
    BodyObj.AddPair('query', TJSONString.Create(GQL));
    if Trim(P.Variables) <> '' then
    begin
      VarsVal := TJSONObject.ParseJSONValue(P.Variables);
      if Assigned(VarsVal) then
        BodyObj.AddPair('variables', VarsVal)
      else
        BodyObj.AddPair('variables', TJSONString.Create(P.Variables));
    end;
    Body := BodyObj.ToJSON;
  finally
    BodyObj.Free;
  end;

  AuthHeader := BuildAuthHeader(P);
  HasApiKey  := Trim(P.ApiKey) <> '';
  if HasApiKey then
    ApiKeyPair := BuildApiKeyHeader(P)
  else
    ApiKeyPair := TNameValuePair.Create('', '');

  Result := PostGraphQL(Trim(P.Endpoint), Body, AuthHeader,
    P.ExtraHeaders, ApiKeyPair, HasApiKey);
end;

function TGraphQLTool.DoIntrospect(const P: TGraphQLParams): TJSONObject;
begin
  Result := RunIntrospection(P);
end;

function TGraphQLTool.DoIntrospectType(const P: TGraphQLParams): TJSONObject;
var
  TName:      string;
  GQL:        string;
  Body:       string;
  BodyObj:    TJSONObject;
  AuthHeader: string;
  ApiKeyPair: TNameValuePair;
  HasApiKey:  Boolean;
begin
  TName := Trim(P.TypeName);
  if TName = '' then
    raise Exception.Create('"typeName" is required for introspect_type operation');

  GQL :=
    'query { __type(name: "' + TName + '") { ' +
    'name kind description ' +
    'fields { name description type { name kind ofType { name kind } } } ' +
    'inputFields { name description type { name kind ofType { name kind } } } ' +
    'enumValues { name description } ' +
    '} }';

  BodyObj := TJSONObject.Create;
  try
    BodyObj.AddPair('query', TJSONString.Create(GQL));
    Body := BodyObj.ToJSON;
  finally
    BodyObj.Free;
  end;

  AuthHeader := BuildAuthHeader(P);
  HasApiKey  := Trim(P.ApiKey) <> '';
  if HasApiKey then
    ApiKeyPair := BuildApiKeyHeader(P)
  else
    ApiKeyPair := TNameValuePair.Create('', '');

  Result := PostGraphQL(Trim(P.Endpoint), Body, AuthHeader,
    P.ExtraHeaders, ApiKeyPair, HasApiKey);
end;

function TGraphQLTool.DoListQueries(const P: TGraphQLParams): TJSONObject;
var
  Schema:    TJSONObject;
  Fields:    TJSONArray;
  Out:       TJSONObject;
  FieldList: TJSONArray;
  I:         Integer;
  FItem:     TJSONValue;
  FObj:      TJSONObject;
  FName:     TJSONValue;
  FDesc:     TJSONValue;
  Entry:     TJSONObject;
begin
  Schema := RunIntrospection(P);
  try
    Fields := ExtractTypeFields(Schema, 'Query');
    try
      Out       := TJSONObject.Create;
      FieldList := TJSONArray.Create;

      for I := 0 to Fields.Count - 1 do
      begin
        FItem := Fields.Items[I];
        if not (FItem is TJSONObject) then
          Continue;
        FObj  := TJSONObject(FItem);
        FName := FObj.FindValue('name');
        FDesc := FObj.FindValue('description');

        Entry := TJSONObject.Create;
        if Assigned(FName) then
          Entry.AddPair('name', TJSONString.Create(FName.Value))
        else
          Entry.AddPair('name', TJSONString.Create(''));
        if Assigned(FDesc) and (FDesc.Value <> '') then
          Entry.AddPair('description', TJSONString.Create(FDesc.Value));
        FieldList.AddElement(Entry);
      end;

      Out.AddPair('operation', TJSONString.Create('list_queries'));
      Out.AddPair('count', TJSONNumber.Create(FieldList.Count));
      Out.AddPair('queries', FieldList);
      Result := Out;
    finally
      Fields.Free;
    end;
  finally
    Schema.Free;
  end;
end;

function TGraphQLTool.DoListMutations(const P: TGraphQLParams): TJSONObject;
var
  Schema:    TJSONObject;
  Fields:    TJSONArray;
  Out:       TJSONObject;
  FieldList: TJSONArray;
  I:         Integer;
  FItem:     TJSONValue;
  FObj:      TJSONObject;
  FName:     TJSONValue;
  FDesc:     TJSONValue;
  Entry:     TJSONObject;
begin
  Schema := RunIntrospection(P);
  try
    Fields := ExtractTypeFields(Schema, 'Mutation');
    try
      Out       := TJSONObject.Create;
      FieldList := TJSONArray.Create;

      for I := 0 to Fields.Count - 1 do
      begin
        FItem := Fields.Items[I];
        if not (FItem is TJSONObject) then
          Continue;
        FObj  := TJSONObject(FItem);
        FName := FObj.FindValue('name');
        FDesc := FObj.FindValue('description');

        Entry := TJSONObject.Create;
        if Assigned(FName) then
          Entry.AddPair('name', TJSONString.Create(FName.Value))
        else
          Entry.AddPair('name', TJSONString.Create(''));
        if Assigned(FDesc) and (FDesc.Value <> '') then
          Entry.AddPair('description', TJSONString.Create(FDesc.Value));
        FieldList.AddElement(Entry);
      end;

      Out.AddPair('operation', TJSONString.Create('list_mutations'));
      Out.AddPair('count', TJSONNumber.Create(FieldList.Count));
      Out.AddPair('mutations', FieldList);
      Result := Out;
    finally
      Fields.Free;
    end;
  finally
    Schema.Free;
  end;
end;

function TGraphQLTool.DoBatch(const P: TGraphQLParams): TJSONObject;
var
  BatchStr:   string;
  Body:       string;
  AuthHeader: string;
  ApiKeyPair: TNameValuePair;
  HasApiKey:  Boolean;
  JV:         TJSONValue;
begin
  BatchStr := Trim(P.BatchOperations);
  if BatchStr = '' then
    raise Exception.Create('"batchOperations" is required for batch operation');

  JV := TJSONObject.ParseJSONValue(BatchStr);
  if not Assigned(JV) then
    raise Exception.Create('"batchOperations" is not valid JSON');
  JV.Free;

  Body := BatchStr;

  AuthHeader := BuildAuthHeader(P);
  HasApiKey  := Trim(P.ApiKey) <> '';
  if HasApiKey then
    ApiKeyPair := BuildApiKeyHeader(P)
  else
    ApiKeyPair := TNameValuePair.Create('', '');

  Result := PostGraphQL(Trim(P.Endpoint), Body, AuthHeader,
    P.ExtraHeaders, ApiKeyPair, HasApiKey);
end;

function TGraphQLTool.DoPing(const P: TGraphQLParams): TJSONObject;
var
  Body:       string;
  BodyObj:    TJSONObject;
  AuthHeader: string;
  ApiKeyPair: TNameValuePair;
  HasApiKey:  Boolean;
  Resp:       TJSONObject;
  DataNode:   TJSONValue;
  Out:        TJSONObject;
begin
  BodyObj := TJSONObject.Create;
  try
    BodyObj.AddPair('query', TJSONString.Create('{__typename}'));
    Body := BodyObj.ToJSON;
  finally
    BodyObj.Free;
  end;

  AuthHeader := BuildAuthHeader(P);
  HasApiKey  := Trim(P.ApiKey) <> '';
  if HasApiKey then
    ApiKeyPair := BuildApiKeyHeader(P)
  else
    ApiKeyPair := TNameValuePair.Create('', '');

  Resp := PostGraphQL(Trim(P.Endpoint), Body, AuthHeader,
    P.ExtraHeaders, ApiKeyPair, HasApiKey);
  try
    Out := TJSONObject.Create;
    Out.AddPair('operation', TJSONString.Create('ping'));
    Out.AddPair('endpoint', TJSONString.Create(Trim(P.Endpoint)));

    DataNode := Resp.FindValue('data');
    if Assigned(DataNode) then
    begin
      Out.AddPair('ok', TJSONTrue.Create);
      Out.AddPair('response', TJSONString.Create(DataNode.ToJSON));
    end
    else
    begin
      Out.AddPair('ok', TJSONFalse.Create);
      Out.AddPair('response', TJSONString.Create(Resp.ToJSON));
    end;
    Result := Out;
  finally
    Resp.Free;
  end;
end;

// -- Main execution ----------------------------------------------------------

function TGraphQLTool.ExecuteWithParams(const AParams: TGraphQLParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op: string;
  R:  TJSONObject;
begin
  try
    Op := LowerCase(Trim(AParams.Operation));
    if Op = '' then
      raise Exception.Create('"operation" is required');

    if Trim(AParams.Endpoint) = '' then
      raise Exception.Create('"endpoint" is required');

    if      Op = 'query'           then R := DoQuery(AParams)
    else if Op = 'mutation'        then R := DoMutation(AParams)
    else if Op = 'introspect'      then R := DoIntrospect(AParams)
    else if Op = 'introspect_type' then R := DoIntrospectType(AParams)
    else if Op = 'list_queries'    then R := DoListQueries(AParams)
    else if Op = 'list_mutations'  then R := DoListMutations(AParams)
    else if Op = 'batch'           then R := DoBatch(AParams)
    else if Op = 'ping'            then R := DoPing(AParams)
    else raise Exception.CreateFmt('Unknown operation "%s". ' +
      'Valid: query, mutation, introspect, introspect_type, ' +
      'list_queries, list_mutations, batch, ping', [Op]);

    Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
    R.Free;
  except
    on E: Exception do
      Result := TAiMCPResponseBuilder.New
        .AddText('{"ok":false,"error":"' +
          E.Message.Replace('\', '\\').Replace('"', '\"')
                   .Replace(#10, '\n').Replace(#13, '') + '"}')
        .Build;
  end;
end;

// -- Registration ------------------------------------------------------------

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-graphql',
    function: IAiMCPTool
    begin
      Result := TGraphQLTool.Create;
    end);
  WriteLn(ErrOutput, '[MCPService]   + mcp-graphql');
end;

end.
