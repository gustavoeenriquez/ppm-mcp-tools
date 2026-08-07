unit MCPTool.SiagQuery;

{
  MCPTool.SiagQuery  -  mcp-siag-query  (port 8771)

  READ-ONLY access to a SIAG analytics server. Query indicators and explore
  the data model, but never modify it: every DSL statement must begin with a
  read verb (QUERY, DRILL, NAVIGATE, INSPECT). Write verbs (CREATE, ALTER,
  DROP, LOAD, DEFINE, INSERT, UPDATE, DELETE) are rejected client-side before
  the request is sent - a safe surface to expose to autonomous agents even
  when the configured user has admin rights.

  Auth is handled internally via SIAG_EMAIL / SIAG_PASSWORD / SIAG_TENANT
  (see MCPTool.SiagClient); the model never sees or handles the token.

  Operations:
    health   - server health check (no DSL)
    get_me   - profile of the authenticated user (no DSL)
    query    - run a QUERY statement       (dsl required)
    drill    - run a DRILL statement        (dsl required)
    navigate - run a NAVIGATE statement     (dsl required)
    inspect  - run an INSPECT statement     (dsl required)
    dsl      - run any read-only statement(s) (dsl required)

  For query/drill/navigate/inspect the leading verb of the DSL must match the
  operation; "dsl" accepts any of the four read verbs.

  Author: Gustavo Enriquez  -  PascalAI
}

interface

uses
  uMakerAi.MCPServer.Core,
  System.JSON;

