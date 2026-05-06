unit MCPTool.Informix;

{
  MCPTool.Informix  ·  mcp-informix
  IBM Informix via FireDAC native driver.
  Supports Informix 12.10+ and HCL Informix 14+.
  Requires IBM Informix Client SDK (ifcli.dll / ifgls09b.dll).
}

interface

uses
  uMakerAi.MCPServer.Core,
  System.SysUtils,
  MCPTool.FDBase,
  FireDAC.Phys.Infx,
  FireDAC.Comp.Client;

type
  TInformixTool = class(TFDBaseTool)
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

{ TInformixTool }

function TInformixTool.GetDefaultPort: Integer;
begin
  Result := 9088;
end;

function TInformixTool.GetListTablesSQL(const DB, Schema: string): string;
begin
  // systables: tabtype='T' = user tables; tabid > 99 skips system catalog tables
  // Informix has no schema concept in classic mode — owner = username
  if Trim(Schema) <> '' then
    Result :=
      'SELECT tabname, owner FROM systables ' +
      'WHERE tabtype = ''T'' AND owner = ''' + LowerCase(Trim(Schema)) + ''' ' +
      'ORDER BY tabname'
  else
    Result :=
      'SELECT tabname, owner FROM systables ' +
      'WHERE tabtype = ''T'' AND tabid > 99 ' +
      'ORDER BY tabname';
end;

function TInformixTool.GetDescribeSQL(const Table, DB, Schema: string): string;
begin
  // syscolumns joined with systables for column metadata
  Result := Format(
    'SELECT c.colname, c.coltype, c.collength, c.colno ' +
    'FROM syscolumns c ' +
    'JOIN systables t ON c.tabid = t.tabid ' +
    'WHERE t.tabname = ''%s'' ' +
    'ORDER BY c.colno',
    [LowerCase(Table)]);
end;

function TInformixTool.GetListDatabasesSQL: string;
begin
  // From sysmaster: lists all databases on this Informix instance
  Result :=
    'SELECT name FROM sysmaster:sysdatabases ORDER BY name';
end;

procedure TInformixTool.ConfigureConnection(Conn: TFDConnection;
  const P: TFDParams);
begin
  // Informix requires INFORMIXSERVER env var or explicit server name.
  // FireDAC maps: Server=host, Port=port, Database=dbname
  // Additional params: ServerName (Informix server alias, if different from host)
end;

constructor TInformixTool.Create;
begin
  inherited;
  FDriverID    := 'Infx';
  FName        := 'mcp-informix';
  FDescription :=
    'IBM Informix database access via FireDAC native driver. ' +
    'Operations: query (SELECT → JSON rows), execute (INSERT/UPDATE/DELETE/DDL → rowsAffected), ' +
    'execute_tx (JSON array of SQL in one transaction), ' +
    'list_tables (params: schema/owner?), describe (params: table), ' +
    'list_databases (queries sysmaster). ' +
    'Required params: host, database, username. ' +
    'Optional: port (default 9088), password, maxRows (default 100), timeout (default 30s). ' +
    'Requires IBM Informix Client SDK (ifcli.dll).';
end;

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-informix',
    function: IAiMCPTool
    begin
      Result := TInformixTool.Create;
    end);
  WriteLn(ErrOutput, '[MCPService]   + mcp-informix');
end;

end.
