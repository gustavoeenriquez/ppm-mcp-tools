unit MCPTool.DB2;

{
  MCPTool.DB2  ·  mcp-db2
  IBM DB2 LUW (Linux/Unix/Windows) via FireDAC native driver.
  Supports DB2 11.5+ and IBM Db2 on Cloud.
  Requires IBM Data Server Driver Package (db2cli.dll) installed.
}

interface

uses
  uMakerAi.MCPServer.Core,
  System.SysUtils,
  MCPTool.FDBase,
  FireDAC.Phys.DB2,
  FireDAC.Comp.Client;

type
  TDB2Tool = class(TFDBaseTool)
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

{ TDB2Tool }

function TDB2Tool.GetDefaultPort: Integer;
begin
  Result := 50000;
end;

function TDB2Tool.GetListTablesSQL(const DB, Schema: string): string;
var
  SchemaFilter: string;
begin
  if Trim(Schema) <> '' then
    SchemaFilter := UpperCase(Trim(Schema))
  else
    SchemaFilter := '';

  if SchemaFilter <> '' then
    Result :=
      'SELECT TABNAME, TABSCHEMA, TYPE FROM SYSCAT.TABLES ' +
      'WHERE TABSCHEMA = ''' + SchemaFilter + ''' AND TYPE = ''T'' ' +
      'ORDER BY TABNAME'
  else
    Result :=
      'SELECT TABNAME, TABSCHEMA, TYPE FROM SYSCAT.TABLES ' +
      'WHERE TABSCHEMA = CURRENT_SCHEMA AND TYPE = ''T'' ' +
      'ORDER BY TABNAME';
end;

function TDB2Tool.GetDescribeSQL(const Table, DB, Schema: string): string;
var
  SchemaFilter, TableUpper: string;
begin
  TableUpper   := UpperCase(Trim(Table));
  SchemaFilter := UpperCase(Trim(Schema));

  if SchemaFilter <> '' then
    Result := Format(
      'SELECT COLNAME, TYPENAME, LENGTH, SCALE, NULLS, "DEFAULT", KEYSEQ, COLNO ' +
      'FROM SYSCAT.COLUMNS ' +
      'WHERE TABSCHEMA = ''%s'' AND TABNAME = ''%s'' ' +
      'ORDER BY COLNO',
      [SchemaFilter, TableUpper])
  else
    Result := Format(
      'SELECT COLNAME, TYPENAME, LENGTH, SCALE, NULLS, "DEFAULT", KEYSEQ, COLNO ' +
      'FROM SYSCAT.COLUMNS ' +
      'WHERE TABSCHEMA = CURRENT_SCHEMA AND TABNAME = ''%s'' ' +
      'ORDER BY COLNO',
      [TableUpper]);
end;

function TDB2Tool.GetListDatabasesSQL: string;
begin
  // DB2 LUW: within a connection, the closest to "list databases" is listing
  // user-visible schemas (excludes system schemas prefixed with SYS/IBM/DB2).
  Result :=
    'SELECT SCHEMANAME, OWNER FROM SYSCAT.SCHEMATA ' +
    'WHERE SCHEMANAME NOT LIKE ''SYS%'' ' +
    '  AND SCHEMANAME NOT LIKE ''IBM%'' ' +
    '  AND SCHEMANAME <> ''NULLID'' ' +
    'ORDER BY SCHEMANAME';
end;

procedure TDB2Tool.ConfigureConnection(Conn: TFDConnection;
  const P: TFDParams);
begin
  // FireDAC handles Server/Port/Database/UID/PWD for DB2 automatically.
  // Additional options (e.g. CURRENTSCHEMA, CONNECTTIMEOUT) can be added here.
end;

constructor TDB2Tool.Create;
begin
  inherited;
  FDriverID    := 'DB2';
  FName        := 'mcp-db2';
  FDescription :=
    'IBM DB2 LUW database access via FireDAC native driver. ' +
    'Operations: query (SELECT → JSON rows), execute (INSERT/UPDATE/DELETE/DDL → rowsAffected), ' +
    'execute_tx (JSON array of SQL in one transaction), ' +
    'list_tables (params: schema?), describe (params: table, schema?), ' +
    'list_databases (lists user schemas). ' +
    'Required params: host, database, username. ' +
    'Optional: port (default 50000), password, maxRows (default 100), timeout (default 30s). ' +
    'Requires IBM Data Server Driver Package (db2cli.dll) on the machine.';
end;

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-db2',
    function: IAiMCPTool
    begin
      Result := TDB2Tool.Create;
    end);
  WriteLn(ErrOutput, '[MCPService]   + mcp-db2');
end;

end.
