unit MCPTool.Siag;

{
  MCPTool.Siag  -  mcp-siag  (port 8770)

  FULL access to a SIAG analytics server: run any DSL (read AND write) and
  manage configuration (categories, variables, indicators, library).

  Write DSL (CREATE/ALTER/DROP/LOAD/DEFINE) requires the authenticated user to
  have rol=admin - the server enforces this and returns an error otherwise.
  For a safe read-only surface, use mcp-siag-query instead.

  Auth is automatic via SIAG_EMAIL / SIAG_PASSWORD / SIAG_TENANT (see
  MCPTool.SiagClient). Any operation may override the credentials per-call by
  passing email + password + tenant.

  Operations:
    health                     - server health check
    login                      - log in and return a JWT token
    get_me                     - profile of the authenticated user
    execute_dsl                - run any DSL statement(s)              (dsl)

    get_categorias             - list config categories               (tenantId?)
    save_categoria             - create/update a category   (id?, nombre, tenantId?)
    delete_categoria           - delete a category          (id, tenantId?)

    get_variables              - list variables                       (tenantId?)
    save_variable              - create/update a variable   (data, tenantId?)
    delete_variable            - delete a variable          (id, tenantId?)

    get_indicadores            - list indicators                      (tenantId?)
    save_indicador             - create/update an indicator (data, tenantId?)
    delete_indicador           - delete an indicator        (id, tenantId?)

    get_biblioteca_categorias  - library: categories
    get_biblioteca_indicadores - library: indicators of a category    (catId)

  When tenantId is omitted for config operations it is resolved from the token
  via get_me.

  Author: Gustavo Enriquez  -  PascalAI
}

interface

uses
  uMakerAi.MCPServer.Core,
  System.JSON;

