unit MCPTool.Tokenizer;

{
  MCPTool.Tokenizer
  MCP tool: mcp-tokenizer

  Operations:
    count    — estimate token count for a given model/tokenizer
    encode   — split text into word-piece tokens (returned as string array)
    truncate — truncate text to fit within max_tokens
    split    — split text into overlapping chunks of max_tokens each
    estimate — detailed breakdown: chars, words, sentences + multi-model estimates

  Model shortcuts (affect chars-per-token ratio):
    gpt4 / gpt-4 / gpt-3.5 / cl100k  — ~4.0 chars/token  (OpenAI cl100k_base)
    gpt3 / p50k / davinci              — ~4.0 chars/token  (OpenAI p50k_base)
    claude                             — ~3.8 chars/token
    llama / llama2 / mistral           — ~3.5 chars/token
    gemini                             — ~4.0 chars/token
    words                              — 1 token per whitespace word
    chars                              — 1 token per character
    (default)                          — 4.0 chars/token

  Note: these are approximations. Exact counts require the model's vocabulary.
}

interface

uses
  uMakerAi.MCPServer.Core,
  System.SysUtils,
  System.Math,
  System.JSON,
  System.RegularExpressions;

type

  // ── Parameters ─────────────────────────────────────────────────────────────

  TTokenizerParams = class
  private
    FOperation: string;
    FText:      string;
    FModel:     string;
    FMaxTokens: Integer;
    FOverlap:   Integer;
  public
    [AiMCPSchemaDescription('Operation: count, encode, truncate, split, estimate')]
    property Operation: string read FOperation write FOperation;

    [AiMCPSchemaDescription('Input text')]
    property Text: string read FText write FText;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Model/tokenizer for estimation: gpt4, gpt3, claude, llama, ' +
      'mistral, gemini, words, chars. Default: gpt4')]
    property Model: string read FModel write FModel;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Maximum tokens for truncate/split operations')]
    property MaxTokens: Integer read FMaxTokens write FMaxTokens;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Token overlap between consecutive chunks for split (default: 0)')]
    property Overlap: Integer read FOverlap write FOverlap;
  end;

  // ── Tool ───────────────────────────────────────────────────────────────────

  TTokenizerTool = class(TAiMCPToolBase<TTokenizerParams>)
  private
    function CharsPerToken(const Model: string): Double;
    function EstimateTokens(const Text, Model: string): Integer;
    function WordCount(const Text: string): Integer;
    function SentenceCount(const Text: string): Integer;
    function Tokenize(const Text: string): TArray<string>;
    function TruncateToTokens(const Text, Model: string; MaxTok: Integer): string;
  protected
    function ExecuteWithParams(const AParams: TTokenizerParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

procedure RegisterTools(AServer: TAiMCPServer);

implementation

// ── Helpers ─────────────────────────────────────────────────────────────────

function TTokenizerTool.CharsPerToken(const Model: string): Double;
var
  M: string;
begin
  M := LowerCase(Trim(Model));
  if      (M = 'words')                              then Result := 0   // special
  else if (M = 'chars')                              then Result := 1.0
  else if (M = 'claude')                             then Result := 3.8
  else if (M = 'llama')  or (M = 'llama2')  or
          (M = 'mistral') or (M = 'llama3')          then Result := 3.5
  else if (M = 'gemini') or (M = 'bard')             then Result := 4.0
  else   {gpt4, gpt3, gpt-4, gpt-3.5, cl100k, p50k, default} Result := 4.0;
end;

function TTokenizerTool.EstimateTokens(const Text, Model: string): Integer;
var
  CPT: Double;
begin
  CPT := CharsPerToken(Model);
  if CPT = 0 then // word mode
    Result := WordCount(Text)
  else if CPT = 1.0 then
    Result := Length(Text)
  else
    Result := Max(1, Round(Length(Text) / CPT));
end;

function TTokenizerTool.WordCount(const Text: string): Integer;
var
  InWord: Boolean;
  i:      Integer;
begin
  Result := 0;
  InWord := False;
  for i := 1 to Length(Text) do
  begin
    if Text[i] > ' ' then
    begin
      if not InWord then
      begin
        Inc(Result);
        InWord := True;
      end;
    end else
      InWord := False;
  end;
end;

function TTokenizerTool.SentenceCount(const Text: string): Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 1 to Length(Text) do
    if CharInSet(Text[i], ['.', '!', '?']) then
      Inc(Result);
  if Result = 0 then Result := 1;
end;

function TTokenizerTool.Tokenize(const Text: string): TArray<string>;
// Splits text into word-piece tokens:
//   - runs of letters/digits → one token
//   - each punctuation character → one token
//   - whitespace is consumed (not emitted)
var
  Tokens: TArray<string>;
  Cap:    Integer;
  Count:  Integer;
  i:      Integer;
  c:      Char;
  Word:   string;

  procedure Push(const S: string);
  begin
    if Count >= Cap then
    begin
      Cap := Cap * 2 + 16;
      SetLength(Tokens, Cap);
    end;
    Tokens[Count] := S;
    Inc(Count);
  end;

begin
  Cap   := 64;
  Count := 0;
  SetLength(Tokens, Cap);
  Word  := '';

  for i := 1 to Length(Text) do
  begin
    c := Text[i];
    if CharInSet(c, ['a'..'z', 'A'..'Z', '0'..'9', '_']) then
      Word := Word + c
    else
    begin
      if Word <> '' then
      begin
        Push(Word);
        Word := '';
      end;
      if c > ' ' then // punctuation, not whitespace
        Push(c);
    end;
  end;
  if Word <> '' then Push(Word);

  SetLength(Tokens, Count);
  Result := Tokens;
end;

function TTokenizerTool.TruncateToTokens(const Text, Model: string;
  MaxTok: Integer): string;
// Truncate at word boundaries to stay within MaxTok
var
  CPT:     Double;
  MaxChar: Integer;
  i:       Integer;
begin
  CPT := CharsPerToken(Model);
  if CPT = 0 then
  begin
    // word mode — count words
    var WN := 0;
    var InW := False;
    var LastEnd := 0;
    for i := 1 to Length(Text) do
    begin
      if Text[i] > ' ' then
      begin
        if not InW then begin InW := True; Inc(WN); end;
      end else begin
        if InW then LastEnd := i - 1;
        InW := False;
      end;
      if WN > MaxTok then
      begin
        Result := Trim(Copy(Text, 1, LastEnd));
        Exit;
      end;
    end;
    Result := Text;
  end
  else if CPT = 1.0 then
    Result := Copy(Text, 1, MaxTok)
  else
  begin
    MaxChar := Round(MaxTok * CPT);
    if Length(Text) <= MaxChar then
    begin
      Result := Text;
      Exit;
    end;
    // Snap to word boundary
    i := MaxChar;
    while (i > 1) and (Text[i] > ' ') do Dec(i);
    Result := Trim(Copy(Text, 1, i));
  end;
end;

// ── Main execution ──────────────────────────────────────────────────────────

function TTokenizerTool.ExecuteWithParams(const AParams: TTokenizerParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op:    string;
  T:     string;
  Mdl:   string;
  R:     TJSONObject;
begin
  try
    Op  := LowerCase(Trim(AParams.Operation));
    T   := AParams.Text;
    Mdl := LowerCase(Trim(AParams.Model));
    if Mdl = '' then Mdl := 'gpt4';

    // ── count ──────────────────────────────────────────────────────────────
    if Op = 'count' then
    begin
      var N := EstimateTokens(T, Mdl);
      R := TJSONObject.Create;
      R.AddPair('model',       Mdl);
      R.AddPair('tokens',      TJSONNumber.Create(N));
      R.AddPair('chars',       TJSONNumber.Create(Length(T)));
      R.AddPair('words',       TJSONNumber.Create(WordCount(T)));
      R.AddPair('note',        'approximate — no vocabulary loaded');
      Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
      R.Free;
    end

    // ── encode ─────────────────────────────────────────────────────────────
    else if Op = 'encode' then
    begin
      var Toks := Tokenize(T);
      var Arr  := TJSONArray.Create;
      for var Tok in Toks do
        Arr.Add(Tok);

      R := TJSONObject.Create;
      R.AddPair('count',  TJSONNumber.Create(Length(Toks)));
      R.AddPair('tokens', Arr);
      R.AddPair('note',   'word-piece split — not BPE vocabulary');
      Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
      R.Free;
    end

    // ── truncate ───────────────────────────────────────────────────────────
    else if Op = 'truncate' then
    begin
      if AParams.MaxTokens <= 0 then
        raise Exception.Create('"maxTokens" is required for truncate');

      var Before   := EstimateTokens(T, Mdl);
      var Truncated := TruncateToTokens(T, Mdl, AParams.MaxTokens);
      var After    := EstimateTokens(Truncated, Mdl);
      var WasCut   := Length(Truncated) < Length(T);

      R := TJSONObject.Create;
      R.AddPair('model',         Mdl);
      R.AddPair('max_tokens',    TJSONNumber.Create(AParams.MaxTokens));
      R.AddPair('tokens_before', TJSONNumber.Create(Before));
      R.AddPair('tokens_after',  TJSONNumber.Create(After));
      R.AddPair('truncated',     TJSONBool.Create(WasCut));
      R.AddPair('result',        Truncated);
      Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
      R.Free;
    end

    // ── split ──────────────────────────────────────────────────────────────
    else if Op = 'split' then
    begin
      if AParams.MaxTokens <= 0 then
        raise Exception.Create('"maxTokens" is required for split');

      var MaxTok  := AParams.MaxTokens;
      var Overlap := Max(0, Min(AParams.Overlap, MaxTok - 1));
      var CPT     := CharsPerToken(Mdl);
      var ChunkCh := Round(MaxTok * Max(CPT, 1.0));
      var StepCh  := Round((MaxTok - Overlap) * Max(CPT, 1.0));
      if StepCh < 1 then StepCh := 1;

      var Chunks := TJSONArray.Create;
      var Pos    := 1;
      var Total  := Length(T);

      while Pos <= Total do
      begin
        var EndPos := Min(Pos + ChunkCh - 1, Total);
        // Snap end to word boundary (forward search not needed; snap backward)
        if EndPos < Total then
          while (EndPos > Pos) and (T[EndPos] > ' ') do Dec(EndPos);

        var Chunk := Trim(Copy(T, Pos, EndPos - Pos + 1));
        if Chunk <> '' then
        begin
          var ChObj := TJSONObject.Create;
          ChObj.AddPair('index',  TJSONNumber.Create(Chunks.Count));
          ChObj.AddPair('tokens', TJSONNumber.Create(EstimateTokens(Chunk, Mdl)));
          ChObj.AddPair('text',   Chunk);
          Chunks.AddElement(ChObj);
        end;

        Pos := Pos + StepCh;
        if Pos > Total then Break;
      end;

      R := TJSONObject.Create;
      R.AddPair('model',      Mdl);
      R.AddPair('max_tokens', TJSONNumber.Create(MaxTok));
      R.AddPair('overlap',    TJSONNumber.Create(Overlap));
      R.AddPair('count',      TJSONNumber.Create(Chunks.Count));
      R.AddPair('chunks',     Chunks);
      Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
      R.Free;
    end

    // ── estimate ───────────────────────────────────────────────────────────
    else if Op = 'estimate' then
    begin
      var Chars     := Length(T);
      var Words     := WordCount(T);
      var Sentences := SentenceCount(T);

      R := TJSONObject.Create;
      R.AddPair('chars',        TJSONNumber.Create(Chars));
      R.AddPair('words',        TJSONNumber.Create(Words));
      R.AddPair('sentences',    TJSONNumber.Create(Sentences));

      var Models := TJSONObject.Create;
      for var M in ['gpt4', 'claude', 'llama', 'words', 'chars'] do
        Models.AddPair(M, TJSONNumber.Create(EstimateTokens(T, M)));
      R.AddPair('estimated_tokens', Models);
      R.AddPair('note', 'approximate — no vocabulary loaded');

      Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
      R.Free;
    end

    else
      raise Exception.CreateFmt(
        'Unknown operation: "%s". Valid: count, encode, truncate, split, estimate', [Op]);

  except
    on E: Exception do
      Result := TAiMCPResponseBuilder.New
        .AddText('Error [mcp-tokenizer]: ' + E.Message)
        .Build;
  end;
end;

constructor TTokenizerTool.Create;
begin
  inherited;
  FName        := 'mcp-tokenizer';
  FDescription :=
    'Estimate and manipulate text token counts for LLM APIs. ' +
    'count: estimate tokens for gpt4/claude/llama/gemini/words/chars. ' +
    'encode: split text into word-piece tokens. ' +
    'truncate: cut text to fit within a token budget. ' +
    'split: divide text into overlapping token-sized chunks for RAG/context windows. ' +
    'estimate: full breakdown with multi-model token estimates.';
end;

// ── Registration ───────────────────────────────────────────────────────────

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-tokenizer',
    function: IAiMCPTool
    begin
      Result := TTokenizerTool.Create;
    end);
  WriteLn(ErrOutput, '[mcp-tokenizer] registered.');
end;

end.
