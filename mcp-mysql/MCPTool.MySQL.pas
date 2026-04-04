unit MCPTool.MySQL;

{
  MCPTool.MySQL  ·  mcp-mysql
  MySQL and MariaDB via FireDAC native driver.
}

interface

uses
  uMakerAi.MCPServer.Core,
  System.SysUtils,
  MCPTool.FDBase,
  FireDAC.Phys.MySQL,
  FireDAC.Comp.Client;

type
  TMySQLTool = class(TFDBaseTool)
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

{ TMySQLTool }

function TMySQLTool.GetDefaultPort: Integer;
begin
  Result := 3306;
end;

function TMySQLTool.GetListTablesSQL(const DB, Schema: string): string;
var
  DBFilter: string;
begin
  if Trim(Schema) <> '' then
    DBFilter := Schema
  else if Trim(DB) <> '' then
    DBFilter := DB
  else
    DBFilter := '';

  if DBFilter <> '' then
    Result := 'SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES ' +
              'WHERE TABLE_SCHEMA = ''' + DBFilter + ''' ORDER BY TABLE_NAME'
  else
    Result := 'SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES ' +
              'WHERE TABLE_SCHEMA = DATABASE() ORDER BY TABLE_NAME';
end;

function TMySQLTool.GetDescribeSQL(const Table, DB, Schema: string): string;
var
  DBFilter: string;
begin
  if Trim(Schema) <> '' then DBFilter := Schema
  else if Trim(DB) <> '' then DBFilter := DB
  else DBFilter := 'DATABASE()';

  if DBFilter = 'DATABASE()' then
    Result := Format(
      'SELECT COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH, IS_NULLABLE, ' +
      'COLUMN_DEFAULT, COLUMN_KEY, EXTRA ' +
      'FROM INFORMATION_SCHEMA.COLUMNS ' +
      'WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ''%s'' ' +
      'ORDER BY ORDINAL_POSITION', [Table])
  else
    Result := Format(
      'SELECT COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH, IS_NULLABLE, ' +
      'COLUMN_DEFAULT, COLUMN_KEY, EXTRA ' +
      'FROM INFORMATION_SCHEMA.COLUMNS ' +
      'WHERE TABLE_SCHEMA = ''%s'' AND TABLE_NAME = ''%s'' ' +
      'ORDER BY ORDINAL_POSITION', [DBFilter, Table]);
end;

function TMySQLTool.GetListDatabasesSQL: string;
begin
  Result := 'SHOW DATABASES';
end;

procedure TMySQLTool.ConfigureConnection(Conn: TFDConnection;
  const P: TFDParams);
begin
  if Trim(P.Charset) <> '' then
    Conn.Params.Add('CharacterSet=' + Trim(P.Charset))
  else
    Conn.Params.Add('CharacterSet=utf8mb4');
end;

constructor TMySQLTool.Create;
begin
  inherited;
  FDriverID    := 'MySQL';
  FName        := 'mcp-mysql';
  FDescription :=
    'MySQL and MariaDB database access via FireDAC native driver. ' +
    'Operations: query (SELECT → JSON rows), execute (INSERT/UPDATE/DELETE/DDL → rowsAffected), ' +
    'execute_tx (JSON array of SQL in one transaction), ' +
    'list_tables (params: schema?), describe (params: table, schema?), ' +
    'list_databases. Required params: host, database, username. ' +
    'Optional: port (default 3306), password, maxRows (default 100), ' +
    'timeout (default 30s), charset (default utf8mb4).';
end;

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-mysql',
    function: IAiMCPTool
    begin
      Result := TMySQLTool.Create;
    end);
  WriteLn(ErrOutput, '[MCPService]   + mcp-mysql');
end;

end.
