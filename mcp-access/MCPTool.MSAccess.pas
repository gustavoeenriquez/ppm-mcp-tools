unit MCPTool.MSAccess;

{
  MCPTool.MSAccess  ·  mcp-access
  Microsoft Access (.accdb / .mdb) via FireDAC native driver (DAO/Jet).
  Requires Microsoft Access Database Engine 2016+ Redistributable (64-bit).
  Note: no host/port — database is the full file path to the .accdb or .mdb file.
}

interface

uses
  uMakerAi.MCPServer.Core,
  System.SysUtils,
  MCPTool.FDBase,
  FireDAC.Phys.MSAcc,
  FireDAC.Comp.Client;

type
  TMSAccessTool = class(TFDBaseTool)
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

{ TMSAccessTool }

function TMSAccessTool.GetDefaultPort: Integer;
begin
  Result := 0;   // file-based, no port
end;

function TMSAccessTool.GetListTablesSQL(const DB, Schema: string): string;
begin
  // MSysObjects: Type=1 are local tables; Flags=0 excludes system/hidden tables
  Result :=
    'SELECT Name AS TABLE_NAME FROM MSysObjects ' +
    'WHERE Type = 1 AND Flags = 0 ' +
    'ORDER BY Name';
end;

function TMSAccessTool.GetDescribeSQL(const Table, DB, Schema: string): string;
begin
  // Access has no INFORMATION_SCHEMA; use a pragma-style SELECT that
  // returns at least column names via an empty resultset.
  // FireDAC will expose field metadata from the cursor even with 0 rows.
  Result := Format('SELECT * FROM [%s] WHERE 1=0', [Table]);
end;

function TMSAccessTool.GetListDatabasesSQL: string;
begin
  // Access is file-based — "databases" = tables in current file.
  // Return the same table list as list_tables.
  Result :=
    'SELECT Name AS TABLE_NAME FROM MSysObjects ' +
    'WHERE Type = 1 AND Flags = 0 ' +
    'ORDER BY Name';
end;

procedure TMSAccessTool.ConfigureConnection(Conn: TFDConnection;
  const P: TFDParams);
begin
  // For Access, FireDAC.Phys.MSAcc uses Database param as the file path.
  // Host and Port are ignored. Password is the database password if set.
  // No charset setting needed — Access handles encoding internally.
  if Trim(P.Password) <> '' then
    Conn.Params.Add('Password=' + Trim(P.Password));
end;

constructor TMSAccessTool.Create;
begin
  inherited;
  FDriverID    := 'MSAcc';
  FName        := 'mcp-access';
  FDescription :=
    'Microsoft Access (.accdb/.mdb) via FireDAC DAO driver. ' +
    'Operations: query (SELECT → JSON rows), execute (INSERT/UPDATE/DELETE/DDL), ' +
    'execute_tx (JSON array of SQL in one transaction), ' +
    'list_tables, describe (returns column names from empty SELECT), ' +
    'list_databases (same as list_tables for Access). ' +
    'Required param: database (full path to .accdb or .mdb file, e.g. C:\data\sales.accdb). ' +
    'Optional: password (if DB is password-protected), maxRows (default 100), timeout (default 30s). ' +
    'Requires Microsoft Access Database Engine 2016+ Redistributable 64-bit.';
end;

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-access',
    function: IAiMCPTool
    begin
      Result := TMSAccessTool.Create;
    end);
  WriteLn(ErrOutput, '[MCPService]   + mcp-access');
end;

end.
