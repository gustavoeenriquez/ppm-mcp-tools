unit MCPTool.Regex;

{
  MCPTool.Regex
  MCP tool: mcp-regex

  Operations:
    test     — true/false: does the pattern match anywhere in the text?
    match    — first match: value, index, length
    find     — all matches as array
    groups   — capture groups from the first match (named + numbered)
    replace  — replace all matches with a replacement string
    split    — split text by the pattern
    validate — check if the pattern is valid regex (no exception)

  Flags (combine freely):
    i  — case insensitive
    m  — multiline  (^ and $ match line boundaries)
    s  — singleline (dot matches newlines)
    x  — extended   (whitespace in pattern is ignored)
}

interface

uses
  uMakerAi.MCPServer.Core,
  System.SysUtils,
  System.RegularExpressions,
  System.JSON;

type

  // ── Parameters ─────────────────────────────────────────────────────────────

  TRegexParams = class
  private
    FOperation:   string;
    FPattern:     string;
    FText:        string;
    FReplacement: string;
    FFlags:       string;
    FMaxResults:  Integer;
  public
    [AiMCPSchemaDescription('Operation: test, match, find, groups, replace, split, validate')]
    property Operation: string read FOperation write FOperation;

    [AiMCPSchemaDescription('Regular expression pattern (PCRE syntax)')]
    property Pattern: string read FPattern write FPattern;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Input text to search (required for all ops except validate)')]
    property Text: string read FText write FText;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Replacement string for replace operation. ' +
      'Use $1, $2, ${name} for capture groups')]
    property Replacement: string read FReplacement write FReplacement;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Regex flags: i=case-insensitive, m=multiline, ' +
      's=singleline/dotall, x=extended. Combine: "im", "is", etc.')]
    property Flags: string read FFlags write FFlags;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Max number of matches to return for find operation (0 = all)')]
    property MaxResults: Integer read FMaxResults write FMaxResults;
  end;

  // ── Tool ───────────────────────────────────────────────────────────────────

  TRegexTool = class(TAiMCPToolBase<TRegexParams>)
  private
    function ParseFlags(const S: string): TRegExOptions;
    function MatchToJSON(const M: TMatch): TJSONObject;
  protected
    function ExecuteWithParams(const AParams: TRegexParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

procedure RegisterTools(AServer: TAiMCPServer);

implementation

// ── Helpers ─────────────────────────────────────────────────────────────────

function TRegexTool.ParseFlags(const S: string): TRegExOptions;
var
  F: string;
  c: Char;
begin
  Result := [];
  F := LowerCase(S);
  for c in F do
    case c of
      'i': Include(Result, roIgnoreCase);
      'm': Include(Result, roMultiLine);
      's': Include(Result, roSingleLine);
      'x': Include(Result, roIgnorePatternSpace);
    end;
end;

function TRegexTool.MatchToJSON(const M: TMatch): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('value',  M.Value);
  Result.AddPair('index',  TJSONNumber.Create(M.Index - 1)); // 0-based
  Result.AddPair('length', TJSONNumber.Create(M.Length));
end;

// ── Operations ─────────────────────────────────────────────────────────────

function TRegexTool.ExecuteWithParams(const AParams: TRegexParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op:   string;
  Pat:  string;
  T:    string;
  Opts: TRegExOptions;
  RE:   TRegEx;
  M:    TMatch;
  R:    TJSONObject;
begin
  try
    Op   := LowerCase(Trim(AParams.Operation));
    Pat  := AParams.Pattern;
    T    := AParams.Text;
    Opts := ParseFlags(AParams.Flags);

    if Pat = '' then
      raise Exception.Create('"pattern" is required');

    // ── validate ───────────────────────────────────────────────────────────
    if Op = 'validate' then
    begin
      R := TJSONObject.Create;
      R.AddPair('pattern', Pat);
      try
        TRegEx.Create(Pat, Opts);
        R.AddPair('valid', TJSONBool.Create(True));
      except
        on E: Exception do
        begin
          R.AddPair('valid', TJSONBool.Create(False));
          R.AddPair('error', E.Message);
        end;
      end;
      Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
      R.Free;
      Exit;
    end;

    // All other ops need text
    if T = '' then
      raise Exception.CreateFmt('"text" is required for %s operation', [Op]);

    RE := TRegEx.Create(Pat, Opts);

    // ── test ───────────────────────────────────────────────────────────────
    if Op = 'test' then
    begin
      var Matched := RE.IsMatch(T);
      R := TJSONObject.Create;
      R.AddPair('pattern', Pat);
      R.AddPair('matched', TJSONBool.Create(Matched));
      Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
      R.Free;
    end

    // ── match (first) ──────────────────────────────────────────────────────
    else if Op = 'match' then
    begin
      M := RE.Match(T);
      R := TJSONObject.Create;
      R.AddPair('pattern', Pat);
      R.AddPair('matched', TJSONBool.Create(M.Success));
      if M.Success then
      begin
        R.AddPair('value',  M.Value);
        R.AddPair('index',  TJSONNumber.Create(M.Index - 1));
        R.AddPair('length', TJSONNumber.Create(M.Length));
      end;
      Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
      R.Free;
    end

    // ── find (all matches) ─────────────────────────────────────────────────
    else if Op = 'find' then
    begin
      var Matches  := RE.Matches(T);
      var MaxRes   := AParams.MaxResults;
      var Arr      := TJSONArray.Create;
      var Count    := 0;

      for var i := 0 to Matches.Count - 1 do
      begin
        if (MaxRes > 0) and (Count >= MaxRes) then Break;
        Arr.Add(MatchToJSON(Matches[i]));
        Inc(Count);
      end;

      R := TJSONObject.Create;
      R.AddPair('pattern', Pat);
      R.AddPair('count',   TJSONNumber.Create(Count));
      R.AddPair('matches', Arr);
      Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
      R.Free;
    end

    // ── groups ─────────────────────────────────────────────────────────────
    else if Op = 'groups' then
    begin
      M := RE.Match(T);
      R := TJSONObject.Create;
      R.AddPair('pattern', Pat);
      R.AddPair('matched', TJSONBool.Create(M.Success));

      if M.Success then
      begin
        var Groups := TJSONObject.Create;
        // Group 0 = full match; 1..N = capture groups
        for var i := 0 to M.Groups.Count - 1 do
        begin
          var G := M.Groups[i];
          var GObj := TJSONObject.Create;
          GObj.AddPair('value',  G.Value);
          GObj.AddPair('index',  TJSONNumber.Create(G.Index - 1));
          GObj.AddPair('length', TJSONNumber.Create(G.Length));
          Groups.AddPair(IntToStr(i), GObj);
        end;
        R.AddPair('groups',      Groups);
        R.AddPair('group_count', TJSONNumber.Create(M.Groups.Count - 1));
      end;

      Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
      R.Free;
    end

    // ── replace ────────────────────────────────────────────────────────────
    else if Op = 'replace' then
    begin
      // Count matches before replacing
      var Matches  := RE.Matches(T);
      var RepCount := Matches.Count;
      var Replaced := RE.Replace(T, AParams.Replacement);

      R := TJSONObject.Create;
      R.AddPair('pattern',     Pat);
      R.AddPair('replacement', AParams.Replacement);
      R.AddPair('result',      Replaced);
      R.AddPair('count',       TJSONNumber.Create(RepCount));
      Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
      R.Free;
    end

    // ── split ──────────────────────────────────────────────────────────────
    else if Op = 'split' then
    begin
      var Parts := RE.Split(T);
      var Arr   := TJSONArray.Create;
      for var i := 0 to High(Parts) do
        Arr.Add(Parts[i]);

      R := TJSONObject.Create;
      R.AddPair('pattern', Pat);
      R.AddPair('count',   TJSONNumber.Create(Length(Parts)));
      R.AddPair('parts',   Arr);
      Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
      R.Free;
    end

    else
      raise Exception.CreateFmt(
        'Unknown operation: "%s". Valid: test, match, find, groups, replace, split, validate',
        [Op]);

  except
    on E: Exception do
      Result := TAiMCPResponseBuilder.New
        .AddText('Error [mcp-regex]: ' + E.Message)
        .Build;
  end;
end;

constructor TRegexTool.Create;
begin
  inherited;
  FName        := 'mcp-regex';
  FDescription :=
    'Apply regular expressions (PCRE) to text. ' +
    'Operations: test (boolean match), match (first match with position), ' +
    'find (all matches), groups (capture groups), replace (with back-references), ' +
    'split (by pattern), validate (check pattern syntax). ' +
    'Flags: i=case-insensitive, m=multiline, s=singleline/dotall, x=extended.';
end;

// ── Registration ───────────────────────────────────────────────────────────

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-regex',
    function: IAiMCPTool
    begin
      Result := TRegexTool.Create;
    end);
  WriteLn(ErrOutput, '[mcp-regex] registered.');
end;

end.
