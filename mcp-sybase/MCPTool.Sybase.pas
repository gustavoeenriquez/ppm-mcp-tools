unit MCPTool.Sybase;

{
  MCPTool.Sybase  ·  mcp-sybase
  SAP SQL Anywhere (formerly Sybase Adaptive Server Anywhere / ASA)
  via FireDAC native driver.
  Supports SQL Anywhere 16, 17, 19+ and SAP SQL Anywhere cloud editions.
  Requires SQL Anywhere client libraries (dbodbc17.dll / dbodbc19.dll).
}

interface

uses
  uMakerAi.MCPServer.Core,
  System.SysUtils,
  MCPTool.FDBase,
  FireDAC.Phys.ASA,
  FireDAC.Comp.Client;

type
  TSybaseTool = class(TFDBaseTool)
  protected
    function GetDefaultPort: Integer; override;
    function GetListTablesSQL(const DB, Schema: string): string; override;
    function GetDescribeSQL(const Table, DB, Schema: string): string; override;
    function GetListDatabasesSQL: string; override;
    procedure ConfigureConnection(Conn: TFDConnection;
      const P: TFDParams); override;
  public
    constructor Create; override;
  end;

procedure RegisterTools(AServer: TAiMCPServer);

implementation

{ TSybaseTool }

function TSybaseTool.GetDefaultPort: Integer;
begin
  Result := 2638;
end;

function TSybaseTool.GetListTablesSQL(const DB, Schema: string): string;
var
  SchemaFilter: string;
begin
  SchemaFilter := Trim(Schema);
  if SchemaFilter <> '' then
    Result :=
      'SELECT t.table_name, t.table_schema ' +
      'FROM INFORMATION_SCHEMA.TABLES t ' +
      'WHERE t.table_type = ''BASE TABLE'' ' +
      '  AND t.table_schema = ''' + SchemaFilter + ''' ' +
      'ORDER BY t.table_name'
  else
    Result :=
      'SELECT t.table_name, t.table_schema ' +
      'FROM INFORMATION_SCHEMA.TABLES t ' +
      'WHERE t.table_type = ''BASE TABLE'' ' +
      '  AND t.table_schema NOT IN (''SYS'', ''SYSTEM'') ' +
      'ORDER BY t.table_schema, t.table_name';
end;

function TSybaseTool.GetDescribeSQL(const Table, DB, Schema: string): string;
var
  SchemaFilter: string;
begin
  SchemaFilter := Trim(Schema);
  if SchemaFilter <> '' then
    Result := Format(
      'SELECT column_name, data_type, character_maximum_length, ' +
      'numeric_precision, numeric_scale, is_nullable, column_default, ordinal_position ' +
      'FROM INFORMATION_SCHEMA.COLUMNS ' +
      'WHERE table_schema = ''%s'' AND table_name = ''%s'' ' +
      'ORDER BY ordinal_position',
      [SchemaFilter, Table])
  else
    Result := Format(
      'SELECT column_name, data_type, character_maximum_length, ' +
      'numeric_precision, numeric_scale, is_nullable, column_default, ordinal_position ' +
      'FROM INFORMATION_SCHEMA.COLUMNS ' +
      'WHERE table_name = ''%s'' ' +
      'ORDER BY ordinal_position',
      [Table]);
end;

function TSybaseTool.GetListDatabasesSQL: string;
begin
  // SQL Anywhere: list all user-visible schemas
  Result :=
    'SELECT schema_name FROM INFORMATION_SCHEMA.SCHEMATA ' +
    'WHERE schema_name NOT IN (''SYS'', ''SYSTEM'', ''INFORMATION_SCHEMA'') ' +
    'ORDER BY schema_name';
end;

procedure TSybaseTool.ConfigureConnection(Conn: TFDConnection;
  const P: TFDParams);
begin
  // SQL Anywhere FireDAC uses standard Server/Port/Database/UID/PWD params.
  // DatabaseName can also be specified as a service name.
  if Trim(P.Charset) <> '' then
    Conn.Params.Add('CharSet=' + Trim(P.Charset));
end;

constructor TSybaseTool.Create;
begin
  inherited;
  FDriverID    := 'ASA';
  FName        := 'mcp-sybase';
  FDescription :=
    'SAP SQL Anywhere (Sybase ASA) database access via FireDAC native driver. ' +
    'Operations: query (SELECT → JSON rows), execute (INSERT/UPDATE/DELETE/DDL → rowsAffected), ' +
    'execute_tx (JSON array of SQL in one transaction), ' +
    'list_tables (params: schema?), describe (params: table, schema?), ' +
    'list_databases (lists schemas). ' +
    'Required params: host, database, username. ' +
    'Optional: port (default 2638), password, maxRows (default 100), timeout (default 30s). ' +
    'Requires SQL Anywhere client libraries (dbodbc17.dll or dbodbc19.dll).';
end;

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-sybase',
    function: IAiMCPTool
    begin
      Result := TSybaseTool.Create;
    end);
  WriteLn(ErrOutput, '[MCPService]   + mcp-sybase');
end;

end.
