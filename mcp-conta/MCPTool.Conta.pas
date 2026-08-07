unit MCPTool.Conta;

{
  MCPTool.Conta  -  shared by mcp-conta (full) and mcp-conta-query (read-only)

  Exposes the PascalAI accounting server (ConServer, Colombia) as ~25 MCP
  tools, one per domain module (comprobantes, reportes, nomina, ventas, ...).

  Every tool has the same shape:
    operation  - method name from the module catalog (see tool description)
    params     - JSON object with the method parameters
    login/nit/password - optional per-call credential override

  operation:"help" returns the full catalog of the module: every operation
  with its documentation (including expected params) and write flag.

  The read-only variant (mcp-conta-query) hides and rejects write operations
  client-side, so it is safe for autonomous agents.

  Auth is automatic via CONTA_URL / CONTA_LOGIN / CONTA_NIT / CONTA_PASSWORD
  (see MCPTool.ContaClient).

  Author: Gustavo Enriquez  -  PascalAI
}

interface

uses
  uMakerAi.MCPServer.Core,
  System.JSON,
  MCPTool.Conta.Catalog;

type
  TContaParams = class
  private
    FOperation: string;
    FParams:    string;
    FLogin:     string;
    FNit:       string;
    FPassword:  string;
  public
    [AiMCPSchemaDescription('Operation to execute (see the list in the tool ' +
      'description). Use "help" to get every operation of this module with ' +
      'its documentation and expected params.')]
    property Operation: string read FOperation write FOperation;

    [AiMCPOptional]
    [AiMCPSchemaDescription('JSON object with the parameters of the operation, ' +
      'e.g. {"fecha_desde":"2026-01-01","fecha_hasta":"2026-01-31"}. ' +
      'Omit for operations without parameters. Use operation:"help" to see ' +
      'the params of each operation.')]
    property Params: string read FParams write FParams;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Omit to use the server-configured CONTA_LOGIN. ' +
      'Never ask the user for credentials.')]
    property Login: string read FLogin write FLogin;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Omit to use the server-configured CONTA_NIT ' +
      '(company / tenant). Only pass it to work on a different company. ' +
      'Never ask the user for credentials.')]
    property Nit: string read FNit write FNit;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Omit to use the server-configured CONTA_PASSWORD. ' +
      'Never ask the user for credentials.')]
    property Password: string read FPassword write FPassword;
  end;

  TContaModuleTool = class(TAiMCPToolBase<TContaParams>)
  private
    FModule:   TContaModuleDef;
    FReadOnly: Boolean;
    function HelpResult: TJSONObject;
  protected
    function ExecuteWithParams(const AParams: TContaParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor CreateForModule(const AModule: TContaModuleDef;
      AReadOnly: Boolean);
  end;

// Registers one tool per catalog module. AReadOnly = query variant.
procedure RegisterTools(AServer: TAiMCPServer; AReadOnly: Boolean);

implementation

uses
  System.SysUtils,
  MCPTool.ContaClient;

// ---------------------------------------------------------------------------
// TContaModuleTool
// ---------------------------------------------------------------------------

constructor TContaModuleTool.CreateForModule(const AModule: TContaModuleDef;
  AReadOnly: Boolean);
var
  Ops: string;
  i: Integer;
begin
  inherited Create;
  FModule   := AModule;
  FReadOnly := AReadOnly;
  FName     := AModule.Tool;

  Ops := '';
  for i := 0 to High(AModule.Methods) do
  begin
    if FReadOnly and AModule.Methods[i].IsWrite then
      Continue;
    if Ops <> '' then
      Ops := Ops + ', ';
    Ops := Ops + AModule.Methods[i].Name;
    if AModule.Methods[i].IsWrite then
      Ops := Ops + '*';
  end;

  FDescription := AModule.Title + ' - ' + AModule.Desc +
    '. Operations: help, ' + Ops + '.';
  if FReadOnly then
    FDescription := FDescription +
      ' READ-ONLY server: write operations are not available here ' +
      '(use mcp-conta for those).'
  else
    FDescription := FDescription +
      ' Operations marked * modify data.';
  FDescription := FDescription +
    ' Call operation:"help" first to see the documentation and params of ' +
    'each operation.';
end;

function TContaModuleTool.HelpResult: TJSONObject;
var
  Arr: TJSONArray;
  Obj, Root: TJSONObject;
  i: Integer;
begin
  Root := TJSONObject.Create;
  Root.AddPair('tool', FModule.Tool);
  Root.AddPair('title', FModule.Title);
  Root.AddPair('descripcion', FModule.Desc);
  if FReadOnly then
    Root.AddPair('modo', 'read-only (las operaciones de escritura estan ocultas)');
  Arr := TJSONArray.Create;
  for i := 0 to High(FModule.Methods) do
  begin
    if FReadOnly and FModule.Methods[i].IsWrite then
      Continue;
    Obj := TJSONObject.Create;
    Obj.AddPair('operation', FModule.Methods[i].Name);
    Obj.AddPair('doc', FModule.Methods[i].Doc);
    Obj.AddPair('write', TJSONBool.Create(FModule.Methods[i].IsWrite));
    Arr.AddElement(Obj);
  end;
  Root.AddPair('operations', Arr);
  Result := TAiMCPResponseBuilder.New.AddText(Root.ToJSON).Build;
  Root.Free;
end;

function TContaModuleTool.ExecuteWithParams(const AParams: TContaParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op, PJson: string;
  i, Found: Integer;
  R: TJSONValue;
begin
  R := nil;
  try
    Op := Trim(AParams.Operation);
    if Op.StartsWith('CON_', True) then
      Op := Copy(Op, 5, MaxInt);

    if (Op = '') or SameText(Op, 'help') then
      Exit(HelpResult);

    Found := -1;
    for i := 0 to High(FModule.Methods) do
      if SameText(FModule.Methods[i].Name, Op) then
      begin
        Found := i;
        Break;
      end;

    if Found < 0 then
      raise EContaError.CreateFmt(
        'Operacion desconocida "%s" en %s. Use operation:"help" para ver la lista.',
        [Op, FModule.Tool]);

    if FReadOnly and FModule.Methods[Found].IsWrite then
      raise EContaError.CreateFmt(
        '"%s" modifica datos y este servidor es de solo lectura. ' +
        'Use mcp-conta (full) para operaciones de escritura.',
        [FModule.Methods[Found].Name]);

    PJson := Trim(AParams.Params);
    if PJson <> '' then
    begin
      R := TJSONObject.ParseJSONValue(PJson);
      if R = nil then
        raise EContaError.Create('"params" no es JSON valido');
      FreeAndNil(R);
    end;

    R := ContaCall('CON_' + FModule.Methods[Found].Name, PJson,
      Trim(AParams.Login), Trim(AParams.Nit), AParams.Password);

    Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
    FreeAndNil(R);
  except
    on E: Exception do
    begin
      if Assigned(R) then
        R.Free;
      Result := TAiMCPResponseBuilder.New
        .AddText('{"ok":false,"error":"' +
          E.Message.Replace('\', '\\').Replace('"', '\"')
                   .Replace(#10, '\n').Replace(#13, '') + '"}')
        .Build;
    end;
  end;
end;

// ---------------------------------------------------------------------------
// Registration
// ---------------------------------------------------------------------------

// Separate function so each closure captures its own copy of the module def
// (capturing a for-loop variable directly would alias every factory to the
// last module).
function MakeFactory(const AModule: TContaModuleDef;
  AReadOnly: Boolean): TAiMCPToolFactory;
begin
  Result :=
    function: IAiMCPTool
    begin
      Result := TContaModuleTool.CreateForModule(AModule, AReadOnly);
    end;
end;

procedure RegisterTools(AServer: TAiMCPServer; AReadOnly: Boolean);
var
  Modules: TArray<TContaModuleDef>;
  i: Integer;
begin
  Modules := ContaModules;
  for i := 0 to High(Modules) do
  begin
    AServer.RegisterTool(Modules[i].Tool, MakeFactory(Modules[i], AReadOnly));
    WriteLn(ErrOutput, '[MCPService]   + ' + Modules[i].Tool +
      ' (' + IntToStr(Length(Modules[i].Methods)) + ' ops)');
  end;
end;

end.
