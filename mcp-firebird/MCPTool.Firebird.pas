// Nombre: Gustavo Enríquez
// Redes Sociales:
// - Email: gustavoeenriquez@gmail.com

// - Telegram: https://t.me/MakerAi_Suite_Delphi
// - Telegram: https://t.me/MakerAi_Delphi_Suite_English

// - LinkedIn: https://www.linkedin.com/in/gustavo-enriquez-3937654a/
// - Youtube: https://www.youtube.com/@cimamaker3945
// - GitHub: https://github.com/gustavoeenriquez/

unit MCPTool.Firebird;

{
  MCPTool.Firebird  ·  mcp-firebird
  Firebird and InterBase via FireDAC native driver.
  Supports Firebird 2.5+, 3.0, 4.0 and InterBase 2020+.
}

interface

uses
  uMakerAi.MCPServer.Core,
  System.SysUtils,
  MCPTool.FDBase,
  FireDAC.Phys.IB,
  FireDAC.Comp.Client;

type
  TFirebirdTool = class(TFDBaseTool)
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

{ TFirebirdTool }

function TFirebirdTool.GetDefaultPort: Integer;
begin
  Result := 3050;
end;

function TFirebirdTool.GetListTablesSQL(const DB, Schema: string): string;
begin
  // Schema not used in Firebird — single namespace per DB
  Result :=
    'SELECT TRIM(RDB$RELATION_NAME) AS TABLE_NAME ' +
    'FROM RDB$RELATIONS ' +
    'WHERE RDB$SYSTEM_FLAG = 0 AND RDB$VIEW_SOURCE IS NULL ' +
    'ORDER BY RDB$RELATION_NAME';
end;

function TFirebirdTool.GetDescribeSQL(const Table, DB, Schema: string): string;
begin
  Result := Format(
    'SELECT TRIM(r.RDB$FIELD_NAME) AS COLUMN_NAME, ' +
    'CASE f.RDB$FIELD_TYPE ' +
    '  WHEN 7  THEN ''SMALLINT'' ' +
    '  WHEN 8  THEN ''INTEGER'' ' +
    '  WHEN 10 THEN ''FLOAT'' ' +
    '  WHEN 12 THEN ''DATE'' ' +
    '  WHEN 13 THEN ''TIME'' ' +
    '  WHEN 14 THEN ''CHAR'' ' +
    '  WHEN 16 THEN ''BIGINT'' ' +
    '  WHEN 27 THEN ''DOUBLE'' ' +
    '  WHEN 35 THEN ''TIMESTAMP'' ' +
    '  WHEN 37 THEN ''VARCHAR'' ' +
    '  WHEN 261 THEN ''BLOB'' ' +
    '  ELSE ''UNKNOWN'' END AS DATA_TYPE, ' +
    'f.RDB$FIELD_LENGTH AS FIELD_LENGTH, ' +
    'IIF(r.RDB$NULL_FLAG = 1, ''NO'', ''YES'') AS IS_NULLABLE, ' +
    'r.RDB$DEFAULT_SOURCE AS COLUMN_DEFAULT ' +
    'FROM RDB$RELATION_FIELDS r ' +
    'JOIN RDB$FIELDS f ON f.RDB$FIELD_NAME = r.RDB$FIELD_SOURCE ' +
    'WHERE TRIM(r.RDB$RELATION_NAME) = ''%s'' ' +
    'ORDER BY r.RDB$FIELD_POSITION',
    [UpperCase(Table)]);
end;

function TFirebirdTool.GetListDatabasesSQL: string;
begin
  Result := ''; // Single database per connection in Firebird
end;

procedure TFirebirdTool.ConfigureConnection(Conn: TFDConnection;
  const P: TFDParams);
begin
  Conn.Params.Add('Protocol=TCPIP');
  // SQLDialect 3 is standard for Firebird 1.5+
  Conn.Params.Add('SQLDialect=3');
end;

constructor TFirebirdTool.Create;
begin
  inherited;
  FDriverID    := 'IB';
  FName        := 'mcp-firebird';
  FDescription :=
    'Firebird 2.5/3.0/4.0 and InterBase via FireDAC native driver. ' +
    'Operations: query, execute, execute_tx, list_tables, describe (params: table), ' +
    'list_databases (not applicable — single DB per connection). ' +
    'Connection: host + port (default 3050) + database (full path on server, ' +
    'e.g. /var/db/mydb.fdb or C:\data\mydb.fdb) + username + password. ' +
    'Requires Firebird client library on the server.';
end;

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-firebird',
    function: IAiMCPTool
    begin
      Result := TFirebirdTool.Create;
    end);
  WriteLn(ErrOutput, '[MCPService]   + mcp-firebird');
end;

end.
