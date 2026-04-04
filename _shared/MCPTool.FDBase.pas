// Nombre: Gustavo Enríquez
// Redes Sociales:
// - Email: gustavoeenriquez@gmail.com

// - Telegram: https://t.me/MakerAi_Suite_Delphi
// - Telegram: https://t.me/MakerAi_Delphi_Suite_English

// - LinkedIn: https://www.linkedin.com/in/gustavo-enriquez-3937654a/
// - Youtube: https://www.youtube.com/@cimamaker3945
// - GitHub: https://github.com/gustavoeenriquez/

unit MCPTool.FDBase;

{
  MCPTool.FDBase  —  Base FireDAC tool shared by all DB tools
  (MySQL, MSSQL, Oracle, Firebird, ODBC)

  Operations (all tools):
    query        - execute SELECT, return rows as JSON
    execute      - execute INSERT/UPDATE/DELETE/DDL, return affected rows
    execute_tx   - execute multiple SQL statements in a single transaction
    list_tables  - list tables in database/schema
    describe     - describe columns of a table
    list_databases - list available databases/schemas
}

interface

uses
  uMakerAi.MCPServer.Core,
  System.SysUtils,
  System.JSON,
  System.Classes,
  System.Variants,
  // FireDAC core
  FireDAC.Stan.Intf,
  FireDAC.Stan.Option,
  FireDAC.Stan.Error,
  FireDAC.Stan.Def,
  FireDAC.Stan.Pool,
  FireDAC.Stan.Async,
  FireDAC.Phys,
  FireDAC.Phys.Intf,
  FireDAC.UI.Intf,
  FireDAC.Comp.Client,
  FireDAC.Stan.Param,
  FireDAC.DApt,
  // Data
  Data.DB;

