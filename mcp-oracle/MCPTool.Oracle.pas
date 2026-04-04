unit MCPTool.Oracle;

{
  MCPTool.Oracle  ·  mcp-oracle
  Oracle Database via FireDAC native driver.
  Supports Oracle 11g+ and Oracle Cloud.
  Connection: host:port/servicename (Easy Connect) or TNS alias.
}

interface

uses
  uMakerAi.MCPServer.Core,
  System.SysUtils,
  MCPTool.FDBase,
  FireDAC.Phys.Oracle,
  FireDAC.Comp.Client;

type
  TOracleTool = class(TFDBaseTool)
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

{ TOracleTool }

function TOracleTool.GetDefaultPort: Integer;
begin
  Result := 1521;
end;

function TOracleTool.GetListTablesSQL(const DB, Schema: string): string;
begin
  if Trim(Schema) <> '' then
    Result := Format(
      'SELECT TABLE_NAME FROM ALL_TABLES WHERE OWNER = ''%s'' ORDER BY TABLE_NAME',
      [UpperCase(Schema)])
  else
    Result := 'SELECT TABLE_NAME FROM USER_TABLES ORDER BY TABLE_NAME';
end;

function TOracleTool.GetDescribeSQL(const Table, DB, Schema: string): string;
begin
  if Trim(Schema) <> '' then
    Result := Format(
      'SELECT COLUMN_NAME, DATA_TYPE, DATA_LENGTH, DATA_PRECISION, DATA_SCALE, ' +
      'NULLABLE, DATA_DEFAULT ' +
      'FROM ALL_TAB_COLUMNS WHERE OWNER = ''%s'' AND TABLE_NAME = ''%s'' ' +
      'ORDER BY COLUMN_ID',
      [UpperCase(Schema), UpperCase(Table)])
  else
    Result := Format(
      'SELECT COLUMN_NAME, DATA_TYPE, DATA_LENGTH, DATA_PRECISION, DATA_SCALE, ' +
      'NULLABLE, DATA_DEFAULT ' +
      'FROM USER_TAB_COLUMNS WHERE TABLE_NAME = ''%s'' ORDER BY COLUMN_ID',
      [UpperCase(Table)]);
end;

function TOracleTool.GetListDatabasesSQL: string;
begin
  // Return schemas (users) visible to current user
  Result := 'SELECT USERNAME FROM ALL_USERS ORDER BY USERNAME';
end;

procedure TOracleTool.ConfigureConnection(Conn: TFDConnection;
  const P: TFDParams);
begin
  // Oracle Easy Connect: host:port/servicename
  // Database field = service name; host+port set separately
  // Nothing extra needed — FireDAC handles EZConnect automatically
end;

constructor TOracleTool.Create;
begin
  inherited;
  FDriverID    := 'Oracle';
  FName        := 'mcp-oracle';
  FDescription :=
    'Oracle Database 11g+ via FireDAC native driver (requires Oracle Client). ' +
    'Operations: query, execute, execute_tx, list_tables (params: schema?), ' +
    'describe (params: table, schema?), list_databases (lists schemas/users). ' +
    'Connection: host + port (default 1521) + database (service name). ' +
    'Use schema to query another user''s objects. ' +
    'Requires Oracle Instant Client installed on the server.';
end;

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-oracle',
    function: IAiMCPTool
    begin
      Result := TOracleTool.Create;
    end);
  WriteLn(ErrOutput, '[MCPService]   + mcp-oracle');
end;

end.
