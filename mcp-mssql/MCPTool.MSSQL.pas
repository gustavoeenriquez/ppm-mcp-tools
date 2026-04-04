unit MCPTool.MSSQL;

{
  MCPTool.MSSQL  ·  mcp-mssql
  Microsoft SQL Server via FireDAC native driver.
  Supports SQL Server 2008+ and Azure SQL Database.
}

interface

uses
  uMakerAi.MCPServer.Core,
  System.SysUtils,
  MCPTool.FDBase,
  FireDAC.Phys.MSSQL,
  FireDAC.Comp.Client;

type
  TMSSQLTool = class(TFDBaseTool)
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

{ TMSSQLTool }

function TMSSQLTool.GetDefaultPort: Integer;
begin
  Result := 1433;
end;

function TMSSQLTool.GetListTablesSQL(const DB, Schema: string): string;
var
  SchemaFilter: string;
begin
  if Trim(Schema) <> '' then
    SchemaFilter := ' AND TABLE_SCHEMA = ''' + Schema + ''''
  else
    SchemaFilter := '';
  Result := 'SELECT TABLE_SCHEMA, TABLE_NAME FROM INFORMATION_SCHEMA.TABLES ' +
            'WHERE TABLE_TYPE = ''BASE TABLE''' + SchemaFilter +
            ' ORDER BY TABLE_SCHEMA, TABLE_NAME';
end;

function TMSSQLTool.GetDescribeSQL(const Table, DB, Schema: string): string;
var
  SchemaFilter: string;
begin
  if Trim(Schema) <> '' then
    SchemaFilter := ' AND TABLE_SCHEMA = ''' + Schema + ''''
  else
    SchemaFilter := '';
  Result := Format(
    'SELECT COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH, NUMERIC_PRECISION, ' +
    'NUMERIC_SCALE, IS_NULLABLE, COLUMN_DEFAULT ' +
    'FROM INFORMATION_SCHEMA.COLUMNS ' +
    'WHERE TABLE_NAME = ''%s''%s ' +
    'ORDER BY ORDINAL_POSITION',
    [Table, SchemaFilter]);
end;

function TMSSQLTool.GetListDatabasesSQL: string;
begin
  Result := 'SELECT name FROM sys.databases ORDER BY name';
end;

procedure TMSSQLTool.ConfigureConnection(Conn: TFDConnection;
  const P: TFDParams);
begin
  // Windows auth when no username provided
  if Trim(P.Username) = '' then
    Conn.Params.Add('OSAuthent=Yes')
  else
    Conn.Params.Add('OSAuthent=No');
  // Enable MARS for compatibility
  Conn.Params.Add('MARS=Yes');
end;

constructor TMSSQLTool.Create;
begin
  inherited;
  FDriverID    := 'MSSQL';
  FName        := 'mcp-mssql';
  FDescription :=
    'Microsoft SQL Server and Azure SQL Database via FireDAC native driver. ' +
    'Operations: query, execute, execute_tx, list_tables (params: schema?), ' +
    'describe (params: table, schema?), list_databases. ' +
    'Required: host, database, username (omit for Windows auth). ' +
    'Optional: port (default 1433), password, maxRows, timeout, schema.';
end;

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-mssql',
    function: IAiMCPTool
    begin
      Result := TMSSQLTool.Create;
    end);
  WriteLn(ErrOutput, '[MCPService]   + mcp-mssql');
end;

end.
