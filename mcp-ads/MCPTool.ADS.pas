unit MCPTool.ADS;

{
  MCPTool.ADS  ·  mcp-ads
  Advantage Database Server (ADS) via FireDAC native driver.
  Supports ADS 12+ (server and local/embedded modes).
  Requires Advantage Client Engine (ace64.dll) or ADS Local Server.
}

interface

uses
  uMakerAi.MCPServer.Core,
  System.SysUtils,
  MCPTool.FDBase,
  FireDAC.Phys.ADS,
  FireDAC.Comp.Client;

type
  TADSTool = class(TFDBaseTool)
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

{ TADSTool }

function TADSTool.GetDefaultPort: Integer;
begin
  Result := 6262;
end;

function TADSTool.GetListTablesSQL(const DB, Schema: string): string;
begin
  // ADS system catalog via stored procedure
  Result := 'EXECUTE PROCEDURE sp_GetTables('''', '''', '''', ''TABLE'')';
end;

function TADSTool.GetDescribeSQL(const Table, DB, Schema: string): string;
begin
  // ADS column info via stored procedure
  Result := Format(
    'EXECUTE PROCEDURE sp_GetColumns(''%s'', '''', '''', '''')',
    [Table]);
end;

function TADSTool.GetListDatabasesSQL: string;
begin
  // ADS is path/dictionary-based — list available tables as the "database" view
  Result := 'EXECUTE PROCEDURE sp_GetTables('''', '''', '''', ''TABLE'')';
end;

procedure TADSTool.ConfigureConnection(Conn: TFDConnection;
  const P: TFDParams);
begin
  // ADS FireDAC params:
  //   ServerType: ADS_REMOTE_SERVER (network), ADS_LOCAL_SERVER (local), ADS_AIS_SERVER
  //   TableType:  ADT (Advantage), DBF (dBASE-compatible), VFP (Visual FoxPro)
  // Default to remote server if host is provided, local otherwise.
  if Trim(P.Host) = '' then
    Conn.Params.Add('ServerType=ADS_LOCAL_SERVER')
  else
    Conn.Params.Add('ServerType=ADS_REMOTE_SERVER');
  Conn.Params.Add('TableType=ADT');
end;

constructor TADSTool.Create;
begin
  inherited;
  FDriverID    := 'ADS';
  FName        := 'mcp-ads';
  FDescription :=
    'Advantage Database Server (ADS) access via FireDAC native driver. ' +
    'Operations: query (SELECT → JSON rows), execute (INSERT/UPDATE/DELETE/DDL → rowsAffected), ' +
    'execute_tx (JSON array of SQL in one transaction), ' +
    'list_tables (via sp_GetTables), describe (via sp_GetColumns), ' +
    'list_databases (same as list_tables in ADS). ' +
    'Required param: database (path to ADS data dictionary .add file or directory). ' +
    'Optional: host (ADS server IP for remote mode; omit for local/embedded mode), ' +
    'port (default 6262), username, password, ' +
    'maxRows (default 100), timeout (default 30s). ' +
    'Requires Advantage Client Engine (ace64.dll).';
end;

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-ads',
    function: IAiMCPTool
    begin
      Result := TADSTool.Create;
    end);
  WriteLn(ErrOutput, '[MCPService]   + mcp-ads');
end;

end.
