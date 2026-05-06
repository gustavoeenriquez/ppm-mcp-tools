unit MCPTool.DynamoDB;

(*
  MCPTool.DynamoDB  *  mcp-dynamodb  (port 8646)

  Wraps the Amazon DynamoDB REST API (single-endpoint, X-Amz-Target dispatch).

  Supports:
    - DynamoDB Local  (http://localhost:8000) — no auth required
    - AWS DynamoDB    (https://dynamodb.{region}.amazonaws.com/) — pass a
      pre-computed AWS Signature V4 Authorization header via AuthHeader param

  All calls: POST / with Content-Type: application/x-amz-json-1.0
             and X-Amz-Target: DynamoDB_20120810.{Action}

  Operations:
    list_tables    - ListTables   — list all table names
    describe_table - DescribeTable — describe a table schema
    get_item       - GetItem      — retrieve a single item by key
    put_item       - PutItem      — create or replace an item
    delete_item    - DeleteItem   — delete an item by key
    query          - Query        — key-condition query on a table/index
    scan           - Scan         — full table scan with optional filter
    create_table   - CreateTable  — create a new table (pass full body via Body)
    delete_table   - DeleteTable  — delete a table
*)

interface

uses
  uMakerAi.MCPServer.Core,
  System.JSON;

type

  TDynamoDBParams = class
  private
    FOperation:                string;
    FEndpointUrl:              string;
    FTableName:                string;
    FKey:                      string;
    FItem:                     string;
    FBody:                     string;
    FKeyConditionExpression:   string;
    FExpressionAttributeValues: string;
    FFilterExpression:         string;
    FLimitVal:                 Integer;
    FAuthHeader:               string;
  public
    constructor Create;

    [AiMCPSchemaDescription('Operation: list_tables, describe_table, get_item, put_item, delete_item, query, scan, create_table, delete_table')]
    property Operation:                string  read FOperation                write FOperation;

    [AiMCPSchemaDescription('DynamoDB endpoint URL: http://localhost:8000 for DynamoDB Local, or https://dynamodb.us-east-1.amazonaws.com for AWS')]
    property EndpointUrl:              string  read FEndpointUrl              write FEndpointUrl;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Table name (required for most operations)')]
    property TableName:                string  read FTableName                write FTableName;

    [AiMCPOptional]
    [AiMCPSchemaDescription('DynamoDB key as JSON, e.g. {"id":{"S":"123"}} (for get_item, delete_item)')]
    property Key:                      string  read FKey                      write FKey;

    [AiMCPOptional]
    [AiMCPSchemaDescription('DynamoDB item as JSON, e.g. {"id":{"S":"123"},"name":{"S":"John"}} (for put_item)')]
    property Item:                     string  read FItem                     write FItem;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Raw JSON body override — if provided, sent directly as request body (use for create_table or custom queries)')]
    property Body:                     string  read FBody                     write FBody;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Key condition expression for query, e.g. "id = :id"')]
    property KeyConditionExpression:   string  read FKeyConditionExpression   write FKeyConditionExpression;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Expression attribute values as JSON, e.g. {":id":{"S":"123"}} (for query/scan)')]
    property ExpressionAttributeValues: string read FExpressionAttributeValues write FExpressionAttributeValues;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Filter expression for scan/query, e.g. "age > :minAge"')]
    property FilterExpression:         string  read FFilterExpression         write FFilterExpression;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Maximum number of items to return (default: 100)')]
    property LimitVal:                 Integer read FLimitVal                 write FLimitVal;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Full AWS Signature V4 Authorization header value (for AWS DynamoDB; leave empty for DynamoDB Local)')]
    property AuthHeader:               string  read FAuthHeader               write FAuthHeader;
  end;

  TDynamoDBTool = class(TAiMCPToolBase<TDynamoDBParams>)
  private
    function CallAction(const EndpointUrl, Action, ReqBody, AuthHeader: string): TJSONObject;
    function DoListTables(const P: TDynamoDBParams): TJSONObject;
    function DoDescribeTable(const P: TDynamoDBParams): TJSONObject;
    function DoGetItem(const P: TDynamoDBParams): TJSONObject;
    function DoPutItem(const P: TDynamoDBParams): TJSONObject;
    function DoDeleteItem(const P: TDynamoDBParams): TJSONObject;
    function DoQuery(const P: TDynamoDBParams): TJSONObject;
    function DoScan(const P: TDynamoDBParams): TJSONObject;
    function DoCreateTable(const P: TDynamoDBParams): TJSONObject;
    function DoDeleteTable(const P: TDynamoDBParams): TJSONObject;
  protected
    function ExecuteWithParams(const AParams: TDynamoDBParams;
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
  System.Net.URLClient,
  System.NetEncoding;

{ TDynamoDBParams }

constructor TDynamoDBParams.Create;
begin
  inherited;
  FLimitVal := 100;
end;

{ TDynamoDBTool }

function TDynamoDBTool.CallAction(const EndpointUrl, Action, ReqBody, AuthHeader: string): TJSONObject;
var
  HTTP:       THTTPClient;
  Stream:     TStringStream;
  Resp:       IHTTPResponse;
  RawResp:    string;
  Parsed:     TJSONValue;
  Endpoint:   string;
begin
  Endpoint := Trim(EndpointUrl);
  if (Length(Endpoint) > 0) and (Endpoint[Length(Endpoint)] = '/') then
    Endpoint := Copy(Endpoint, 1, Length(Endpoint) - 1);

  HTTP   := THTTPClient.Create;
  Stream := TStringStream.Create(ReqBody, TEncoding.UTF8);
  try
    HTTP.ConnectionTimeout := 15000;
    HTTP.ResponseTimeout   := 30000;

    if Trim(AuthHeader) <> '' then
      Resp := HTTP.Post(Endpoint + '/', Stream, nil,
        [TNameValuePair.Create('Content-Type',  'application/x-amz-json-1.0'),
         TNameValuePair.Create('X-Amz-Target',  'DynamoDB_20120810.' + Action),
         TNameValuePair.Create('Authorization', AuthHeader)])
    else
      Resp := HTTP.Post(Endpoint + '/', Stream, nil,
        [TNameValuePair.Create('Content-Type', 'application/x-amz-json-1.0'),
         TNameValuePair.Create('X-Amz-Target', 'DynamoDB_20120810.' + Action)]);
    RawResp := Resp.ContentAsString(TEncoding.UTF8);

    if (Resp.StatusCode < 200) or (Resp.StatusCode >= 300) then
      raise Exception.CreateFmt('HTTP %d: %s', [Resp.StatusCode,
        Copy(RawResp, 1, 400)]);

    Parsed := TJSONObject.ParseJSONValue(RawResp);
    if Assigned(Parsed) and (Parsed is TJSONObject) then
      Result := Parsed as TJSONObject
    else
    begin
      if Assigned(Parsed) then Parsed.Free;
      Result := TJSONObject.Create;
      Result.AddPair('raw', TJSONString.Create(RawResp));
    end;
  finally
    Stream.Free;
    HTTP.Free;
  end;
end;

function TDynamoDBTool.DoListTables(const P: TDynamoDBParams): TJSONObject;
var
  Lim:  Integer;
  Body: string;
begin
  Lim := P.LimitVal;
  if Lim <= 0 then Lim := 100;
  Body   := Format('{"Limit":%d}', [Lim]);
  Result := CallAction(P.EndpointUrl, 'ListTables', Body, P.AuthHeader);
end;

function TDynamoDBTool.DoDescribeTable(const P: TDynamoDBParams): TJSONObject;
var
  Body: string;
begin
  if Trim(P.TableName) = '' then
    raise Exception.Create('"tableName" is required for describe_table');
  Body   := '{"TableName":"' + P.TableName + '"}';
  Result := CallAction(P.EndpointUrl, 'DescribeTable', Body, P.AuthHeader);
end;

function TDynamoDBTool.DoGetItem(const P: TDynamoDBParams): TJSONObject;
var
  KeyStr: string;
  Body:   string;
begin
  if Trim(P.TableName) = '' then
    raise Exception.Create('"tableName" is required for get_item');
  KeyStr := Trim(P.Key);
  if KeyStr = '' then
    raise Exception.Create('"key" is required for get_item');
  Body   := '{"TableName":"' + P.TableName + '","Key":' + KeyStr + '}';
  Result := CallAction(P.EndpointUrl, 'GetItem', Body, P.AuthHeader);
end;

function TDynamoDBTool.DoPutItem(const P: TDynamoDBParams): TJSONObject;
var
  ItemStr: string;
  Body:    string;
begin
  if Trim(P.TableName) = '' then
    raise Exception.Create('"tableName" is required for put_item');
  ItemStr := Trim(P.Item);
  if ItemStr = '' then
    raise Exception.Create('"item" is required for put_item');
  Body   := '{"TableName":"' + P.TableName + '","Item":' + ItemStr + '}';
  Result := CallAction(P.EndpointUrl, 'PutItem', Body, P.AuthHeader);
end;

function TDynamoDBTool.DoDeleteItem(const P: TDynamoDBParams): TJSONObject;
var
  KeyStr: string;
  Body:   string;
begin
  if Trim(P.TableName) = '' then
    raise Exception.Create('"tableName" is required for delete_item');
  KeyStr := Trim(P.Key);
  if KeyStr = '' then
    raise Exception.Create('"key" is required for delete_item');
  Body   := '{"TableName":"' + P.TableName + '","Key":' + KeyStr + '}';
  Result := CallAction(P.EndpointUrl, 'DeleteItem', Body, P.AuthHeader);
end;

function TDynamoDBTool.DoQuery(const P: TDynamoDBParams): TJSONObject;
var
  Expr:   string;
  Vals:   string;
  Filt:   string;
  Lim:    Integer;
  Body:   string;
begin
  if Trim(P.TableName) = '' then
    raise Exception.Create('"tableName" is required for query');
  Expr := Trim(P.KeyConditionExpression);
  if Expr = '' then
    raise Exception.Create('"keyConditionExpression" is required for query');
  Vals := Trim(P.ExpressionAttributeValues);
  if Vals = '' then
    raise Exception.Create('"expressionAttributeValues" is required for query');

  Lim := P.LimitVal;
  if Lim <= 0 then Lim := 100;

  Body := '{"TableName":"' + P.TableName + '"' +
          ',"KeyConditionExpression":"' + Expr + '"' +
          ',"ExpressionAttributeValues":' + Vals +
          ',"Limit":' + IntToStr(Lim);

  Filt := Trim(P.FilterExpression);
  if Filt <> '' then
    Body := Body + ',"FilterExpression":"' + Filt + '"';

  Body   := Body + '}';
  Result := CallAction(P.EndpointUrl, 'Query', Body, P.AuthHeader);
end;

function TDynamoDBTool.DoScan(const P: TDynamoDBParams): TJSONObject;
var
  Filt: string;
  Lim:  Integer;
  Body: string;
begin
  if Trim(P.TableName) = '' then
    raise Exception.Create('"tableName" is required for scan');

  Lim := P.LimitVal;
  if Lim <= 0 then Lim := 100;

  Body := '{"TableName":"' + P.TableName + '"' +
          ',"Limit":' + IntToStr(Lim);

  Filt := Trim(P.FilterExpression);
  if Filt <> '' then
    Body := Body + ',"FilterExpression":"' + Filt + '"';

  Body   := Body + '}';
  Result := CallAction(P.EndpointUrl, 'Scan', Body, P.AuthHeader);
end;

function TDynamoDBTool.DoCreateTable(const P: TDynamoDBParams): TJSONObject;
var
  BodyStr: string;
begin
  BodyStr := Trim(P.Body);
  if BodyStr = '' then
    raise Exception.Create('"body" is required for create_table — provide the full CreateTable JSON request body');
  Result := CallAction(P.EndpointUrl, 'CreateTable', BodyStr, P.AuthHeader);
end;

function TDynamoDBTool.DoDeleteTable(const P: TDynamoDBParams): TJSONObject;
var
  Body: string;
begin
  if Trim(P.TableName) = '' then
    raise Exception.Create('"tableName" is required for delete_table');
  Body   := '{"TableName":"' + P.TableName + '"}';
  Result := CallAction(P.EndpointUrl, 'DeleteTable', Body, P.AuthHeader);
end;

function TDynamoDBTool.ExecuteWithParams(const AParams: TDynamoDBParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op:      string;
  BodyStr: string;
  R:       TJSONObject;
begin
  try
    if Trim(AParams.EndpointUrl) = '' then
      raise Exception.Create('"endpointUrl" is required');

    Op := LowerCase(Trim(AParams.Operation));
    if Op = '' then
      raise Exception.Create('"operation" is required');

    (* If a raw body override is supplied and the operation supports it,
       route directly through CallAction with the appropriate action name. *)
    BodyStr := Trim(AParams.Body);

    if (BodyStr <> '') and
       (Op <> 'create_table') and
       (Op <> 'list_tables') then
    begin
      if      Op = 'describe_table' then R := CallAction(AParams.EndpointUrl, 'DescribeTable', BodyStr, AParams.AuthHeader)
      else if Op = 'get_item'       then R := CallAction(AParams.EndpointUrl, 'GetItem',       BodyStr, AParams.AuthHeader)
      else if Op = 'put_item'       then R := CallAction(AParams.EndpointUrl, 'PutItem',       BodyStr, AParams.AuthHeader)
      else if Op = 'delete_item'    then R := CallAction(AParams.EndpointUrl, 'DeleteItem',    BodyStr, AParams.AuthHeader)
      else if Op = 'query'          then R := CallAction(AParams.EndpointUrl, 'Query',         BodyStr, AParams.AuthHeader)
      else if Op = 'scan'           then R := CallAction(AParams.EndpointUrl, 'Scan',          BodyStr, AParams.AuthHeader)
      else if Op = 'delete_table'   then R := CallAction(AParams.EndpointUrl, 'DeleteTable',   BodyStr, AParams.AuthHeader)
      else raise Exception.CreateFmt('Unknown operation "%s"', [Op]);
    end
    else
    begin
      if      Op = 'list_tables'    then R := DoListTables(AParams)
      else if Op = 'describe_table' then R := DoDescribeTable(AParams)
      else if Op = 'get_item'       then R := DoGetItem(AParams)
      else if Op = 'put_item'       then R := DoPutItem(AParams)
      else if Op = 'delete_item'    then R := DoDeleteItem(AParams)
      else if Op = 'query'          then R := DoQuery(AParams)
      else if Op = 'scan'           then R := DoScan(AParams)
      else if Op = 'create_table'   then R := DoCreateTable(AParams)
      else if Op = 'delete_table'   then R := DoDeleteTable(AParams)
      else raise Exception.CreateFmt('Unknown operation "%s"', [Op]);
    end;

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

constructor TDynamoDBTool.Create;
begin
  inherited;
  FName        := 'mcp-dynamodb';
  FDescription :=
    'Amazon DynamoDB access via REST API. ' +
    'Supports DynamoDB Local (http://localhost:8000, no auth) and AWS DynamoDB ' +
    '(https://dynamodb.{region}.amazonaws.com, pass pre-computed AWS Signature V4 ' +
    'Authorization header via authHeader param). ' +
    'Operations: ' +
    'list_tables (params: limitVal?), ' +
    'describe_table (params: tableName), ' +
    'get_item (params: tableName, key=DynamoDB key JSON), ' +
    'put_item (params: tableName, item=DynamoDB item JSON), ' +
    'delete_item (params: tableName, key=DynamoDB key JSON), ' +
    'query (params: tableName, keyConditionExpression, expressionAttributeValues, filterExpression?, limitVal?), ' +
    'scan (params: tableName, filterExpression?, limitVal?), ' +
    'create_table (params: body=full CreateTable JSON), ' +
    'delete_table (params: tableName). ' +
    'For any operation, supply body to override the request body directly. ' +
    'Required params for all: operation, endpointUrl.';
end;

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-dynamodb',
    function: IAiMCPTool
    begin
      Result := TDynamoDBTool.Create;
    end);
  WriteLn(ErrOutput, '[MCPService]   + mcp-dynamodb');
end;

end.