type
  TSiagParams = class
  private
    FOperation: string;
    FDsl:       string;
    FEmail:     string;
    FPassword:  string;
    FTenant:    string;
    FTenantId:  string;
    FId:        string;
    FNombre:    string;
    FData:      string;
    FCatId:     string;
  public
    [AiMCPSchemaDescription('Operation: health, login, get_me, execute_dsl, ' +
      'get_categorias, save_categoria, delete_categoria, ' +
      'get_variables, save_variable, delete_variable, ' +
      'get_indicadores, save_indicador, delete_indicador, ' +
      'get_biblioteca_categorias, get_biblioteca_indicadores')]
    property Operation: string read FOperation write FOperation;

    [AiMCPOptional]
    [AiMCPSchemaDescription('SIAG DSL statement(s) for execute_dsl. Read: QUERY, DRILL, ' +
      'NAVIGATE, INSPECT. Write (needs rol=admin): CREATE/ALTER/DROP TABLE, ' +
      'LOAD DIMENSION, LOAD DATA, DEFINE INDICATOR. Multiple statements may be ' +
      'separated by newlines. Example: "DEFINE INDICATOR roi FORMULA: utilidad / ventas UNIT: %".')]
    property Dsl: string read FDsl write FDsl;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Override credentials: user email (else uses SIAG_EMAIL)')]
    property Email: string read FEmail write FEmail;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Override credentials: password (else uses SIAG_PASSWORD)')]
    property Password: string read FPassword write FPassword;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Override credentials: tenant slug / empresa (else uses SIAG_TENANT)')]
    property Tenant: string read FTenant write FTenant;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Tenant id for config operations. If omitted, resolved from the token.')]
    property TenantId: string read FTenantId write FTenantId;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Record id (for save/delete of categoria/variable/indicador; ' +
      'empty on save = create new)')]
    property Id: string read FId write FId;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Category name (for save_categoria)')]
    property Nombre: string read FNombre write FNombre;

    [AiMCPOptional]
    [AiMCPSchemaDescription('JSON object payload for save_variable / save_indicador. ' +
      'Example: {"id":"","nombre":"Ventas","unidad":"MXN"}')]
    property Data: string read FData write FData;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Category id for get_biblioteca_indicadores')]
    property CatId: string read FCatId write FCatId;
  end;

  TSiagTool = class(TAiMCPToolBase<TSiagParams>)
  protected
    function ExecuteWithParams(const AParams: TSiagParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

procedure RegisterTools(AServer: TAiMCPServer);

implementation

uses
  System.SysUtils,
  MCPTool.SiagClient;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

// Reads a JSON field as string regardless of the underlying type.
function JStr(Obj: TJSONObject; const AName: string): string;
var
  V: TJSONValue;
begin
  Result := '';
  if Obj = nil then Exit;
  V := Obj.FindValue(AName);
  if V <> nil then
    Result := V.Value;
end;

// Token for this call: explicit creds override, else the cached env login.
function TokenFor(const P: TSiagParams): string;
begin
  if (Trim(P.Email) <> '') and (P.Password <> '') and (Trim(P.Tenant) <> '') then
    Result := SiagLogin(Trim(P.Email), P.Password, Trim(P.Tenant))
  else
    Result := SiagEnsureToken;
end;

// Returns TenantId param, or resolves it from get_me when empty.
function ResolveTenantId(const AToken, AProvided: string): string;
var
  Me: TJSONObject;
begin
  if Trim(AProvided) <> '' then
    Exit(Trim(AProvided));
  Me := SiagGetMe(AToken);
  try
    Result := JStr(Me, 'tenantId');
    if Result = '' then
      raise ESiagError.Create('Could not resolve tenantId from token; pass "tenantId".');
  finally
    Me.Free;
  end;
end;

function ParseDataObject(const AData: string): TJSONValue;
begin
  if Trim(AData) = '' then
    raise ESiagError.Create('"data" (a JSON object) is required for this operation');
  Result := TJSONObject.ParseJSONValue(AData);
  if Result = nil then
    raise ESiagError.Create('"data" is not valid JSON');
end;

function StrArr(const AItems: array of string): TJSONArray;
var
  i: Integer;
begin
  Result := TJSONArray.Create;
  for i := 0 to High(AItems) do
    Result.Add(AItems[i]);
end;

// ---------------------------------------------------------------------------
// Tool
// ---------------------------------------------------------------------------

function TSiagTool.ExecuteWithParams(const AParams: TSiagParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op, Token, Tid, ErrMsg: string;
  R: TJSONValue;
  Arr: TJSONArray;

  function RequireDsl: string;
  begin
    Result := AParams.Dsl;
    if Trim(Result) = '' then
      raise ESiagError.Create('"dsl" is required for execute_dsl');
  end;

  function RequireId: string;
  begin
    Result := Trim(AParams.Id);
    if Result = '' then
      raise ESiagError.CreateFmt('"id" is required for operation "%s"', [Op]);
  end;

begin
  R := nil;
  try
    Op := LowerCase(Trim(AParams.Operation));
    if Op = '' then
      raise ESiagError.Create('"operation" is required');

    if Op = 'health' then
      R := SiagHealth

    else if Op = 'login' then
    begin
      Token := TokenFor(AParams);
      R := TJSONObject.Create;
      TJSONObject(R).AddPair('token', TJSONString.Create(Token));
    end

    else if Op = 'get_me' then
      R := SiagGetMe(TokenFor(AParams))

    else if Op = 'execute_dsl' then
      R := SiagExecuteDSL(TokenFor(AParams), RequireDsl)

    // ---- Categorias ----
    else if Op = 'get_categorias' then
    begin
      Token := TokenFor(AParams);
      Tid := ResolveTenantId(Token, AParams.TenantId);
      R := SiagDsGet('GetCategorias', [Tid, Token]);
    end
    else if Op = 'save_categoria' then
    begin
      if Trim(AParams.Nombre) = '' then
        raise ESiagError.Create('"nombre" is required for save_categoria');
      Token := TokenFor(AParams);
      Tid := ResolveTenantId(Token, AParams.TenantId);
      R := SiagDsPost('SaveCategoria',
        StrArr([Tid, Trim(AParams.Id), Trim(AParams.Nombre), Token]));
    end
    else if Op = 'delete_categoria' then
    begin
      Token := TokenFor(AParams);
      Tid := ResolveTenantId(Token, AParams.TenantId);
      R := SiagDsPost('DeleteCategoria', StrArr([Tid, RequireId, Token]));
    end

    // ---- Variables ----
    else if Op = 'get_variables' then
    begin
      Token := TokenFor(AParams);
      Tid := ResolveTenantId(Token, AParams.TenantId);
      R := SiagDsGet('GetVariables', [Tid, Token]);
    end
    else if Op = 'save_variable' then
    begin
      Token := TokenFor(AParams);
      Tid := ResolveTenantId(Token, AParams.TenantId);
      Arr := TJSONArray.Create;
      Arr.Add(Tid);
      Arr.Add(Token);
      Arr.AddElement(ParseDataObject(AParams.Data));
      R := SiagDsPost('SaveVariable', Arr);
    end
    else if Op = 'delete_variable' then
    begin
      Token := TokenFor(AParams);
      Tid := ResolveTenantId(Token, AParams.TenantId);
      R := SiagDsPost('DeleteVariable', StrArr([Tid, RequireId, Token]));
    end

    // ---- Indicadores ----
    else if Op = 'get_indicadores' then
    begin
      Token := TokenFor(AParams);
      Tid := ResolveTenantId(Token, AParams.TenantId);
      R := SiagDsGet('GetIndicadores', [Tid, Token]);
    end
    else if Op = 'save_indicador' then
    begin
      Token := TokenFor(AParams);
      Tid := ResolveTenantId(Token, AParams.TenantId);
      Arr := TJSONArray.Create;
      Arr.Add(Tid);
      Arr.Add(Token);
      Arr.AddElement(ParseDataObject(AParams.Data));
      R := SiagDsPost('SaveIndicador', Arr);
    end
    else if Op = 'delete_indicador' then
    begin
      Token := TokenFor(AParams);
      Tid := ResolveTenantId(Token, AParams.TenantId);
      R := SiagDsPost('DeleteIndicador', StrArr([Tid, RequireId, Token]));
    end

    // ---- Biblioteca ----
    else if Op = 'get_biblioteca_categorias' then
      R := SiagDsGet('GetBibliotecaCategorias', [])
    else if Op = 'get_biblioteca_indicadores' then
    begin
      if Trim(AParams.CatId) = '' then
        raise ESiagError.Create('"catId" is required for get_biblioteca_indicadores');
      R := SiagDsGet('GetBibliotecaIndicadores', [Trim(AParams.CatId)]);
    end

    else
      raise ESiagError.CreateFmt('Unknown operation "%s"', [Op]);

    // Surface a server-side {"error": "..."} as a tool error too.
    if (R is TJSONObject) and TJSONObject(R).TryGetValue<string>('error', ErrMsg) then
    begin
      FreeAndNil(R);
      raise ESiagError.Create('SIAG: ' + ErrMsg);
    end;

    Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
    R.Free;
  except
    on E: Exception do
    begin
      if Assigned(R) then R.Free;
      Result := TAiMCPResponseBuilder.New
        .AddText('{"ok":false,"error":"' +
          E.Message.Replace('\', '\\').Replace('"', '\"')
                   .Replace(#10, '\n').Replace(#13, '') + '"}')
        .Build;
    end;
  end;
end;

constructor TSiagTool.Create;
begin
  inherited;
  FName        := 'mcp-siag';
  FDescription :=
    'FULL access to a SIAG analytics server: run any DSL (read and write) and ' +
    'manage configuration. Operations: health, login, get_me, execute_dsl, ' +
    'get/save/delete_categoria, get/save/delete_variable, ' +
    'get/save/delete_indicador, get_biblioteca_categorias, ' +
    'get_biblioteca_indicadores. DSL writes (CREATE/ALTER/DROP/LOAD/DEFINE) ' +
    'require the user to have rol=admin. Auth is automatic via ' +
    'SIAG_EMAIL/SIAG_PASSWORD/SIAG_TENANT env vars; pass email+password+tenant ' +
    'to override per call. For a read-only surface use mcp-siag-query.';
end;

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-siag',
    function: IAiMCPTool
    begin
      Result := TSiagTool.Create;
    end);
  WriteLn(ErrOutput, '[MCPService]   + mcp-siag');
end;

end.
