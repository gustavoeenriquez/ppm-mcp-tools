unit MCPTool.BigQuery;

(*
  MCPTool.BigQuery  ·  mcp-bigquery  (port 8644)
  Google BigQuery REST API v2 wrapper.

  Operations:
    query          - run a SQL query (synchronous)
    list_datasets  - list datasets in a project
    list_tables    - list tables in a dataset
    get_table      - get table schema and metadata
    insert_rows    - streaming insert rows into a table
    create_dataset - create a new dataset
    delete_dataset - delete a dataset (and its contents)

  Auth: OAuth2 Bearer access token
*)

interface

uses
  uMakerAi.MCPServer.Core,
  System.JSON;

type
  TBigQueryParams = class
  private
    FOperation:   string;
    FAccessToken: string;
    FProjectId:   string;
    FDatasetId:   string;
    FTableId:     string;
    FSql:         string;
    FRows:        string;
    FMaxResults:  Integer;
    FLocation:    string;
  public
    constructor Create;

    [AiMCPSchemaDescription('Operation: query, list_datasets, list_tables, get_table, insert_rows, create_dataset, delete_dataset')]
    property Operation:   string  read FOperation   write FOperation;

    [AiMCPSchemaDescription('OAuth2 access token (Bearer token for BigQuery API)')]
    property AccessToken: string  read FAccessToken write FAccessToken;

    [AiMCPSchemaDescription('GCP project ID (e.g. my-project-123)')]
    property ProjectId:   string  read FProjectId   write FProjectId;

    [AiMCPOptional]
    [AiMCPSchemaDescription('BigQuery dataset ID (required for list_tables, get_table, insert_rows, create_dataset, delete_dataset)')]
    property DatasetId:   string  read FDatasetId   write FDatasetId;

    [AiMCPOptional]
    [AiMCPSchemaDescription('BigQuery table ID (required for get_table and insert_rows)')]
    property TableId:     string  read FTableId     write FTableId;

    [AiMCPOptional]
    [AiMCPSchemaDescription('SQL query string (required for query operation)')]
    property Sql:         string  read FSql         write FSql;

    [AiMCPOptional]
    [AiMCPSchemaDescription('JSON array string of rows for insert_rows, e.g. [{"name":"John","age":30}]')]
    property Rows:        string  read FRows        write FRows;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Maximum number of rows to return for query (default: 1000)')]
    property MaxResults:  Integer read FMaxResults  write FMaxResults;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Dataset or query location, e.g. US, EU, us-central1')]
    property Location:    string  read FLocation    write FLocation;
  end;

  TBigQueryTool = class(TAiMCPToolBase<TBigQueryParams>)
  private
    function ApiGet(const URL, AccessToken: string): string;
    function ApiPost(const URL, AccessToken, Body: string): string;
    function ApiDelete(const URL, AccessToken: string): string;
    function ParseResponse(const Raw: string): TJSONObject;
    function DoQuery(const P: TBigQueryParams): TJSONObject;
    function DoListDatasets(const P: TBigQueryParams): TJSONObject;
    function DoListTables(const P: TBigQueryParams): TJSONObject;
    function DoGetTable(const P: TBigQueryParams): TJSONObject;
    function DoInsertRows(const P: TBigQueryParams): TJSONObject;
    function DoCreateDataset(const P: TBigQueryParams): TJSONObject;
    function DoDeleteDataset(const P: TBigQueryParams): TJSONObject;
  protected
    function ExecuteWithParams(const AParams: TBigQueryParams;
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

const
  BQ_BASE = 'https://bigquery.googleapis.com/bigquery/v2';

{ TBigQueryParams }

constructor TBigQueryParams.Create;
begin
  inherited;
  FMaxResults := 1000;
end;

{ TBigQueryTool }

function TBigQueryTool.ApiGet(const URL, AccessToken: string): string;
var
  HTTP: THTTPClient;
  Resp: IHTTPResponse;
begin
  HTTP := THTTPClient.Create;
  try
    Resp   := HTTP.Get(URL, nil,
      [TNameValuePair.Create('Authorization', 'Bearer ' + AccessToken),
       TNameValuePair.Create('Accept',        'application/json')]);
    Result := Resp.ContentAsString(TEncoding.UTF8);
  finally
    HTTP.Free;
  end;
end;

function TBigQueryTool.ApiPost(const URL, AccessToken, Body: string): string;
var
  HTTP:   THTTPClient;
  Stream: TStringStream;
  Resp:   IHTTPResponse;
begin
  HTTP   := THTTPClient.Create;
  Stream := TStringStream.Create(Body, TEncoding.UTF8);
  try
    Resp   := HTTP.Post(URL, Stream, nil,
      [TNameValuePair.Create('Authorization', 'Bearer ' + AccessToken),
       TNameValuePair.Create('Content-Type',  'application/json'),
       TNameValuePair.Create('Accept',        'application/json')]);
    Result := Resp.ContentAsString(TEncoding.UTF8);
  finally
    Stream.Free;
    HTTP.Free;
  end;
end;

function TBigQueryTool.ApiDelete(const URL, AccessToken: string): string;
var
  HTTP: THTTPClient;
  Resp: IHTTPResponse;
begin
  HTTP := THTTPClient.Create;
  try
    Resp   := HTTP.Delete(URL, nil,
      [TNameValuePair.Create('Authorization', 'Bearer ' + AccessToken),
       TNameValuePair.Create('Accept',        'application/json')]);
    Result := Resp.ContentAsString(TEncoding.UTF8);
  finally
    HTTP.Free;
  end;
end;

function TBigQueryTool.ParseResponse(const Raw: string): TJSONObject;
var
  J: TJSONValue;
begin
  J := TJSONObject.ParseJSONValue(Raw);
  if Assigned(J) then
  begin
    if J is TJSONObject then
      Result := J as TJSONObject
    else
    begin
      Result := TJSONObject.Create;
      Result.AddPair('data', J);
    end;
  end
  else
  begin
    Result := TJSONObject.Create;
    Result.AddPair('raw', TJSONString.Create(Raw));
  end;
end;

function TBigQueryTool.DoQuery(const P: TBigQueryParams): TJSONObject;
var
  Proj, Sql, Loc, URL, Body, Raw: string;
  MaxRes: Integer;
begin
  Proj := Trim(P.ProjectId);
  Sql  := Trim(P.Sql);
  if Sql = '' then raise Exception.Create('"sql" is required for query operation');

  MaxRes := P.MaxResults;
  if MaxRes <= 0 then MaxRes := 1000;

  Loc  := Trim(P.Location);
  URL  := BQ_BASE + '/projects/' + Proj + '/queries';

  Body := '{"query":' + TJSONString.Create(Sql).ToString +
          ',"useLegacySql":false' +
          ',"maxResults":' + IntToStr(MaxRes);

  if Loc <> '' then
    Body := Body + ',"location":' + TJSONString.Create(Loc).ToString;

  Body := Body + '}';

  Raw    := ApiPost(URL, P.AccessToken, Body);
  Result := ParseResponse(Raw);
end;

function TBigQueryTool.DoListDatasets(const P: TBigQueryParams): TJSONObject;
var
  Proj, URL, Raw: string;
begin
  Proj   := Trim(P.ProjectId);
  URL    := BQ_BASE + '/projects/' + Proj + '/datasets';
  Raw    := ApiGet(URL, P.AccessToken);
  Result := ParseResponse(Raw);
end;

function TBigQueryTool.DoListTables(const P: TBigQueryParams): TJSONObject;
var
  Proj, Ds, URL, Raw: string;
begin
  Proj := Trim(P.ProjectId);
  Ds   := Trim(P.DatasetId);
  if Ds = '' then raise Exception.Create('"datasetId" is required for list_tables operation');

  URL    := BQ_BASE + '/projects/' + Proj + '/datasets/' + Ds + '/tables';
  Raw    := ApiGet(URL, P.AccessToken);
  Result := ParseResponse(Raw);
end;

function TBigQueryTool.DoGetTable(const P: TBigQueryParams): TJSONObject;
var
  Proj, Ds, Tbl, URL, Raw: string;
begin
  Proj := Trim(P.ProjectId);
  Ds   := Trim(P.DatasetId);
  Tbl  := Trim(P.TableId);
  if Ds  = '' then raise Exception.Create('"datasetId" is required for get_table operation');
  if Tbl = '' then raise Exception.Create('"tableId" is required for get_table operation');

  URL    := BQ_BASE + '/projects/' + Proj + '/datasets/' + Ds + '/tables/' + Tbl;
  Raw    := ApiGet(URL, P.AccessToken);
  Result := ParseResponse(Raw);
end;

function TBigQueryTool.DoInsertRows(const P: TBigQueryParams): TJSONObject;
var
  Proj, Ds, Tbl, RowsStr, URL, Body, Raw: string;
  RowsVal:  TJSONValue;
  RowsArr:  TJSONArray;
  RowsOut:  TJSONArray;
  RowObj:   TJSONObject;
  WrapObj:  TJSONObject;
  i:        Integer;
begin
  Proj   := Trim(P.ProjectId);
  Ds     := Trim(P.DatasetId);
  Tbl    := Trim(P.TableId);
  RowsStr := Trim(P.Rows);

  if Ds     = '' then raise Exception.Create('"datasetId" is required for insert_rows operation');
  if Tbl    = '' then raise Exception.Create('"tableId" is required for insert_rows operation');
  if RowsStr = '' then raise Exception.Create('"rows" is required for insert_rows operation');

  RowsVal := TJSONObject.ParseJSONValue(RowsStr);
  if not Assigned(RowsVal) then
    raise Exception.Create('"rows" must be a valid JSON array');
  if not (RowsVal is TJSONArray) then
  begin
    RowsVal.Free;
    raise Exception.Create('"rows" must be a JSON array, e.g. [{"name":"John","age":30}]');
  end;

  RowsArr := RowsVal as TJSONArray;
  RowsOut := TJSONArray.Create;
  try
    for i := 0 to RowsArr.Count - 1 do
    begin
      RowObj  := RowsArr.Items[i] as TJSONObject;
      WrapObj := TJSONObject.Create;
      WrapObj.AddPair('insertId', 'row_' + IntToStr(i));
      WrapObj.AddPair('json', RowObj.Clone as TJSONValue);
      RowsOut.AddElement(WrapObj);
    end;

    URL  := BQ_BASE + '/projects/' + Proj + '/datasets/' + Ds + '/tables/' + Tbl + '/insertAll';
    Body := '{"rows":' + RowsOut.ToJSON + '}';
    Raw  := ApiPost(URL, P.AccessToken, Body);
  finally
    RowsVal.Free;
    RowsOut.Free;
  end;

  Result := ParseResponse(Raw);
end;

function TBigQueryTool.DoCreateDataset(const P: TBigQueryParams): TJSONObject;
var
  Proj, Ds, Loc, URL, Body, Raw: string;
begin
  Proj := Trim(P.ProjectId);
  Ds   := Trim(P.DatasetId);
  if Ds = '' then raise Exception.Create('"datasetId" is required for create_dataset operation');

  Loc  := Trim(P.Location);
  URL  := BQ_BASE + '/projects/' + Proj + '/datasets';

  Body := '{"datasetReference":{"projectId":' + TJSONString.Create(Proj).ToString +
          ',"datasetId":' + TJSONString.Create(Ds).ToString + '}';
  if Loc <> '' then
    Body := Body + ',"location":' + TJSONString.Create(Loc).ToString;
  Body := Body + '}';

  Raw    := ApiPost(URL, P.AccessToken, Body);
  Result := ParseResponse(Raw);
end;

function TBigQueryTool.DoDeleteDataset(const P: TBigQueryParams): TJSONObject;
var
  Proj, Ds, URL, Raw: string;
begin
  Proj := Trim(P.ProjectId);
  Ds   := Trim(P.DatasetId);
  if Ds = '' then raise Exception.Create('"datasetId" is required for delete_dataset operation');

  URL := BQ_BASE + '/projects/' + Proj + '/datasets/' + Ds + '?deleteContents=true';
  Raw := ApiDelete(URL, P.AccessToken);

  if Trim(Raw) = '' then
  begin
    Result := TJSONObject.Create;
    Result.AddPair('deleted',   TJSONTrue.Create);
    Result.AddPair('datasetId', TJSONString.Create(Ds));
    Result.AddPair('projectId', TJSONString.Create(Proj));
  end
  else
    Result := ParseResponse(Raw);
end;

function TBigQueryTool.ExecuteWithParams(const AParams: TBigQueryParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op:  string;
  Tok: string;
  R:   TJSONObject;
begin
  try
    Tok := Trim(AParams.AccessToken);
    if Tok = '' then
      raise Exception.Create('"accessToken" is required (OAuth2 Bearer token)');
    if Trim(AParams.ProjectId) = '' then
      raise Exception.Create('"projectId" is required');

    Op := LowerCase(Trim(AParams.Operation));
    if Op = '' then raise Exception.Create('"operation" is required');

    if      Op = 'query'          then R := DoQuery(AParams)
    else if Op = 'list_datasets'  then R := DoListDatasets(AParams)
    else if Op = 'list_tables'    then R := DoListTables(AParams)
    else if Op = 'get_table'      then R := DoGetTable(AParams)
    else if Op = 'insert_rows'    then R := DoInsertRows(AParams)
    else if Op = 'create_dataset' then R := DoCreateDataset(AParams)
    else if Op = 'delete_dataset' then R := DoDeleteDataset(AParams)
    else raise Exception.CreateFmt('Unknown operation "%s"', [Op]);

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

constructor TBigQueryTool.Create;
begin
  inherited;
  FName        := 'mcp-bigquery';
  FDescription :=
    'Google BigQuery REST API v2 wrapper. Requires OAuth2 accessToken and projectId for all operations. ' +
    'Operations: ' +
    'query (params: sql, maxResults? [default 1000], location?) → run a SQL query and return rows/schema; ' +
    'list_datasets (params: —) → list all datasets in the project; ' +
    'list_tables (params: datasetId) → list tables in a dataset; ' +
    'get_table (params: datasetId, tableId) → get table schema and metadata; ' +
    'insert_rows (params: datasetId, tableId, rows=JSON array e.g. [{"col":"val"}]) → streaming insert; ' +
    'create_dataset (params: datasetId, location?) → create a new dataset; ' +
    'delete_dataset (params: datasetId) → delete dataset and all its contents.';
end;

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-bigquery',
    function: IAiMCPTool
    begin
      Result := TBigQueryTool.Create;
    end);
  WriteLn(ErrOutput, '[MCPService]   + mcp-bigquery');
end;

end.
