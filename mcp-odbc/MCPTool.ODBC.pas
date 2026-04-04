// Nombre: Gustavo Enríquez
// Redes Sociales:
// - Email: gustavoeenriquez@gmail.com

// - Telegram: https://t.me/MakerAi_Suite_Delphi
// - Telegram: https://t.me/MakerAi_Delphi_Suite_English

// - LinkedIn: https://www.linkedin.com/in/gustavo-enriquez-3937654a/
// - Youtube: https://www.youtube.com/@cimamaker3945
// - GitHub: https://github.com/gustavoeenriquez/

unit MCPTool.ODBC;

{
  MCPTool.ODBC  ·  mcp-odbc
  Generic ODBC access via FireDAC ODBC driver.
  Connects to any database that has an ODBC driver installed:
  Snowflake, IBM DB2, Teradata, SAP HANA, Access, Excel, etc.
}

interface

uses
  uMakerAi.MCPServer.Core,
  System.SysUtils,
  MCPTool.FDBase,
  FireDAC.Phys.ODBC,
  FireDAC.Comp.Client;

type
  TODBCTool = class(TFDBaseTool)
  protected
    function GetDefaultPort: Integer; override;
    function GetListTablesSQL(const DB, Schema: string): string; override;
    function GetDescribeSQL(const Table, DB, Schema: string): string; override;
    function GetListDatabasesSQL: string; override;
  public
    constructor Create; override;
  end;

procedure RegisterTools(AServer: TAiMCPServer);

implementation

{ TODBCTool }

function TODBCTool.GetDefaultPort: Integer;
begin
  Result := 0; // Varies by driver
end;

function TODBCTool.GetListTablesSQL(const DB, Schema: string): string;
begin
  // Generic INFORMATION_SCHEMA — works for most ODBC sources
  if Trim(Schema) <> '' then
    Result := 'SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES ' +
              'WHERE TABLE_SCHEMA = ''' + Schema + ''' ORDER BY TABLE_NAME'
  else
    Result := 'SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES ORDER BY TABLE_NAME';
end;

function TODBCTool.GetDescribeSQL(const Table, DB, Schema: string): string;
begin
  if Trim(Schema) <> '' then
    Result := Format(
      'SELECT COLUMN_NAME, DATA_TYPE, IS_NULLABLE, COLUMN_DEFAULT ' +
      'FROM INFORMATION_SCHEMA.COLUMNS ' +
      'WHERE TABLE_NAME = ''%s'' AND TABLE_SCHEMA = ''%s'' ' +
      'ORDER BY ORDINAL_POSITION', [Table, Schema])
  else
    Result := Format(
      'SELECT COLUMN_NAME, DATA_TYPE, IS_NULLABLE, COLUMN_DEFAULT ' +
      'FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = ''%s'' ' +
      'ORDER BY ORDINAL_POSITION', [Table]);
end;

function TODBCTool.GetListDatabasesSQL: string;
begin
  Result := '';
end;

constructor TODBCTool.Create;
begin
  inherited;
  FDriverID    := 'ODBC';
  FName        := 'mcp-odbc';
  FDescription :=
    'Generic ODBC database access via FireDAC — connects to any DB with an ODBC driver. ' +
    'Supported: Snowflake, IBM DB2, SAP HANA, Teradata, MS Access, Excel, and more. ' +
    'Operations: query, execute, execute_tx, list_tables, describe, list_databases. ' +
    'Connection options: ' +
    '(1) DSN: use dsn param with a configured System/User DSN name. ' +
    '(2) Driver: use odbcDriver (e.g. "{Snowflake ODBC Driver}") + host + database + username + password. ' +
    'Optional: schema for list_tables/describe, maxRows, timeout.';
end;

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-odbc',
    function: IAiMCPTool
    begin
      Result := TODBCTool.Create;
    end);
  WriteLn(ErrOutput, '[MCPService]   + mcp-odbc');
end;

end.
