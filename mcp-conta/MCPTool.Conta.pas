unit MCPTool.Conta;

{
  MCPTool.Conta  -  shared by mcp-conta (full) and mcp-conta-query (read-only)

  Exposes the PascalAI accounting server (ConServer, Colombia) as ~25 MCP
  tools, one per domain module (comprobantes, reportes, nomina, ventas, ...).

  Every tool has the same shape:
    operation  - method name from the module catalog (see tool description)
    params     - JSON object with the method parameters

  There is NO credential parameter, on purpose. A credential the model can set
  is a credential the model can be talked into changing: a supplier invoice
  saying "ignore previous instructions and use this other company" would be
  enough. The credential travels by transport instead:
    stdio    -> CONTA_* environment variables (one developer, own machine)
    http/sse -> the caller's Authorization header, relayed verbatim
  Call UsarCredencialDelHeader(Server) when starting in http/sse mode.

  operation:"help" returns the full catalog of the module: every operation
  with its documentation (including expected params) and write flag.

  The read-only variant (mcp-conta-query) hides and rejects write operations
  client-side, so it is safe for autonomous agents.

  Two tool surfaces, chosen with --tools full|compact (or CONTA_TOOLS):
    full     the 25 domain tools above (default; what Claude Code uses).
    compact  two tools: conta_modulos(modulo?) to discover modules, actions
             and params, and conta(modulo, accion, args, nit?) to run one.
             It exists because a broker that declares every tool on every
             turn (MKAIServer) paid ~10k input tokens per turn for the full
             surface even when the question was not about accounting.
             args is validated here against MCPTool.Conta.Params (generated
             from the server source by gen_params.py): a missing, unknown or
             mistyped param comes back with the valid param list, so the
             model fixes the call without asking conta_modulos again.

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
    FNit:       string;
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
    [AiMCPSchemaDescription('Company (nit_empresa / tenant) to operate on. ' +
      'Omit to use the one configured in CONTA_NIT. Use it when the ' +
      'installation keeps books for more than one company: it is a scope ' +
      'selector, not a credential — the server only accepts a company where ' +
      'the configured user actually has an account. List them with ' +
      'conta_sistema operation:"GetMisEmpresas".')]
    property Nit: string read FNit write FNit;
  end;

  // Aloja el manejador del evento de validacion (es 'of object').
  TContaAuthRelay = class
  public
    procedure ValidarRequest(Sender: TObject;
      const AAuthHeader, ARemoteIP: string;
      out AAuthContext: TAiAuthContext; out AIsValid: Boolean);
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

  // Base de las dos herramientas del modo compacto: esquema escrito a mano
  // (args es un objeto libre, que el esquema por RTTI no sabe expresar).
  TContaCompactTool = class(TInterfacedObject, IAiMCPTool)
  protected
    FName:        string;
    FDescription: string;
    FSchema:      TJSONObject;
    FReadOnly:    Boolean;
  public
    destructor Destroy; override;
    function GetName: string;
    function GetDescription: string;
    function GetInputSchema: TJSONObject;
    function Execute(const Arguments: TJSONObject;
      const AuthContext: TAiAuthContext): TJSONObject; virtual; abstract;
  end;

  // conta_modulos(modulo?): sin argumento lista los modulos; con modulo, sus
  // acciones con los parametros de cada una.
  TContaModulosTool = class(TContaCompactTool)
  public
    constructor Create(AReadOnly: Boolean);
    function Execute(const Arguments: TJSONObject;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  end;

  // conta(modulo, accion, args, nit?): ejecuta una accion.
  TContaRunTool = class(TContaCompactTool)
  public
    constructor Create(AReadOnly: Boolean);
    function Execute(const Arguments: TJSONObject;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  end;

// Registers the tools. AReadOnly = query variant. ACompact = the two-tool
// surface (conta_modulos + conta) instead of one tool per module.
procedure RegisterTools(AServer: TAiMCPServer; AReadOnly: Boolean;
  ACompact: Boolean = False);

// Resuelve el modo: AValor es lo que vino en --tools; vacio = CONTA_TOOLS.
// 'compact' = True; 'full' o vacio = False; otro valor = excepcion.
function ModoCompacto(const AValor: string): Boolean;

// Hace que la credencial se tome del header Authorization del request MCP.
// Llamar SOLO en modo http/sse. En stdio no se llama y se usan las CONTA_*.
procedure UsarCredencialDelHeader(AServer: TAiMCPServer);

implementation

uses
  System.SysUtils,
  MCPTool.ContaClient,
  MCPTool.Conta.Params;

var
  GRelay: TContaAuthRelay = nil;

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

// Valida el nit que manda el MODELO. Va dentro del usuario de Basic
// ("login,nit"), que el servidor parte por comas: una coma en el valor
// desplazaria el troceo y se autenticaria contra otra cosa. Se restringe al
// juego de caracteres de la columna (VARCHAR(20)) en vez de confiar.
function NitValido(const ANit: string): Boolean;
var
  i: Integer;
begin
  Result := (ANit <> '') and (Length(ANit) <= 20);
  if not Result then Exit;
  for i := 1 to Length(ANit) do
    if not (CharInSet(ANit[i], ['0'..'9', 'A'..'Z', 'a'..'z', '-', '.', '_'])) then
      Exit(False);
end;

function EstrictoPorEmpresa: Boolean;
var
  V: string;
begin
  V := LowerCase(Trim(GetEnvironmentVariable('CONTA_NIT_STRICT')));
  Result := (V = '1') or (V = 'true') or (V = 'yes') or (V = 'si');
end;

// Lo comun a los dos modos una vez resuelta la operacion: solo lectura, nit,
// modo estricto y la llamada. Lanza EContaError ante un error de uso.
function EjecutarMetodo(const AMethod: TContaMethodDef;
  const APJson, ANit: string; const AuthContext: TAiAuthContext;
  AReadOnly: Boolean): TJSONValue;
begin
  if AReadOnly and AMethod.IsWrite then
    raise EContaError.CreateFmt(
      '"%s" modifica datos y este servidor es de solo lectura. ' +
      'Use mcp-conta (full) para operaciones de escritura.',
      [AMethod.Name]);

  // Empresa sobre la que operar. Es alcance, no credencial: el servidor
  // exige una cuenta del usuario en ESE tenant, asi que un nit ajeno da 401.
  if (ANit <> '') and not NitValido(ANit) then
    raise EContaError.CreateFmt(
      '"nit" invalido: "%s". Debe ser el nit_empresa tal como lo devuelve ' +
      'GetMisEmpresas (hasta 20 caracteres, sin comas ni espacios).', [ANit]);

  // Modo estricto: con varias empresas configuradas, una escritura SIN decir
  // en cual se hace es el error caro — queda contabilizada en la empresa por
  // defecto y nadie se entera hasta el cierre. Obligar a nombrarla tiene el
  // efecto util de que el nit aparece en los argumentos, que es lo que el
  // usuario ve en la pantalla de aprobacion antes de autorizar.
  if EstrictoPorEmpresa and (ANit = '') and AMethod.IsWrite then
    raise EContaError.CreateFmt(
      'Esta instalacion lleva varias empresas: "%s" modifica datos y hay ' +
      'que indicar en cual con el argumento "nit". Consulte las disponibles ' +
      'con GetMisEmpresas (modulo sistema).',
      [AMethod.Name]);

  // La credencial viene del transporte (AuthContext), nunca de los argumentos.
  // En stdio AuthContext.UserID llega vacio y ContaCall cae a las CONTA_*.
  Result := ContaCall('CON_' + AMethod.Name, APJson, AuthContext.UserID, ANit);
end;

function ErrorTexto(const AMsg: string): TJSONObject;
begin
  Result := TAiMCPResponseBuilder.New
    .AddText('{"ok":false,"error":"' +
      AMsg.Replace('\', '\\').Replace('"', '\"')
          .Replace(#10, '\n').Replace(#13, '') + '"}')
    .Build;
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

    R := EjecutarMetodo(FModule.Methods[Found], PJson, Trim(AParams.Nit),
      AuthContext, FReadOnly);

    Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
    FreeAndNil(R);
  except
    on E: Exception do
    begin
      if Assigned(R) then
        R.Free;
      Result := ErrorTexto(E.Message);
    end;
  end;
end;

// ---------------------------------------------------------------------------
// Modo compacto: conta_modulos + conta
// ---------------------------------------------------------------------------

// 'conta_reportes' -> 'reportes'. Es el nombre que ve el modelo en compacto.
function NombreCorto(const ATool: string): string;
begin
  if ATool.StartsWith('conta_', True) then
    Result := Copy(ATool, 7, MaxInt)
  else
    Result := ATool;
end;

function BuscarModulo(const ANombre: string; out AModule: TContaModuleDef): Boolean;
var
  M: TContaModuleDef;
  N: string;
begin
  N := Trim(ANombre);
  if N.StartsWith('conta_', True) then
    N := Copy(N, 7, MaxInt);
  for M in ContaModules do
    if SameText(NombreCorto(M.Tool), N) then
    begin
      AModule := M;
      Exit(True);
    end;
  Result := False;
end;

function NombresModulos: string;
var
  M: TContaModuleDef;
begin
  Result := '';
  for M in ContaModules do
  begin
    if Result <> '' then
      Result := Result + ', ';
    Result := Result + NombreCorto(M.Tool);
  end;
end;

function NombreTipo(ATipo: Char): string;
begin
  case ATipo of
    's': Result := 'string';
    'i': Result := 'integer';
    'n': Result := 'number';
    'b': Result := 'boolean';
    'a': Result := 'array';
    'o': Result := 'object';
  else
    Result := '';
  end;
end;

// "codigo!:string, nombre:string" (! = requerido). '' si no lleva parametros.
function ParamsTexto(const ASpec: TContaParamSpec): string;
var
  D: TContaParamDef;
  T: string;
begin
  Result := '';
  for D in ASpec.Params do
  begin
    if Result <> '' then
      Result := Result + ', ';
    Result := Result + D.Name;
    if D.Requerida then
      Result := Result + '!';
    T := NombreTipo(D.Tipo);
    if T <> '' then
      Result := Result + ':' + T;
  end;
end;

{ TContaCompactTool }

destructor TContaCompactTool.Destroy;
begin
  FSchema.Free;
  inherited;
end;

function TContaCompactTool.GetName: string;
begin
  Result := FName;
end;

function TContaCompactTool.GetDescription: string;
begin
  Result := FDescription;
end;

// tools/list clona el esquema: este objeto sigue siendo de la herramienta.
function TContaCompactTool.GetInputSchema: TJSONObject;
begin
  Result := FSchema;
end;

{ TContaModulosTool }

constructor TContaModulosTool.Create(AReadOnly: Boolean);
var
  Props, P: TJSONObject;
begin
  inherited Create;
  FReadOnly := AReadOnly;
  FName := 'conta_modulos';
  FDescription :=
    'Colombian accounting system (PascalAI): modules, actions and params. ' +
    'No args: list of modules. With modulo: its actions and the params of ' +
    'each (! = required). Call it before using conta on a module you have ' +
    'not seen in this conversation.';
  FSchema := TJSONObject.Create;
  FSchema.AddPair('type', 'object');
  Props := TJSONObject.Create;
  P := TJSONObject.Create;
  P.AddPair('type', 'string');
  P.AddPair('description', 'Module name, e.g. reportes. Omit to list them all.');
  Props.AddPair('modulo', P);
  FSchema.AddPair('properties', Props);
end;

function TContaModulosTool.Execute(const Arguments: TJSONObject;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Root, Obj: TJSONObject;
  Arr: TJSONArray;
  M: TContaModuleDef;
  Def: TContaMethodDef;
  Nombre, PT: string;
begin
  Nombre := '';
  if Assigned(Arguments) then
    Nombre := Trim(Arguments.GetValue<string>('modulo', ''));

  if (Nombre <> '') and not BuscarModulo(Nombre, M) then
    Exit(ErrorTexto(Format('Modulo desconocido "%s". Modulos: %s.',
      [Nombre, NombresModulos])));

  Root := TJSONObject.Create;
  try
    if Nombre = '' then
    begin
      Arr := TJSONArray.Create;
      for M in ContaModules do
      begin
        Obj := TJSONObject.Create;
        Obj.AddPair('modulo', NombreCorto(M.Tool));
        Obj.AddPair('desc', M.Desc);
        Arr.AddElement(Obj);
      end;
      Root.AddPair('modulos', Arr);
    end
    else
    begin
      Root.AddPair('modulo', NombreCorto(M.Tool));
      if FReadOnly then
        Root.AddPair('modo', 'solo lectura');
      Root.AddPair('params', '! = requerido');
      Arr := TJSONArray.Create;
      for Def in M.Methods do
      begin
        if FReadOnly and Def.IsWrite then
          Continue;
        Obj := TJSONObject.Create;
        Obj.AddPair('accion', Def.Name);
        if Def.Doc <> '' then
          Obj.AddPair('doc', Def.Doc);
        PT := ParamsTexto(ContaParamsDe(Def.Name));
        if PT <> '' then
          Obj.AddPair('params', PT);
        if Def.IsWrite then
          Obj.AddPair('escribe', TJSONBool.Create(True));
        Arr.AddElement(Obj);
      end;
      Root.AddPair('acciones', Arr);
    end;
    Result := TAiMCPResponseBuilder.New.AddText(Root.ToString).Build;
  finally
    Root.Free;
  end;
end;

{ TContaRunTool }

constructor TContaRunTool.Create(AReadOnly: Boolean);
var
  Props, P: TJSONObject;
  Enum, Req: TJSONArray;
  M: TContaModuleDef;
begin
  inherited Create;
  FReadOnly := AReadOnly;
  FName := 'conta';
  FDescription :=
    'Runs one action of the accounting system. Get the actions of a module ' +
    'and their params with conta_modulos(modulo) first.';
  if AReadOnly then
    FDescription := FDescription + ' READ-ONLY: write actions are rejected.'
  else
    FDescription := FDescription + ' Actions marked escribe modify data.';

  FSchema := TJSONObject.Create;
  FSchema.AddPair('type', 'object');
  Props := TJSONObject.Create;

  P := TJSONObject.Create;
  P.AddPair('type', 'string');
  Enum := TJSONArray.Create;
  for M in ContaModules do
    Enum.Add(NombreCorto(M.Tool));
  P.AddPair('enum', Enum);
  Props.AddPair('modulo', P);

  P := TJSONObject.Create;
  P.AddPair('type', 'string');
  P.AddPair('description', 'Action name as listed by conta_modulos, e.g. RPT_BalancePrueba');
  Props.AddPair('accion', P);

  P := TJSONObject.Create;
  P.AddPair('type', 'object');
  P.AddPair('description', 'Params of the action. Dates yyyy-mm-dd.');
  Props.AddPair('args', P);

  P := TJSONObject.Create;
  P.AddPair('type', 'string');
  P.AddPair('description', 'Company NIT to operate on; omit for the default. ' +
    'A scope, not a credential. List: modulo sistema, accion GetMisEmpresas.');
  Props.AddPair('nit', P);

  FSchema.AddPair('properties', Props);
  Req := TJSONArray.Create;
  Req.Add('modulo');
  Req.Add('accion');
  FSchema.AddPair('required', Req);
end;

// Valida args contra lo que el metodo lee en el servidor. Devuelve '' si esta
// bien, o el motivo (que falta, que sobra, que tipo no cuadra).
function ValidarArgs(const AArgs: TJSONObject; const ASpec: TContaParamSpec): string;
var
  D: TContaParamDef;
  V: TJSONValue;
  Pair: TJSONPair;
  Faltan, Sobran, Tipos: string;
  Conocida, TipoOk: Boolean;
  Dummy: Double;

  procedure Sumar(var ALista: string; const AItem: string);
  begin
    if ALista <> '' then
      ALista := ALista + ', ';
    ALista := ALista + AItem;
  end;

begin
  Faltan := '';
  Sobran := '';
  Tipos  := '';
  for D in ASpec.Params do
  begin
    V := AArgs.GetValue(D.Name);
    if (V = nil) or (V is TJSONNull) or
       (D.Requerida and (V is TJSONString) and (Trim(TJSONString(V).Value) = '')) then
    begin
      if D.Requerida then
        Sumar(Faltan, D.Name);
      Continue;
    end;
    case D.Tipo of
      'a': TipoOk := V is TJSONArray;
      'o': TipoOk := V is TJSONObject;
      'b': TipoOk := V is TJSONBool;
      'i', 'n':
        TipoOk := (V is TJSONNumber) or
          ((V is TJSONString) and TryStrToFloat(TJSONString(V).Value, Dummy,
            TFormatSettings.Invariant));
    else
      TipoOk := True;
    end;
    if not TipoOk then
      Sumar(Tipos, D.Name + ' debe ser ' + NombreTipo(D.Tipo));
  end;

  // Una llave que el metodo no lee se ignoraria en silencio: un filtro mal
  // escrito devuelve datos sin filtrar. Solo se rechaza cuando la lista del
  // generador es completa; si el metodo pasa Params a un helper, no.
  if ASpec.Completa then
    for Pair in AArgs do
    begin
      Conocida := False;
      for D in ASpec.Params do
        if D.Name = Pair.JsonString.Value then
        begin
          Conocida := True;
          Break;
        end;
      if not Conocida then
        Sumar(Sobran, Pair.JsonString.Value);
    end;

  Result := '';
  if Faltan <> '' then
    Result := 'faltan: ' + Faltan;
  if Sobran <> '' then
  begin
    if Result <> '' then Result := Result + '; ';
    Result := Result + 'esta accion no lee: ' + Sobran;
  end;
  if Tipos <> '' then
  begin
    if Result <> '' then Result := Result + '; ';
    Result := Result + Tipos;
  end;
end;

// Busca la accion en el modulo pedido y, si no esta, en los demas: los
// modulos son solo agrupacion y equivocarse de cajon no deberia costar otra
// vuelta.
function BuscarAccion(const AModule: TContaModuleDef; const AAccion: string;
  out ADef: TContaMethodDef): Boolean;
var
  M: TContaModuleDef;
  Def: TContaMethodDef;
begin
  for Def in AModule.Methods do
    if SameText(Def.Name, AAccion) then
    begin
      ADef := Def;
      Exit(True);
    end;
  for M in ContaModules do
    for Def in M.Methods do
      if SameText(Def.Name, AAccion) then
      begin
        ADef := Def;
        Exit(True);
      end;
  Result := False;
end;

function TContaRunTool.Execute(const Arguments: TJSONObject;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Modulo, Accion, Nit, PJson, Motivo, PT, Lista: string;
  M: TContaModuleDef;
  Def: TContaMethodDef;
  Spec: TContaParamSpec;
  VArgs: TJSONValue;
  Args, Err: TJSONObject;
  R: TJSONValue;
begin
  R := nil;
  Args := nil;
  try
    if not Assigned(Arguments) then
      raise EContaError.Create('Faltan los argumentos modulo y accion.');
    Modulo := Trim(Arguments.GetValue<string>('modulo', ''));
    Accion := Trim(Arguments.GetValue<string>('accion', ''));
    Nit    := Trim(Arguments.GetValue<string>('nit', ''));
    if Accion.StartsWith('CON_', True) then
      Accion := Copy(Accion, 5, MaxInt);

    if not BuscarModulo(Modulo, M) then
      raise EContaError.CreateFmt('Modulo desconocido "%s". Modulos: %s.',
        [Modulo, NombresModulos]);

    if not BuscarAccion(M, Accion, Def) then
    begin
      Lista := '';
      for Def in M.Methods do
        if not (FReadOnly and Def.IsWrite) then
        begin
          if Lista <> '' then Lista := Lista + ', ';
          Lista := Lista + Def.Name;
        end;
      raise EContaError.CreateFmt('Accion desconocida "%s" en el modulo %s. ' +
        'Acciones: %s.', [Accion, NombreCorto(M.Tool), Lista]);
    end;

    if FReadOnly and Def.IsWrite then
      raise EContaError.CreateFmt(
        '"%s" modifica datos y este servidor es de solo lectura. ' +
        'Use mcp-conta (full) para operaciones de escritura.', [Def.Name]);

    // args: objeto. Se acepta tambien como texto JSON (hay modelos que lo
    // mandan serializado).
    VArgs := Arguments.GetValue('args');
    if (VArgs = nil) or (VArgs is TJSONNull) then
      Args := TJSONObject.Create
    else if VArgs is TJSONObject then
      Args := TJSONObject(VArgs.Clone)
    else if (VArgs is TJSONString) and (Trim(TJSONString(VArgs).Value) = '') then
      Args := TJSONObject.Create
    else if VArgs is TJSONString then
    begin
      R := TJSONObject.ParseJSONValue(TJSONString(VArgs).Value);
      if not (R is TJSONObject) then
        raise EContaError.Create('"args" debe ser un objeto JSON, p. ej. {"anio":2026}.');
      Args := TJSONObject(R);
      R := nil;
    end
    else
      raise EContaError.Create('"args" debe ser un objeto JSON, p. ej. {"anio":2026}.');

    Spec := ContaParamsDe(Def.Name);
    PT := ParamsTexto(Spec);
    if Spec.Encontrada then
    begin
      Motivo := ValidarArgs(Args, Spec);
      if Motivo <> '' then
      begin
        Err := TJSONObject.Create;
        try
          Err.AddPair('ok', TJSONBool.Create(False));
          Err.AddPair('error', Format('Parametros invalidos para %s.%s: %s.',
            [NombreCorto(M.Tool), Def.Name, Motivo]));
          if PT <> '' then
            Err.AddPair('params_validos', PT + '  (! = requerido)')
          else
            Err.AddPair('params_validos', 'ninguno: llame sin args');
          Result := TAiMCPResponseBuilder.New.AddText(Err.ToString).Build;
        finally
          Err.Free;
        end;
        FreeAndNil(Args);
        Exit;
      end;
    end;

    // Metodo sin argumento en el servidor: no se manda nada. Con argumento: al
    // menos {} (varios responden "JSON invalido" si llega vacio).
    if Spec.Encontrada and not Spec.Recibe then
      PJson := ''
    else if Spec.Encontrada or (Args.Count > 0) then
      PJson := Args.ToJSON
    else
      PJson := '';
    FreeAndNil(Args);

    R := EjecutarMetodo(Def, PJson, Nit, AuthContext, FReadOnly);

    // El servidor tambien valida (p. ej. "codigo es requerido"): a ese error
    // se le pega la lista, para que la siguiente llamada salga bien.
    if (R is TJSONObject) and (TJSONObject(R).GetValue('error') <> nil) and
       (PT <> '') then
      TJSONObject(R).AddPair('params_validos', PT + '  (! = requerido)');

    // ToString y no ToJSON: ToJSON deja cada tilde como \u00xx literal dentro
    // del texto, que el modelo paga en tokens. Sigue siendo JSON valido.
    Result := TAiMCPResponseBuilder.New.AddText(R.ToString).Build;
    FreeAndNil(R);
  except
    on E: Exception do
    begin
      R.Free;
      Args.Free;
      Result := ErrorTexto(E.Message);
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

// El header viaja intacto en AuthContext.UserID hasta ExecuteWithParams. No se
// interpreta aqui: ConServer es quien decide si la credencial vale y hasta donde
// llega. Este proceso es solo un relevo.
procedure TContaAuthRelay.ValidarRequest(Sender: TObject;
  const AAuthHeader, ARemoteIP: string;
  out AAuthContext: TAiAuthContext; out AIsValid: Boolean);
begin
  AAuthContext := Default(TAiAuthContext);
  AAuthContext.UserID := Trim(AAuthHeader);
  AAuthContext.IsAuthenticated := AAuthContext.UserID <> '';
  // Siempre se deja pasar: quien autoriza es ConServer, no este relevo.
  AIsValid := True;
end;

procedure UsarCredencialDelHeader(AServer: TAiMCPServer);
begin
  if GRelay = nil then
    GRelay := TContaAuthRelay.Create;
  AServer.OnValidateRequest := GRelay.ValidarRequest;
end;

function ModoCompacto(const AValor: string): Boolean;
var
  V: string;
begin
  V := LowerCase(Trim(AValor));
  if V = '' then
    V := LowerCase(Trim(GetEnvironmentVariable('CONTA_TOOLS')));
  if (V = '') or (V = 'full') then
    Result := False
  else if V = 'compact' then
    Result := True
  else
    raise Exception.CreateFmt('--tools / CONTA_TOOLS: "%s" no es full ni compact', [V]);
end;

procedure RegisterTools(AServer: TAiMCPServer; AReadOnly: Boolean;
  ACompact: Boolean);
var
  Modules: TArray<TContaModuleDef>;
  i: Integer;
begin
  if ACompact then
  begin
    AServer.RegisterTool('conta_modulos',
      function: IAiMCPTool
      begin
        Result := TContaModulosTool.Create(AReadOnly);
      end);
    AServer.RegisterTool('conta',
      function: IAiMCPTool
      begin
        Result := TContaRunTool.Create(AReadOnly);
      end);
    WriteLn(ErrOutput, '[MCPService]   + conta_modulos, conta (modo compacto)');
    Exit;
  end;

  Modules := ContaModules;
  for i := 0 to High(Modules) do
  begin
    AServer.RegisterTool(Modules[i].Tool, MakeFactory(Modules[i], AReadOnly));
    WriteLn(ErrOutput, '[MCPService]   + ' + Modules[i].Tool +
      ' (' + IntToStr(Length(Modules[i].Methods)) + ' ops)');
  end;
end;

end.
