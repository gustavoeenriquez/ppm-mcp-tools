unit MCPTool.TextTransform;

{
  MCPTool.TextTransform
  MCP tool: mcp-text-transform

  Operations:
    Case:       uppercase, lowercase, titlecase, camelcase, pascalcase,
                snakecase, kebabcase, constantcase
    Edit:       trim, reverse, replace, truncate, pad_left, pad_right, repeat_
    Info:       count  (chars, words, lines, bytes)
    Encoding:   encode, decode  (base64, url, hex)
    Other:      slug, wrap
}

interface

uses
  uMakerAi.MCPServer.Core,
  System.SysUtils,
  System.Classes,
  System.Math,
  System.NetEncoding,
  System.JSON,
  System.StrUtils;

type

  // ── Parameters ─────────────────────────────────────────────────────────────

  TTextTransformParams = class
  private
    FOperation:   string;
    FText:        string;
    FSearch:      string;
    FReplacement: string;
    FMaxLength:   Integer;
    FPadChar:     string;
    FWidth:       Integer;
    FRepeatCount: Integer;
    FEncoding:    string;
    FDelimiter:   string;
  public
    [AiMCPSchemaDescription('Operation: uppercase, lowercase, titlecase, camelcase, pascalcase, ' +
      'snakecase, kebabcase, constantcase, trim, reverse, replace, truncate, ' +
      'pad_left, pad_right, repeat_, count, encode, decode, slug, wrap')]
    property Operation: string read FOperation write FOperation;

    [AiMCPSchemaDescription('Input text to transform')]
    property Text: string read FText write FText;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Search string (for replace operation)')]
    property Search: string read FSearch write FSearch;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Replacement string (for replace operation)')]
    property Replacement: string read FReplacement write FReplacement;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Max length (for truncate) or line width (for wrap)')]
    property MaxLength: Integer read FMaxLength write FMaxLength;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Pad character for pad_left / pad_right (default: space)')]
    property PadChar: string read FPadChar write FPadChar;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Target width for pad_left / pad_right')]
    property Width: Integer read FWidth write FWidth;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Number of repetitions for repeat_ operation')]
    property RepeatCount: Integer read FRepeatCount write FRepeatCount;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Encoding for encode/decode: base64, url, hex. Default: base64')]
    property Encoding: string read FEncoding write FEncoding;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Delimiter for wrap operation (default: space). Also used as join string in slug')]
    property Delimiter: string read FDelimiter write FDelimiter;
  end;

  // ── Tool ───────────────────────────────────────────────────────────────────

  TTextTransformTool = class(TAiMCPToolBase<TTextTransformParams>)
  private
    function SplitWords(const S: string): TStringList;
    function ToSlug(const S: string): string;
    function WordWrap(const S: string; Width: Integer): string;
    function HexEncode(const S: string): string;
    function HexDecode(const S: string): string;
  protected
    function ExecuteWithParams(const AParams: TTextTransformParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

procedure RegisterTools(AServer: TAiMCPServer);

implementation

// ── Helpers ─────────────────────────────────────────────────────────────────

function TTextTransformTool.SplitWords(const S: string): TStringList;
var
  i:    Integer;
  c:    Char;
  Word: string;
begin
  Result := TStringList.Create;
  Word   := '';
  for i := 1 to Length(S) do
  begin
    c := S[i];
    // Split on separators
    if CharInSet(c, [' ', '-', '_', '.', '/', '\']) then
    begin
      if Word <> '' then begin Result.Add(Word); Word := ''; end;
    end
    // Detect camelCase / PascalCase boundary (lower→Upper or Digit→Upper)
    else if (i > 1) and CharInSet(c, ['A'..'Z']) and
            (CharInSet(S[i-1], ['a'..'z', '0'..'9'])) then
    begin
      if Word <> '' then begin Result.Add(Word); Word := ''; end;
      Word := c;
    end
    else
      Word := Word + c;
  end;
  if Word <> '' then Result.Add(Word);
end;

function TTextTransformTool.ToSlug(const S: string): string;
var
  i: Integer;
  c: Char;
begin
  Result := '';
  for i := 1 to Length(S) do
  begin
    c := LowerCase(S[i])[1];
    if CharInSet(c, ['a'..'z', '0'..'9']) then
      Result := Result + c
    else if CharInSet(S[i], [' ', '-', '_', '.']) then
    begin
      if (Result <> '') and (Result[Length(Result)] <> '-') then
        Result := Result + '-';
    end;
  end;
  // strip trailing dash
  while (Result <> '') and (Result[Length(Result)] = '-') do
    Delete(Result, Length(Result), 1);
end;

function TTextTransformTool.WordWrap(const S: string; Width: Integer): string;
var
  Words:   TArray<string>;
  Line:    string;
  Word:    string;
  Lines:   TStringList;
begin
  if Width <= 0 then Width := 80;
  Words := S.Split([' ']);
  Lines := TStringList.Create;
  try
    Line := '';
    for Word in Words do
    begin
      if Word = '' then Continue;
      if Line = '' then
        Line := Word
      else if Length(Line) + 1 + Length(Word) <= Width then
        Line := Line + ' ' + Word
      else
      begin
        Lines.Add(Line);
        Line := Word;
      end;
    end;
    if Line <> '' then Lines.Add(Line);
    Result := Lines.Text;
    // Lines.Text appends #13#10; trim trailing
    Result := Trim(Result);
    // normalize line endings to LF
    Result := StringReplace(Result, #13#10, #10, [rfReplaceAll]);
  finally
    Lines.Free;
  end;
end;

function TTextTransformTool.HexEncode(const S: string): string;
var
  Bytes: TBytes;
  i:     Integer;
begin
  Bytes  := TEncoding.UTF8.GetBytes(S);
  Result := '';
  for i := 0 to High(Bytes) do
    Result := Result + IntToHex(Bytes[i], 2);
end;

function TTextTransformTool.HexDecode(const S: string): string;
var
  Bytes: TBytes;
  i, N:  Integer;
begin
  N := Length(S) div 2;
  SetLength(Bytes, N);
  for i := 0 to N - 1 do
    Bytes[i] := StrToInt('$' + Copy(S, i * 2 + 1, 2));
  Result := TEncoding.UTF8.GetString(Bytes);
end;

// ── Operations ─────────────────────────────────────────────────────────────

function TTextTransformTool.ExecuteWithParams(const AParams: TTextTransformParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op:    string;
  T:     string;
  Res:   string;
  Words: TStringList;
  i:     Integer;
  Pc:    Char;
  Enc:   string;
  R:     TJSONObject;
  W:     string;

  function JoinWords(const Sep: string): string;
  var j: Integer;
  begin
    Result := '';
    for j := 0 to Words.Count - 1 do
    begin
      if Result <> '' then Result := Result + Sep;
      Result := Result + LowerCase(Words[j]);
    end;
  end;

  function JoinWordsCap(const Sep: string): string;
  var j: Integer; Wj: string;
  begin
    Result := '';
    for j := 0 to Words.Count - 1 do
    begin
      if Result <> '' then Result := Result + Sep;
      Wj := LowerCase(Words[j]);
      if Wj <> '' then Wj[1] := UpCase(Wj[1]);
      Result := Result + Wj;
    end;
  end;

begin
  try
    Op := LowerCase(Trim(AParams.Operation));
    T  := AParams.Text;
    Res := '';

    // ── Simple string ops ─────────────────────────────────────────────────
    if      Op = 'uppercase'    then Res := UpperCase(T)
    else if Op = 'lowercase'    then Res := LowerCase(T)
    else if Op = 'trim'         then Res := Trim(T)
    else if Op = 'reverse'      then
    begin
      for i := Length(T) downto 1 do Res := Res + T[i];
    end
    else if Op = 'slug'         then Res := ToSlug(T)

    // ── titlecase ────────────────────────────────────────────────────────
    else if Op = 'titlecase' then
    begin
      Res := LowerCase(T);
      if Res <> '' then Res[1] := UpCase(Res[1]);
      for i := 2 to Length(Res) do
        if CharInSet(Res[i-1], [' ', '-', '_']) and CharInSet(Res[i], ['a'..'z']) then
          Res[i] := UpCase(Res[i]);
    end

    // ── Word-split based case transforms ─────────────────────────────────
    else if Op = 'camelcase' then
    begin
      Words := SplitWords(T);
      try
        Res := '';
        for i := 0 to Words.Count - 1 do
        begin
          W := LowerCase(Words[i]);
          if i = 0 then Res := Res + W
          else begin
            if W <> '' then W[1] := UpCase(W[1]);
            Res := Res + W;
          end;
        end;
      finally Words.Free; end;
    end
    else if Op = 'pascalcase' then
    begin
      Words := SplitWords(T);
      try Res := JoinWordsCap('');
      finally Words.Free; end;
    end
    else if Op = 'snakecase' then
    begin
      Words := SplitWords(T);
      try Res := JoinWords('_');
      finally Words.Free; end;
    end
    else if Op = 'kebabcase' then
    begin
      Words := SplitWords(T);
      try Res := JoinWords('-');
      finally Words.Free; end;
    end
    else if Op = 'constantcase' then
    begin
      Words := SplitWords(T);
      try
        Res := '';
        for i := 0 to Words.Count - 1 do
        begin
          if Res <> '' then Res := Res + '_';
          Res := Res + UpperCase(Words[i]);
        end;
      finally Words.Free; end;
    end

    // ── Replace ──────────────────────────────────────────────────────────
    else if Op = 'replace' then
    begin
      if AParams.Search = '' then
        raise Exception.Create('"search" is required for replace');
      Res := StringReplace(T, AParams.Search, AParams.Replacement, [rfReplaceAll]);
    end

    // ── Truncate ─────────────────────────────────────────────────────────
    else if Op = 'truncate' then
    begin
      var ML := AParams.MaxLength;
      if ML <= 0 then raise Exception.Create('"maxLength" is required for truncate');
      if Length(T) <= ML then Res := T
      else Res := Copy(T, 1, ML) + '...';
    end

    // ── Pad ──────────────────────────────────────────────────────────────
    else if Op = 'pad_left' then
    begin
      Pc := ' ';
      if AParams.PadChar <> '' then Pc := AParams.PadChar[1];
      Res := StringOfChar(Pc, Max(0, AParams.Width - Length(T))) + T;
    end
    else if Op = 'pad_right' then
    begin
      Pc := ' ';
      if AParams.PadChar <> '' then Pc := AParams.PadChar[1];
      Res := T + StringOfChar(Pc, Max(0, AParams.Width - Length(T)));
    end

    // ── Repeat ───────────────────────────────────────────────────────────
    else if Op = 'repeat_' then
    begin
      var RC := AParams.RepeatCount;
      if RC <= 0 then raise Exception.Create('"repeatCount" must be > 0');
      for i := 1 to RC do Res := Res + T;
    end

    // ── Wrap ─────────────────────────────────────────────────────────────
    else if Op = 'wrap' then
      Res := WordWrap(T, AParams.MaxLength)

    // ── Count ────────────────────────────────────────────────────────────
    else if Op = 'count' then
    begin
      var CharCount  := Length(T);
      var ByteCount  := Length(TEncoding.UTF8.GetBytes(T));
      var LineCount  := 1;
      for i := 1 to Length(T) do
        if T[i] = #10 then Inc(LineCount);
      var WordCount  := 0;
      var InWord := False;
      for i := 1 to Length(T) do
      begin
        if T[i] > ' ' then
        begin
          if not InWord then begin Inc(WordCount); InWord := True; end;
        end else InWord := False;
      end;

      R := TJSONObject.Create;
      R.AddPair('operation',   Op);
      R.AddPair('input',       T);
      R.AddPair('chars',       TJSONNumber.Create(CharCount));
      R.AddPair('words',       TJSONNumber.Create(WordCount));
      R.AddPair('lines',       TJSONNumber.Create(LineCount));
      R.AddPair('bytes_utf8',  TJSONNumber.Create(ByteCount));
      Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
      R.Free;
      Exit;
    end

    // ── Encode / Decode ──────────────────────────────────────────────────
    else if (Op = 'encode') or (Op = 'decode') then
    begin
      Enc := LowerCase(Trim(AParams.Encoding));
      if Enc = '' then Enc := 'base64';
      if Op = 'encode' then
      begin
        if      Enc = 'base64' then Res := TNetEncoding.Base64.Encode(T)
        else if Enc = 'url'    then Res := TNetEncoding.URL.Encode(T)
        else if Enc = 'hex'    then Res := HexEncode(T)
        else raise Exception.CreateFmt('Unknown encoding: "%s". Valid: base64, url, hex', [Enc]);
      end else begin
        if      Enc = 'base64' then Res := TNetEncoding.Base64.Decode(T)
        else if Enc = 'url'    then Res := TNetEncoding.URL.Decode(T)
        else if Enc = 'hex'    then Res := HexDecode(T)
        else raise Exception.CreateFmt('Unknown encoding: "%s". Valid: base64, url, hex', [Enc]);
      end;
    end

    else
      raise Exception.CreateFmt(
        'Unknown operation: "%s". Valid: uppercase, lowercase, titlecase, camelcase, ' +
        'pascalcase, snakecase, kebabcase, constantcase, trim, reverse, replace, truncate, ' +
        'pad_left, pad_right, repeat_, count, encode, decode, slug, wrap', [Op]);

    R := TJSONObject.Create;
    R.AddPair('operation', Op);
    R.AddPair('input',     T);
    R.AddPair('result',    Res);
    Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
    R.Free;

  except
    on E: Exception do
      Result := TAiMCPResponseBuilder.New
        .AddText('Error [mcp-text-transform]: ' + E.Message)
        .Build;
  end;
end;

constructor TTextTransformTool.Create;
begin
  inherited;
  FName        := 'mcp-text-transform';
  FDescription :=
    'Transform text in various ways. ' +
    'Case: uppercase, lowercase, titlecase, camelcase, pascalcase, snakecase, kebabcase, constantcase. ' +
    'Edit: trim, reverse, replace, truncate, pad_left, pad_right, repeat_, wrap, slug. ' +
    'Info: count (chars, words, lines, bytes). ' +
    'Encoding: encode/decode with base64, url, hex.';
end;

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-text-transform',
    function: IAiMCPTool
    begin
      Result := TTextTransformTool.Create;
    end);
  WriteLn(ErrOutput, '[mcp-text-transform] registered.');
end;

end.