type

  TFDParams = class
  private
    FOperation:  string;
    FHost:       string;
    FPort:       Integer;
    FDatabase:   string;
    FUsername:   string;
    FPassword:   string;
    FSQL:        string;
    FSQLList:    string;
    FTable:      string;
    FSchema:     string;
    FMaxRows:    Integer;
    FTimeout:    Integer;
    FDSN:        string;
    FODBCDriver: string;
    FCharset:    string;
  public
    constructor Create;

    [AiMCPSchemaDescription('Operation: query, execute, execute_tx, list_tables, describe, list_databases')]
    property Operation:  string  read FOperation  write FOperation;

    [AiMCPSchemaDescription('Database host or IP address')]
    property Host:       string  read FHost       write FHost;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Port (default depends on DB: MySQL=3306, MSSQL=1433, Oracle=1521, Firebird=3050)')]
    property Port:       Integer read FPort       write FPort;

    [AiMCPSchemaDescription('Database name (or service name for Oracle, path for Firebird)')]
    property Database:   string  read FDatabase   write FDatabase;

    [AiMCPSchemaDescription('Username')]
    property Username:   string  read FUsername   write FUsername;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Password')]
    property Password:   string  read FPassword   write FPassword;

    [AiMCPOptional]
    [AiMCPSchemaDescription('SQL statement (for query and execute)')]
    property SQL:        string  read FSQL        write FSQL;

    [AiMCPOptional]
    [AiMCPSchemaDescription('JSON array of SQL statements to execute in a single transaction (for execute_tx)')]
    property SQLList:    string  read FSQLList    write FSQLList;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Table name (for describe)')]
    property Table:      string  read FTable      write FTable;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Schema/owner name (optional filter for list_tables and describe)')]
    property Schema:     string  read FSchema     write FSchema;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Maximum rows to return (default: 100)')]
    property MaxRows:    Integer read FMaxRows    write FMaxRows;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Query timeout in seconds (default: 30)')]
    property Timeout:    Integer read FTimeout    write FTimeout;

    [AiMCPOptional]
    [AiMCPSchemaDescription('ODBC Data Source Name (for mcp-odbc when using a configured DSN)')]
    property DSN:        string  read FDSN        write FDSN;

    [AiMCPOptional]
    [AiMCPSchemaDescription('ODBC driver name, e.g. "{ODBC Driver 17 for SQL Server}" (for mcp-odbc without DSN)')]
    property ODBCDriver: string  read FODBCDriver write FODBCDriver;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Character set / collation (e.g. utf8mb4 for MySQL)')]
    property Charset:    string  read FCharset    write FCharset;
  end;

  TFDBaseTool = class(TAiMCPToolBase<TFDParams>)
  private
    function BuildConnection(const P: TFDParams): TFDConnection;
    function RowsToJSON(Q: TFDQuery; MaxRows: Integer): TJSONObject;
    function FieldToJSON(F: TField): TJSONValue;
    function DoQuery(const P: TFDParams): TJSONObject;
    function DoExecute(const P: TFDParams): TJSONObject;
    function DoExecuteTx(const P: TFDParams): TJSONObject;
    function DoListTables(const P: TFDParams): TJSONObject;
    function DoDescribe(const P: TFDParams): TJSONObject;
    function DoListDatabases(const P: TFDParams): TJSONObject;
  protected
    FDriverID: string;
    function GetDefaultPort: Integer; virtual;
    function GetListTablesSQL(const DB, Schema: string): string; virtual;
    function GetDescribeSQL(const Table, DB, Schema: string): string; virtual;
    function GetListDatabasesSQL: string; virtual;
    procedure ConfigureConnection(Conn: TFDConnection;
      const P: TFDParams); virtual;
    function ExecuteWithParams(const AParams: TFDParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  end;

implementation

{ TFDParams }

constructor TFDParams.Create;
begin
  inherited;
  FHost    := 'localhost';
  FMaxRows := 100;
  FTimeout := 30;
end;

{ TFDBaseTool }

function TFDBaseTool.GetDefaultPort: Integer;
begin
  Result := 0;
end;

function TFDBaseTool.GetListTablesSQL(const DB, Schema: string): string;
begin
  Result := 'SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES ' +
            'WHERE TABLE_TYPE=''BASE TABLE''';
end;

function TFDBaseTool.GetDescribeSQL(const Table, DB, Schema: string): string;
begin
  Result := 'SELECT COLUMN_NAME, DATA_TYPE, IS_NULLABLE, COLUMN_DEFAULT ' +
            'FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME=''' + Table + '''';
end;

function TFDBaseTool.GetListDatabasesSQL: string;
begin
  Result := '';
end;

procedure TFDBaseTool.ConfigureConnection(Conn: TFDConnection;
  const P: TFDParams);
begin
  // Base: no extra config
end;

function TFDBaseTool.BuildConnection(const P: TFDParams): TFDConnection;
var
  Port: Integer;
begin
  Result := TFDConnection.Create(nil);
  try
    Result.LoginPrompt := False;
    Result.Params.DriverID := FDriverID;

    if FDriverID = 'ODBC' then
    begin
      // ODBC: use DSN or driver+server
      if Trim(P.DSN) <> '' then
        Result.Params.Add('DataSource=' + P.DSN)
      else
      begin
        if Trim(P.ODBCDriver) <> '' then
          Result.Params.Add('ODBCDriver=' + P.ODBCDriver);
        Result.Params.Add('Server=' + P.Host);
        if P.Port > 0 then
          Result.Params.Add('Port=' + IntToStr(P.Port));
        if Trim(P.Database) <> '' then
          Result.Params.Add('Database=' + P.Database);
      end;
    end
    else
    begin
      Result.Params.Add('Server=' + Trim(P.Host));
      Port := P.Port;
      if Port <= 0 then Port := GetDefaultPort;
      if Port > 0 then
        Result.Params.Add('Port=' + IntToStr(Port));
      if Trim(P.Database) <> '' then
        Result.Params.Add('Database=' + Trim(P.Database));
    end;

    if Trim(P.Username) <> '' then
      Result.Params.Add('User_Name=' + Trim(P.Username));
    if Trim(P.Password) <> '' then
      Result.Params.Add('Password=' + Trim(P.Password));

    ConfigureConnection(Result, P);
    Result.Open;
  except
    Result.Free;
    raise;
  end;
end;

function TFDBaseTool.FieldToJSON(F: TField): TJSONValue;
begin
  if F.IsNull then
    Exit(TJSONNull.Create);

  case F.DataType of
    ftInteger, ftSmallint, ftWord, ftByte, ftShortint:
      Result := TJSONNumber.Create(F.AsInteger);
    ftLargeint:
      Result := TJSONNumber.Create(F.AsLargeInt);
    ftFloat, ftCurrency, ftExtended, ftSingle:
      Result := TJSONNumber.Create(F.AsFloat);
    ftBCD, ftFMTBcd:
      Result := TJSONNumber.Create(F.AsFloat);
    ftBoolean:
      Result := TJSONBool.Create(F.AsBoolean);
    ftDate:
      Result := TJSONString.Create(FormatDateTime('yyyy-mm-dd', F.AsDateTime));
    ftTime:
      Result := TJSONString.Create(FormatDateTime('hh:nn:ss', F.AsDateTime));
    ftDateTime, ftTimeStamp:
      Result := TJSONString.Create(FormatDateTime('yyyy-mm-dd hh:nn:ss', F.AsDateTime));
    ftBlob, ftGraphic, ftOraBlob, ftOraClob:
      Result := TJSONString.Create('<blob>');
    else
      Result := TJSONString.Create(F.AsString);
  end;
end;

function TFDBaseTool.RowsToJSON(Q: TFDQuery; MaxRows: Integer): TJSONObject;
var
  Rows:    TJSONArray;
  Cols:    TJSONArray;
  Row:     TJSONObject;
  i, N:    Integer;
begin
  Result := TJSONObject.Create;
  Rows   := TJSONArray.Create;
  Cols   := TJSONArray.Create;

  // Column names
  for i := 0 to Q.FieldCount - 1 do
    Cols.Add(Q.Fields[i].FieldName);

  // Rows
  N := 0;
  while not Q.EOF and ((MaxRows <= 0) or (N < MaxRows)) do
  begin
    Row := TJSONObject.Create;
    for i := 0 to Q.FieldCount - 1 do
      Row.AddPair(Q.Fields[i].FieldName, FieldToJSON(Q.Fields[i]));
    Rows.AddElement(Row);
    Q.Next;
    Inc(N);
  end;

  Result.AddPair('columns', Cols);
  Result.AddPair('rows',    Rows);
  Result.AddPair('count',   TJSONNumber.Create(N));
  Result.AddPair('ok',      TJSONTrue.Create);
end;

function TFDBaseTool.DoQuery(const P: TFDParams): TJSONObject;
var
  Conn: TFDConnection;
  Q:    TFDQuery;
  MaxR: Integer;
begin
  if Trim(P.SQL) = '' then raise Exception.Create('"sql" required for query');
  MaxR := P.MaxRows; if MaxR <= 0 then MaxR := 100;

  Conn := BuildConnection(P);
  try
    Q := TFDQuery.Create(nil);
    try
      Q.Connection  := Conn;
      Q.FetchOptions.RecsMax := MaxR;
      Q.SQL.Text := P.SQL;
      Q.Open;
      Result := RowsToJSON(Q, MaxR);
    finally
      Q.Free;
    end;
  finally
    Conn.Free;
  end;
end;

function TFDBaseTool.DoExecute(const P: TFDParams): TJSONObject;
var
  Conn: TFDConnection;
  Q:    TFDQuery;
  Rows: Integer;
begin
  if Trim(P.SQL) = '' then raise Exception.Create('"sql" required for execute');

  Conn := BuildConnection(P);
  try
    Q := TFDQuery.Create(nil);
    try
      Q.Connection := Conn;
      Q.SQL.Text := P.SQL;
      Q.ExecSQL;
      Rows := Q.RowsAffected;
    finally
      Q.Free;
    end;
  finally
    Conn.Free;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('rowsAffected', TJSONNumber.Create(Rows));
  Result.AddPair('ok',           TJSONTrue.Create);
end;

function TFDBaseTool.DoExecuteTx(const P: TFDParams): TJSONObject;
var
  Conn:      TFDConnection;
  Q:         TFDQuery;
  StmtArr:   TJSONValue;
  Arr:       TJSONArray;
  i, Total:  Integer;
  Stmt:      string;
begin
  if Trim(P.SQLList) = '' then raise Exception.Create('"sqlList" (JSON array) required for execute_tx');

  StmtArr := TJSONObject.ParseJSONValue(P.SQLList);
  if not (StmtArr is TJSONArray) then
  begin
    StmtArr.Free;
    raise Exception.Create('"sqlList" must be a JSON array of SQL strings');
  end;
  Arr := StmtArr as TJSONArray;

  Conn := BuildConnection(P);
  try
    Conn.StartTransaction;
    try
      Q := TFDQuery.Create(nil);
      try
        Q.Connection := Conn;
        Total := 0;
        for i := 0 to Arr.Count - 1 do
        begin
          Stmt := Trim(Arr.Items[i].Value);
          if Stmt = '' then Continue;
          Q.SQL.Text := Stmt;
          Q.ExecSQL;
          Inc(Total, Q.RowsAffected);
        end;
      finally
        Q.Free;
      end;
      Conn.Commit;
    except
      Conn.Rollback;
      raise;
    end;
  finally
    Conn.Free;
    Arr.Free;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('statementsExecuted', TJSONNumber.Create(Arr.Count));
  Result.AddPair('totalRowsAffected',  TJSONNumber.Create(Total));
  Result.AddPair('ok',                 TJSONTrue.Create);
end;

function TFDBaseTool.DoListTables(const P: TFDParams): TJSONObject;
var
  Conn:  TFDConnection;
  Q:     TFDQuery;
  Tables: TJSONArray;
begin
  Conn := BuildConnection(P);
  try
    Q := TFDQuery.Create(nil);
    try
      Q.Connection := Conn;
      Q.SQL.Text   := GetListTablesSQL(P.Database, P.Schema);
      Q.Open;
      Tables := TJSONArray.Create;
      while not Q.EOF do
      begin
        Tables.Add(Q.Fields[0].AsString.Trim);
        Q.Next;
      end;
    finally
      Q.Free;
    end;
  finally
    Conn.Free;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('tables', Tables);
  Result.AddPair('count',  TJSONNumber.Create(Tables.Count));
  Result.AddPair('ok',     TJSONTrue.Create);
end;

function TFDBaseTool.DoDescribe(const P: TFDParams): TJSONObject;
var
  Conn: TFDConnection;
  Q:    TFDQuery;
  Cols: TJSONArray;
  Col:  TJSONObject;
begin
  if Trim(P.Table) = '' then raise Exception.Create('"table" required for describe');

  Conn := BuildConnection(P);
  try
    Q := TFDQuery.Create(nil);
    try
      Q.Connection := Conn;
      Q.SQL.Text   := GetDescribeSQL(P.Table, P.Database, P.Schema);
      Q.Open;
      Cols := TJSONArray.Create;
      while not Q.EOF do
      begin
        Col := TJSONObject.Create;
        var i: Integer;
        for i := 0 to Q.FieldCount - 1 do
          Col.AddPair(Q.Fields[i].FieldName.ToLower,
            TJSONString.Create(Q.Fields[i].AsString.Trim));
        Cols.AddElement(Col);
        Q.Next;
      end;
    finally
      Q.Free;
    end;
  finally
    Conn.Free;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('table',   P.Table);
  Result.AddPair('columns', Cols);
  Result.AddPair('count',   TJSONNumber.Create(Cols.Count));
  Result.AddPair('ok',      TJSONTrue.Create);
end;

function TFDBaseTool.DoListDatabases(const P: TFDParams): TJSONObject;
var
  Conn: TFDConnection;
  Q:    TFDQuery;
  DBs:  TJSONArray;
  SQL:  string;
begin
  SQL := GetListDatabasesSQL;
  if SQL = '' then
  begin
    Result := TJSONObject.Create;
    Result.AddPair('databases', TJSONArray.Create);
    Result.AddPair('note', 'list_databases not supported for this driver');
    Result.AddPair('ok',   TJSONTrue.Create);
    Exit;
  end;

  Conn := BuildConnection(P);
  try
    Q := TFDQuery.Create(nil);
    try
      Q.Connection := Conn;
      Q.SQL.Text   := SQL;
      Q.Open;
      DBs := TJSONArray.Create;
      while not Q.EOF do
      begin
        DBs.Add(Q.Fields[0].AsString.Trim);
        Q.Next;
      end;
    finally
      Q.Free;
    end;
  finally
    Conn.Free;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('databases', DBs);
  Result.AddPair('count',     TJSONNumber.Create(DBs.Count));
  Result.AddPair('ok',        TJSONTrue.Create);
end;

function TFDBaseTool.ExecuteWithParams(const AParams: TFDParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op: string;
  R:  TJSONObject;
begin
  try
    Op := LowerCase(Trim(AParams.Operation));
    if Op = '' then raise Exception.Create('"operation" is required');

    if      Op = 'query'          then R := DoQuery(AParams)
    else if Op = 'execute'        then R := DoExecute(AParams)
    else if Op = 'execute_tx'     then R := DoExecuteTx(AParams)
    else if Op = 'list_tables'    then R := DoListTables(AParams)
    else if Op = 'describe'       then R := DoDescribe(AParams)
    else if Op = 'list_databases' then R := DoListDatabases(AParams)
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

end.