type
  TSiagQueryParams = class
  private
    FOperation: string;
    FDsl:       string;
  public
    [AiMCPSchemaDescription('Operation: health, get_me, query, drill, navigate, inspect, dsl')]
    property Operation: string read FOperation write FOperation;

    [AiMCPOptional]
    [AiMCPSchemaDescription('SIAG DSL statement to run (required for query/drill/navigate/inspect/dsl). ' +
      'Read-only only. Examples: "QUERY roi PERIOD 2024 GRANULARITY monthly"; ' +
      '"DRILL ventas BY DIMENSION region LAST 12 MONTHS"; ' +
      '"INSPECT INDICATORS"; "INSPECT INDICATOR roi"; "INSPECT TABLES"; ' +
      '"INSPECT DIMENSIONS OF ventas". Multiple statements may be separated by newlines.')]
    property Dsl: string read FDsl write FDsl;
  end;

  TSiagQueryTool = class(TAiMCPToolBase<TSiagQueryParams>)
  protected
    function ExecuteWithParams(const AParams: TSiagQueryParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

procedure RegisterTools(AServer: TAiMCPServer);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  MCPTool.SiagClient;

// ---------------------------------------------------------------------------
// Read-only enforcement
// ---------------------------------------------------------------------------

const
  WRITE_VERBS: array[0..7] of string =
    ('CREATE', 'ALTER', 'DROP', 'LOAD', 'DEFINE', 'INSERT', 'UPDATE', 'DELETE');
  READ_VERBS: array[0..3] of string =
    ('QUERY', 'DRILL', 'NAVIGATE', 'INSPECT');

// True if AWord appears in AText as a whole (case-insensitive) word.
function HasWholeWord(const AText, AWord: string): Boolean;
var
  U, W: string;
  P, L: Integer;
  Before, After: Char;
  IsWordChar: TSysCharSet;
begin
  IsWordChar := ['A'..'Z', '0'..'9', '_'];
  U := UpperCase(AText);
  W := UpperCase(AWord);
  L := Length(W);
  P := Pos(W, U);
  while P > 0 do
  begin
    if P = 1 then Before := ' ' else Before := U[P - 1];
    if P + L > Length(U) then After := ' ' else After := U[P + L];
    if (not CharInSet(Before, IsWordChar)) and (not CharInSet(After, IsWordChar)) then
      Exit(True);
    P := PosEx(W, U, P + L);
  end;
  Result := False;
end;

// Raises ESiagError if the DSL contains any write verb.
procedure GuardReadOnly(const ADsl: string);
var
  i: Integer;
begin
  for i := Low(WRITE_VERBS) to High(WRITE_VERBS) do
    if HasWholeWord(ADsl, WRITE_VERBS[i]) then
      raise ESiagError.CreateFmt(
        'Rejected: "%s" is a write operation. mcp-siag-query is read-only ' +
        '(QUERY, DRILL, NAVIGATE, INSPECT). Use mcp-siag for writes.',
        [WRITE_VERBS[i]]);
end;

// Leading verb of the first statement, uppercased.
function LeadingVerb(const ADsl: string): string;
var
  S: string;
  i: Integer;
begin
  S := Trim(ADsl);
  i := 1;
  while (i <= Length(S)) and CharInSet(S[i], ['A'..'Z', 'a'..'z']) do
    Inc(i);
  Result := UpperCase(Copy(S, 1, i - 1));
end;

// ---------------------------------------------------------------------------
// Tool
// ---------------------------------------------------------------------------

function TSiagQueryTool.ExecuteWithParams(const AParams: TSiagQueryParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op, Dsl, Verb, Token: string;
  R: TJSONObject;
  ErrMsg: string;

  function RunDsl(const AExpectedVerb: string): TJSONObject;
  begin
    if Trim(Dsl) = '' then
      raise ESiagError.CreateFmt('"dsl" is required for operation "%s"', [Op]);
    GuardReadOnly(Dsl);
    Verb := LeadingVerb(Dsl);
    if (AExpectedVerb <> '') and (Verb <> AExpectedVerb) then
      raise ESiagError.CreateFmt(
        'Operation "%s" expects a %s statement, but the DSL starts with "%s".',
        [Op, AExpectedVerb, Verb]);
    if (AExpectedVerb = '') and (IndexStr(Verb, READ_VERBS) < 0) then
      raise ESiagError.CreateFmt(
        'Leading verb "%s" is not a read operation (QUERY, DRILL, NAVIGATE, INSPECT).',
        [Verb]);
    Token := SiagEnsureToken;
    Result := SiagExecuteDSL(Token, Dsl);
  end;

begin
  try
    Op  := LowerCase(Trim(AParams.Operation));
    Dsl := AParams.Dsl;
    if Op = '' then
      raise ESiagError.Create('"operation" is required');

    if      Op = 'health'   then R := SiagHealth
    else if Op = 'get_me'   then R := SiagGetMe(SiagEnsureToken)
    else if Op = 'query'    then R := RunDsl('QUERY')
    else if Op = 'drill'    then R := RunDsl('DRILL')
    else if Op = 'navigate' then R := RunDsl('NAVIGATE')
    else if Op = 'inspect'  then R := RunDsl('INSPECT')
    else if Op = 'dsl'      then R := RunDsl('')
    else
      raise ESiagError.CreateFmt('Unknown operation "%s". Valid: health, ' +
        'get_me, query, drill, navigate, inspect, dsl', [Op]);

    // Surface a server-side {"error": "..."} as a tool error too.
    if R.TryGetValue<string>('error', ErrMsg) then
    begin
      R.Free;
      raise ESiagError.Create('SIAG: ' + ErrMsg);
    end;

    Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
    R.Free;
  except
    on E: Exception do
      Result := TAiMCPResponseBuilder.New
        .AddText('{"ok":false,"error":"' +
          E.Message.Replace('\', '\\').Replace('"', '\"')
                   .Replace(#10, '\n').Replace(#13, '') + '"}')
        .Build;
  end;
end;

constructor TSiagQueryTool.Create;
begin
  inherited;
  FName        := 'mcp-siag-query';
  FDescription :=
    'READ-ONLY access to a SIAG analytics server: query business indicators ' +
    'and explore the data model. Operations: health, get_me, query, drill, ' +
    'navigate, inspect, dsl. The "dsl" parameter carries a SIAG DSL statement ' +
    '(e.g. "QUERY roi PERIOD 2024 GRANULARITY monthly", ' +
    '"DRILL ventas BY DIMENSION region LAST 12 MONTHS", "INSPECT INDICATORS"). ' +
    'Write operations (CREATE/ALTER/DROP/LOAD/DEFINE/...) are rejected. ' +
    'Auth is automatic via the SIAG_EMAIL/SIAG_PASSWORD/SIAG_TENANT env vars.';
end;

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-siag-query',
    function: IAiMCPTool
    begin
      Result := TSiagQueryTool.Create;
    end);
  WriteLn(ErrOutput, '[MCPService]   + mcp-siag-query');
end;

end.
