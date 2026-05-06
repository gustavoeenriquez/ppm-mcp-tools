unit MCPTool.Calculator;

{
  MCPTool.Calculator
  MCP tool: mcp-calculator

  Operations (binary):
    add, subtract, multiply, divide, modulo, power

  Operations (unary):
    sqrt, abs, floor, ceil, round, log10, ln, exp

  Operations (expression):
    evaluate — evaluates a math expression string.
               Supports: + - * / ^ % ( )
               Functions: sqrt abs floor ceil round log log10 log2 ln exp
                          sin cos tan asin acos atan  (degrees)
               Constants: pi  e
}

interface

uses
  uMakerAi.MCPServer.Core,
  System.SysUtils,
  System.Math,
  System.JSON;

type

  // ── Parameters ─────────────────────────────────────────────────────────────

  TCalculatorParams = class
  private
    FOperation:  string;
    FA:          Double;
    FB:          Double;
    FExpression: string;
    FPrecision:  Integer;
  public
    [AiMCPSchemaDescription('Operation: add, subtract, multiply, divide, modulo, power, ' +
      'sqrt, abs, floor, ceil, round, log10, ln, exp, evaluate')]
    property Operation: string read FOperation write FOperation;

    [AiMCPOptional]
    [AiMCPSchemaDescription('First operand (all operations except evaluate)')]
    property A: Double read FA write FA;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Second operand (binary: add, subtract, multiply, divide, modulo, power)')]
    property B: Double read FB write FB;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Math expression string for evaluate. Supports: + - * / ^ % (), ' +
      'functions: sqrt abs floor ceil round log log10 log2 ln exp sin cos tan (degrees), ' +
      'constants: pi e. Example: "sqrt(2^10) + pi * 3"')]
    property Expression: string read FExpression write FExpression;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Decimal places in result (default: 10, max: 15)')]
    property Precision: Integer read FPrecision write FPrecision;
  end;

  // ── Tool ───────────────────────────────────────────────────────────────────

  TCalculatorTool = class(TAiMCPToolBase<TCalculatorParams>)
  private
    function FormatResult(V: Double; Prec: Integer): string;
  protected
    function ExecuteWithParams(const AParams: TCalculatorParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

procedure RegisterTools(AServer: TAiMCPServer);

implementation

// ── Expression parser (recursive descent) ──────────────────────────────────
//
//   expr    = term   (('+' | '-') term)*
//   term    = factor (('*' | '/' | '%') factor)*
//   factor  = unary  ('^' factor)?        -- right-associative
//   unary   = ('-'|'+') unary | primary
//   primary = number | '(' expr ')' | constant | func '(' expr ')'

type
  TExprParser = record
  private
    FExpr: string;
    FPos:  Integer;
    procedure Skip;
    function  Peek: Char;
    function  Consume: Char;
    function  ParseExpr: Double;
    function  ParseTerm: Double;
    function  ParseFactor: Double;
    function  ParseUnary: Double;
    function  ParsePrimary: Double;
  public
    class function Evaluate(const Expr: string): Double; static;
  end;

procedure TExprParser.Skip;
begin
  while (FPos <= Length(FExpr)) and (FExpr[FPos] <= ' ') do
    Inc(FPos);
end;

function TExprParser.Peek: Char;
begin
  Skip;
  if FPos <= Length(FExpr) then Result := FExpr[FPos]
  else                          Result := #0;
end;

function TExprParser.Consume: Char;
begin
  Skip;
  if FPos <= Length(FExpr) then
  begin
    Result := FExpr[FPos];
    Inc(FPos);
  end
  else
    Result := #0;
end;

function TExprParser.ParseExpr: Double;
var
  Op:    Char;
  Right: Double;
begin
  Result := ParseTerm;
  while Peek in ['+', '-'] do
  begin
    Op    := Consume;
    Right := ParseTerm;
    if Op = '+' then Result := Result + Right
    else             Result := Result - Right;
  end;
end;

function TExprParser.ParseTerm: Double;
var
  Op:    Char;
  Right: Double;
begin
  Result := ParseFactor;
  while Peek in ['*', '/', '%'] do
  begin
    Op    := Consume;
    Right := ParseFactor;
    case Op of
      '*': Result := Result * Right;
      '/': begin
             if Right = 0 then raise Exception.Create('Division by zero');
             Result := Result / Right;
           end;
      '%': begin
             if Right = 0 then raise Exception.Create('Modulo by zero');
             Result := FMod(Result, Right);
           end;
    end;
  end;
end;

function TExprParser.ParseFactor: Double;
var
  Base: Double;
begin
  Base := ParseUnary;
  if Peek = '^' then
  begin
    Consume;
    Result := Power(Base, ParseFactor); // right-associative via recursion
  end
  else
    Result := Base;
end;

function TExprParser.ParseUnary: Double;
begin
  if Peek = '-' then
  begin
    Consume;
    Result := -ParseUnary;
  end
  else if Peek = '+' then
  begin
    Consume;
    Result := ParseUnary;
  end
  else
    Result := ParsePrimary;
end;

function TExprParser.ParsePrimary: Double;
var
  Name:   string;
  V:      Double;
  Start:  Integer;
  NumStr: string;
  FS:     TFormatSettings;
begin
  Skip;

  // Parenthesized sub-expression
  if Peek = '(' then
  begin
    Consume;
    Result := ParseExpr;
    Skip;
    if Peek <> ')' then
      raise Exception.Create('Missing closing ")"');
    Consume;
    Exit;
  end;

  // Number literal
  if Peek in ['0'..'9', '.'] then
  begin
    Start := FPos;
    while (FPos <= Length(FExpr)) and (FExpr[FPos] in ['0'..'9', '.']) do
      Inc(FPos);
    if (FPos <= Length(FExpr)) and (FExpr[FPos] in ['e', 'E']) then
    begin
      Inc(FPos);
      if (FPos <= Length(FExpr)) and (FExpr[FPos] in ['+', '-']) then
        Inc(FPos);
      while (FPos <= Length(FExpr)) and (FExpr[FPos] in ['0'..'9']) do
        Inc(FPos);
    end;
    NumStr := Copy(FExpr, Start, FPos - Start);
    FS := TFormatSettings.Create('en-US');
    if not TryStrToFloat(NumStr, Result, FS) then
      raise Exception.CreateFmt('Invalid number: "%s"', [NumStr]);
    Exit;
  end;

  // Identifier: constant or function
  if Peek in ['a'..'z', 'A'..'Z', '_'] then
  begin
    Start := FPos;
    while (FPos <= Length(FExpr)) and
          (FExpr[FPos] in ['a'..'z', 'A'..'Z', '0'..'9', '_']) do
      Inc(FPos);
    Name := LowerCase(Copy(FExpr, Start, FPos - Start));

    // Constants
    if Name = 'pi'  then begin Result := Pi;     Exit; end;
    if Name = 'e'   then begin Result := Exp(1); Exit; end;
    if Name = 'inf' then begin Result := Infinity; Exit; end;

    // Functions — must be followed by '('
    Skip;
    if Peek <> '(' then
      raise Exception.CreateFmt('Unknown identifier or missing "(" after "%s"', [Name]);
    Consume; // '('
    V := ParseExpr;
    Skip;
    if Peek <> ')' then
      raise Exception.CreateFmt('Missing ")" after argument to %s()', [Name]);
    Consume; // ')'

    if      Name = 'sqrt'  then
    begin
      if V < 0 then raise Exception.Create('sqrt of negative number');
      Result := Sqrt(V);
    end
    else if Name = 'abs'   then Result := Abs(V)
    else if Name = 'floor' then Result := Floor(V)
    else if Name = 'ceil'  then Result := Ceil(V)
    else if Name = 'round' then Result := System.Round(V)
    else if Name = 'log'   then
    begin
      if V <= 0 then raise Exception.Create('log requires positive argument');
      Result := Log10(V);
    end
    else if Name = 'log10' then
    begin
      if V <= 0 then raise Exception.Create('log10 requires positive argument');
      Result := Log10(V);
    end
    else if Name = 'log2'  then
    begin
      if V <= 0 then raise Exception.Create('log2 requires positive argument');
      Result := Log2(V);
    end
    else if Name = 'ln'    then
    begin
      if V <= 0 then raise Exception.Create('ln requires positive argument');
      Result := Ln(V);
    end
    else if Name = 'exp'   then Result := Exp(V)
    else if Name = 'sin'   then Result := Sin(V * Pi / 180)   // degrees
    else if Name = 'cos'   then Result := Cos(V * Pi / 180)
    else if Name = 'tan'   then Result := Tan(V * Pi / 180)
    else if Name = 'asin'  then Result := ArcSin(V) * 180 / Pi
    else if Name = 'acos'  then Result := ArcCos(V) * 180 / Pi
    else if Name = 'atan'  then Result := ArcTan(V) * 180 / Pi
    else if Name = 'sinr'  then Result := Sin(V)               // radians
    else if Name = 'cosr'  then Result := Cos(V)
    else if Name = 'tanr'  then Result := Tan(V)
    else raise Exception.CreateFmt('Unknown function: "%s"', [Name]);
    Exit;
  end;

  if FPos <= Length(FExpr) then
    raise Exception.CreateFmt('Unexpected character "%s" at position %d',
      [FExpr[FPos], FPos])
  else
    raise Exception.Create('Unexpected end of expression');
end;

class function TExprParser.Evaluate(const Expr: string): Double;
var
  P: TExprParser;
begin
  P.FExpr := Expr;
  P.FPos  := 1;
  Result  := P.ParseExpr;
  P.Skip;
  if P.FPos <= Length(P.FExpr) then
    raise Exception.CreateFmt('Unexpected text at position %d: "%s"',
      [P.FPos, Copy(P.FExpr, P.FPos, 20)]);
end;

// ── Tool implementation ─────────────────────────────────────────────────────

function TCalculatorTool.FormatResult(V: Double; Prec: Integer): string;
begin
  if Prec <= 0 then Prec := 10;
  Prec := Min(Prec, 15);
  // Integer-valued result → no decimal point
  if (not IsNan(V)) and (not IsInfinite(V)) and (Abs(V) < 1e15) and (V = Int(V)) then
    Result := IntToStr(Trunc(V))
  else
    Result := FloatToStrF(V, ffGeneral, 15, Prec);
end;

function TCalculatorTool.ExecuteWithParams(const AParams: TCalculatorParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op:       string;
  A, B:     Double;
  Res:      Double;
  Prec:     Integer;
  IsBinary: Boolean;
  R:        TJSONObject;
begin
  try
    Op   := LowerCase(Trim(AParams.Operation));
    A    := AParams.A;
    B    := AParams.B;
    Prec := AParams.Precision;
    if Prec <= 0 then Prec := 10;

    IsBinary := (Op = 'add') or (Op = 'subtract') or (Op = 'multiply') or
                (Op = 'divide') or (Op = 'modulo') or (Op = 'power');

    case Op[1] of
      'e': if Op = 'evaluate' then
           begin
             if Trim(AParams.Expression) = '' then
               raise Exception.Create('"expression" is required for evaluate operation');
             Res := TExprParser.Evaluate(Trim(AParams.Expression));
           end
           else if Op = 'exp' then Res := Exp(A)
           else raise Exception.CreateFmt('Unknown operation: "%s"', [Op]);
      'a': if      Op = 'add'      then Res := A + B
           else if Op = 'abs'      then Res := Abs(A)
           else raise Exception.CreateFmt('Unknown operation: "%s"', [Op]);
      's': if      Op = 'subtract' then Res := A - B
           else if Op = 'sqrt'     then
           begin
             if A < 0 then raise Exception.Create('sqrt requires non-negative number');
             Res := Sqrt(A);
           end
           else raise Exception.CreateFmt('Unknown operation: "%s"', [Op]);
      'm': if      Op = 'multiply' then Res := A * B
           else if Op = 'modulo'   then
           begin
             if B = 0 then raise Exception.Create('Modulo by zero');
             Res := FMod(A, B);
           end
           else raise Exception.CreateFmt('Unknown operation: "%s"', [Op]);
      'd': if      Op = 'divide'   then
           begin
             if B = 0 then raise Exception.Create('Division by zero');
             Res := A / B;
           end
           else raise Exception.CreateFmt('Unknown operation: "%s"', [Op]);
      'p': if      Op = 'power'    then Res := Power(A, B)
           else raise Exception.CreateFmt('Unknown operation: "%s"', [Op]);
      'f': if      Op = 'floor'    then Res := Floor(A)
           else raise Exception.CreateFmt('Unknown operation: "%s"', [Op]);
      'c': if      Op = 'ceil'     then Res := Ceil(A)
           else raise Exception.CreateFmt('Unknown operation: "%s"', [Op]);
      'r': if      Op = 'round'    then Res := System.Round(A)
           else raise Exception.CreateFmt('Unknown operation: "%s"', [Op]);
      'l': if      Op = 'log10'    then
           begin
             if A <= 0 then raise Exception.Create('log10 requires positive number');
             Res := Log10(A);
           end
           else if Op = 'ln'       then
           begin
             if A <= 0 then raise Exception.Create('ln requires positive number');
             Res := Ln(A);
           end
           else raise Exception.CreateFmt('Unknown operation: "%s"', [Op]);
    else
      raise Exception.CreateFmt(
        'Unknown operation: "%s". Valid: add, subtract, multiply, divide, modulo, ' +
        'power, sqrt, abs, floor, ceil, round, log10, ln, exp, evaluate', [Op]);
    end;

    R := TJSONObject.Create;
    R.AddPair('operation', Op);
    if Op = 'evaluate' then
      R.AddPair('expression', AParams.Expression)
    else
    begin
      R.AddPair('a', TJSONNumber.Create(A));
      if IsBinary then
        R.AddPair('b', TJSONNumber.Create(B));
    end;
    R.AddPair('result',     TJSONNumber.Create(Res));
    R.AddPair('result_str', FormatResult(Res, Prec));

    Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
    R.Free;

  except
    on E: Exception do
      Result := TAiMCPResponseBuilder.New
        .AddText('Error [mcp-calculator]: ' + E.Message)
        .Build;
  end;
end;

constructor TCalculatorTool.Create;
begin
  inherited;
  FName        := 'mcp-calculator';
  FDescription :=
    'Perform arithmetic and math operations. ' +
    'Binary: add, subtract, multiply, divide, modulo, power. ' +
    'Unary: sqrt, abs, floor, ceil, round, log10, ln, exp. ' +
    'Expression: evaluate a full math expression string with operator precedence, ' +
    'parentheses, functions (sqrt, sin, cos, log...) and constants (pi, e).';
end;

// ── Registration ───────────────────────────────────────────────────────────

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-calculator',
    function: IAiMCPTool
    begin
      Result := TCalculatorTool.Create;
    end);
  WriteLn(ErrOutput, '[mcp-calculator] registered.');
end;

end.
