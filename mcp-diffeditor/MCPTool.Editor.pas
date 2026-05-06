unit MCPTool.Editor;

(*
  MCPTool.Editor  ·  mcp-editor  ·  port 8650

  File editor with unified diff support (based on uMakerAi.Utils.DiffUpdater).
  Designed for LLMs: line-numbered view, apply_diff with fuzzy matching,
  exact replace, and line-range replacement.

  Operations:
    view          {path, offset?, limit?}                          → numbered content
    apply_diff    {path, diff, backup?, encoding?}                 → ok, hunks_applied, lines_before, lines_after
    replace       {path, old_string, new_string, encoding?}        → ok, replacements
    replace_lines {path, start_line, end_line, content, encoding?} → ok, lines_removed, lines_added
    insert_lines  {path, line, content, encoding?}                 → ok, lines_inserted

  Port: 8650
*)

interface

uses
  uMakerAi.MCPServer.Core,
  uMakerAi.Utils.DiffUpdater,
  System.JSON,
  System.SysUtils,
  System.StrUtils,
  System.Classes,
  System.IOUtils,
  System.Math,
  System.Generics.Collections;

type
  TEditorParams = class
  private
    FOperation:  string;
    FPath:       string;
    FDiff:      string;
    FOldstr:    string;
    FNewstr:    string;
    FContent:   string;
    FEncoding:  string;
    FOffset:    Integer;
    FLimit:     Integer;
    FFromline:  Integer;
    FToline:    Integer;
    FLine:      Integer;
    FBackup:    Boolean;
  public
    [AiMCPSchemaDescription('Operation: view, apply_diff, replace, replace_lines, insert_lines')]
    property Operation:  string  read FOperation  write FOperation;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Path to the file to edit or view. Required for all operations.')]
    property Path:       string  read FPath       write FPath;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Unified diff text (patch). Required for: apply_diff. Format: @@ -start,count +start,count @@ then lines starting with +, -, or space.')]
    property Diff:       string  read FDiff       write FDiff;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Exact text to find and replace. Required for: replace.')]
    property Oldstr:     string  read FOldstr     write FOldstr;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Replacement text. Required for: replace.')]
    property Newstr:     string  read FNewstr     write FNewstr;

    [AiMCPOptional]
    [AiMCPSchemaDescription('New content to write. Required for: replace_lines, insert_lines.')]
    property Content:    string  read FContent    write FContent;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Text encoding: utf8 (default), utf16, ansi.')]
    property Encoding:   string  read FEncoding   write FEncoding;

    [AiMCPOptional]
    [AiMCPSchemaDescription('First line to show (1-based). Used by: view. Default: 1')]
    property Offset:     Integer read FOffset     write FOffset;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Number of lines to show. Used by: view. Default: 0 = all')]
    property Limit:      Integer read FLimit      write FLimit;

    [AiMCPOptional]
    [AiMCPSchemaDescription('First line of range to replace (1-based). Required for: replace_lines.')]
    property Fromline:   Integer read FFromline   write FFromline;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Last line of range to replace (1-based, inclusive). Required for: replace_lines.')]
    property Toline:     Integer read FToline     write FToline;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Line number to insert BEFORE (1-based). Use 0 to append at end. Required for: insert_lines.')]
    property Line:       Integer read FLine       write FLine;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Save a .bak backup before editing. Used by: apply_diff, replace, replace_lines, insert_lines. Default: false')]
    property Backup:     Boolean read FBackup     write FBackup;
  end;

  TEditorTool = class(TAiMCPToolBase<TEditorParams>)
  private
    function ResolveEncoding(const Enc: string): TEncoding;
    procedure SaveBackup(const FilePath: string);
    function DoView(const P: TEditorParams): TJSONObject;
    function DoApplyDiff(const P: TEditorParams): TJSONObject;
    function DoReplace(const P: TEditorParams): TJSONObject;
    function DoReplaceLines(const P: TEditorParams): TJSONObject;
    function DoInsertLines(const P: TEditorParams): TJSONObject;
  protected
    function ExecuteWithParams(const AParams: TEditorParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

procedure RegisterTools(AServer: TAiMCPServer);

implementation

{ TEditorTool }

function TEditorTool.ResolveEncoding(const Enc: string): TEncoding;
var
  E: string;
begin
  E := LowerCase(Trim(Enc));
  if      E = 'utf16' then Result := TEncoding.Unicode
  else if E = 'ansi'  then Result := TEncoding.ANSI
  else                     Result := TEncoding.UTF8;
end;

procedure TEditorTool.SaveBackup(const FilePath: string);
var
  BakPath: string;
begin
  BakPath := FilePath + '.bak';
  if TFile.Exists(FilePath) then
    TFile.Copy(FilePath, BakPath, True);
end;

function TEditorTool.DoView(const P: TEditorParams): TJSONObject;
var
  Lines:     TStringList;
  Enc:       TEncoding;
  Start:     Integer;
  Count:     Integer;
  I:         Integer;
  SB:        TStringBuilder;
  Total:     Integer;
begin
  if P.Path = '' then raise Exception.Create('"path" is required for view');
  if not TFile.Exists(P.Path) then
    raise Exception.CreateFmt('File not found: %s', [P.Path]);

  Enc   := ResolveEncoding(P.Encoding);
  Lines := TStringList.Create;
  SB    := TStringBuilder.Create;
  try
    Lines.LoadFromFile(P.Path, Enc);
    Total := Lines.Count;

    Start := P.Offset;
    if Start < 1 then Start := 1;
    Start := Min(Start, Total + 1);

    Count := P.Limit;
    if Count <= 0 then
      Count := Total - Start + 1
    else
      Count := Min(Count, Total - Start + 1);

    for I := Start - 1 to Start - 1 + Count - 1 do
    begin
      SB.AppendFormat('%4d  %s', [I + 1, Lines[I]]);
      SB.Append(#10);
    end;

    Result := TJSONObject.Create;
    Result.AddPair('ok',          TJSONTrue.Create);
    Result.AddPair('path',        P.Path);
    Result.AddPair('content',     SB.ToString);
    Result.AddPair('lines_shown', TJSONNumber.Create(Count));
    Result.AddPair('total_lines', TJSONNumber.Create(Total));
  finally
    Lines.Free;
    SB.Free;
  end;
end;

function TEditorTool.DoApplyDiff(const P: TEditorParams): TJSONObject;
var
  Enc:          TEncoding;
  Original:     string;
  NewContent:   string;
  ErrorMsg:     string;
  Applier:      TDiffApplier;
  Parser:       TDiffParser;
  Hunks:        TList<TDiffHunk>;
  H:            TDiffHunk;
  LinesBefore:  Integer;
  LinesAfter:   Integer;
  HunkCount:    Integer;
  LinesBuf:     TStringList;
begin
  if P.Path = '' then raise Exception.Create('"path" is required for apply_diff');
  if P.Diff = '' then raise Exception.Create('"diff" is required for apply_diff');
  if not TFile.Exists(P.Path) then
    raise Exception.CreateFmt('File not found: %s', [P.Path]);

  Enc      := ResolveEncoding(P.Encoding);
  Original := TFile.ReadAllText(P.Path, Enc);

  // Count lines before
  LinesBuf := TStringList.Create;
  try
    LinesBuf.Text := Original;
    LinesBefore   := LinesBuf.Count;
  finally
    LinesBuf.Free;
  end;

  // Count hunks for reporting
  Parser := TDiffParser.Create;
  try
    Hunks := Parser.Parse(P.Diff);
    try
      HunkCount := Hunks.Count;
    finally
      for H in Hunks do H.Free;
      Hunks.Free;
    end;
  finally
    Parser.Free;
  end;

  if P.Backup then SaveBackup(P.Path);

  Applier := TDiffApplier.Create;
  try
    if not Applier.Apply(Original, P.Diff, NewContent, ErrorMsg) then
      raise Exception.Create('Diff apply failed: ' + ErrorMsg);
  finally
    Applier.Free;
  end;

  TFile.WriteAllText(P.Path, NewContent, Enc);

  // Count lines after
  LinesBuf := TStringList.Create;
  try
    LinesBuf.Text := NewContent;
    LinesAfter    := LinesBuf.Count;
  finally
    LinesBuf.Free;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('ok',           TJSONTrue.Create);
  Result.AddPair('path',         P.Path);
  Result.AddPair('hunks_applied',TJSONNumber.Create(HunkCount));
  Result.AddPair('lines_before', TJSONNumber.Create(LinesBefore));
  Result.AddPair('lines_after',  TJSONNumber.Create(LinesAfter));
end;

function TEditorTool.DoReplace(const P: TEditorParams): TJSONObject;
var
  Enc:          TEncoding;
  Original:     string;
  NewContent:   string;
  Replacements: Integer;
  SearchPos:    Integer;
  OldLen:       Integer;
begin
  if P.Path   = '' then raise Exception.Create('"path" is required for replace');
  if P.Oldstr = '' then raise Exception.Create('"oldstr" is required for replace');
  if not TFile.Exists(P.Path) then
    raise Exception.CreateFmt('File not found: %s', [P.Path]);

  Enc      := ResolveEncoding(P.Encoding);
  Original := TFile.ReadAllText(P.Path, Enc);

  // Count occurrences first
  Replacements := 0;
  OldLen       := Length(P.Oldstr);
  SearchPos    := Pos(P.Oldstr, Original);
  while SearchPos > 0 do
  begin
    Inc(Replacements);
    SearchPos := PosEx(P.Oldstr, Original, SearchPos + OldLen);
  end;

  if Replacements = 0 then
    raise Exception.Create('old_string not found in file');

  if P.Backup then SaveBackup(P.Path);

  NewContent := StringReplace(Original, P.Oldstr, P.Newstr, [rfReplaceAll]);
  TFile.WriteAllText(P.Path, NewContent, Enc);

  Result := TJSONObject.Create;
  Result.AddPair('ok',           TJSONTrue.Create);
  Result.AddPair('path',         P.Path);
  Result.AddPair('replacements', TJSONNumber.Create(Replacements));
end;

function TEditorTool.DoReplaceLines(const P: TEditorParams): TJSONObject;
var
  Enc:        TEncoding;
  Lines:      TStringList;
  NewLines:   TStringList;
  I:          Integer;
  StartIdx:   Integer;
  EndIdx:     Integer;
  LinesRemoved: Integer;
  LinesAdded:   Integer;
begin
  if P.Path     = ''  then raise Exception.Create('"path" is required for replace_lines');
  if P.Fromline <= 0  then raise Exception.Create('"fromline" is required for replace_lines');
  if P.Toline   <= 0  then raise Exception.Create('"toline" is required for replace_lines');
  if P.Fromline > P.Toline then
    raise Exception.Create('"fromline" must be <= "toline"');
  if not TFile.Exists(P.Path) then
    raise Exception.CreateFmt('File not found: %s', [P.Path]);

  Enc   := ResolveEncoding(P.Encoding);
  Lines := TStringList.Create;
  try
    Lines.LoadFromFile(P.Path, Enc);

    StartIdx := P.Fromline - 1;
    EndIdx   := P.Toline   - 1;

    if StartIdx >= Lines.Count then
      raise Exception.CreateFmt('start_line %d exceeds file length (%d lines)', [P.Fromline, Lines.Count]);
    EndIdx := Min(EndIdx, Lines.Count - 1);

    LinesRemoved := EndIdx - StartIdx + 1;

    if P.Backup then SaveBackup(P.Path);

    // Remove old lines
    for I := 0 to LinesRemoved - 1 do
      Lines.Delete(StartIdx);

    // Insert new content lines
    NewLines := TStringList.Create;
    try
      NewLines.Text := P.Content;
      // TStringList.Text adds a trailing empty — trim it if Content didn't end with newline
      if (NewLines.Count > 0) and (NewLines[NewLines.Count - 1] = '') and
         not P.Content.EndsWith(#10) and not P.Content.EndsWith(#13) then
        NewLines.Delete(NewLines.Count - 1);

      LinesAdded := NewLines.Count;
      for I := NewLines.Count - 1 downto 0 do
        Lines.Insert(StartIdx, NewLines[I]);
    finally
      NewLines.Free;
    end;

    Lines.SaveToFile(P.Path, Enc);
  finally
    Lines.Free;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('ok',           TJSONTrue.Create);
  Result.AddPair('path',         P.Path);
  Result.AddPair('fromline',     TJSONNumber.Create(P.Fromline));
  Result.AddPair('toline',       TJSONNumber.Create(P.Toline));
  Result.AddPair('lines_removed',TJSONNumber.Create(LinesRemoved));
  Result.AddPair('lines_added',  TJSONNumber.Create(LinesAdded));
end;

function TEditorTool.DoInsertLines(const P: TEditorParams): TJSONObject;
var
  Enc:          TEncoding;
  Lines:        TStringList;
  NewLines:     TStringList;
  I:            Integer;
  InsertAt:     Integer;
  LinesInserted: Integer;
begin
  if P.Path = '' then raise Exception.Create('"path" is required for insert_lines');
  if not TFile.Exists(P.Path) then
    raise Exception.CreateFmt('File not found: %s', [P.Path]);

  Enc   := ResolveEncoding(P.Encoding);
  Lines := TStringList.Create;
  try
    Lines.LoadFromFile(P.Path, Enc);

    // Line=0 → append at end; Line=N → insert before line N
    if P.Line <= 0 then
      InsertAt := Lines.Count
    else
      InsertAt := Min(P.Line - 1, Lines.Count);

    if P.Backup then SaveBackup(P.Path);

    NewLines := TStringList.Create;
    try
      NewLines.Text := P.Content;
      if (NewLines.Count > 0) and (NewLines[NewLines.Count - 1] = '') and
         not P.Content.EndsWith(#10) and not P.Content.EndsWith(#13) then
        NewLines.Delete(NewLines.Count - 1);

      LinesInserted := NewLines.Count;
      for I := NewLines.Count - 1 downto 0 do
        Lines.Insert(InsertAt, NewLines[I]);
    finally
      NewLines.Free;
    end;

    Lines.SaveToFile(P.Path, Enc);
  finally
    Lines.Free;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('ok',             TJSONTrue.Create);
  Result.AddPair('path',           P.Path);
  Result.AddPair('inserted_at',    TJSONNumber.Create(InsertAt + 1));
  Result.AddPair('lines_inserted', TJSONNumber.Create(LinesInserted));
end;

function TEditorTool.ExecuteWithParams(const AParams: TEditorParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op: string;
  R:  TJSONObject;
begin
  try
    Op := LowerCase(Trim(AParams.Operation));
    if Op = '' then raise Exception.Create('"operation" is required');

    if      Op = 'view'          then R := DoView(AParams)
    else if Op = 'apply_diff'    then R := DoApplyDiff(AParams)
    else if Op = 'replace'       then R := DoReplace(AParams)
    else if Op = 'replace_lines' then R := DoReplaceLines(AParams)
    else if Op = 'insert_lines'  then R := DoInsertLines(AParams)
    else raise Exception.CreateFmt('Unknown operation "%s". Valid: view,apply_diff,replace,replace_lines,insert_lines', [Op]);

    Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
    R.Free;
  except
    on E: Exception do
      Result := TAiMCPResponseBuilder.New
        .AddText('{"ok":false,"error":"' +
          E.Message.Replace('\','\\').Replace('"','\"')
                   .Replace(#10,'\n').Replace(#13,'') + '"}')
        .Build;
  end;
end;

constructor TEditorTool.Create;
begin
  inherited;
  FName        := 'mcp-diffeditor';
  FDescription :=
    'File editor with diff support. Edit files precisely: apply unified diffs, replace text, edit line ranges.' + #10 +
    'ALWAYS include "operation" in every call. Use absolute paths. Call "view" first to see line numbers before editing.' + #10 +
    '' + #10 +
    'OPERATIONS (required params listed after each name):' + #10 +
    '  view          — path. Optional: offset (start line, 1-based), limit (line count). Returns content with line numbers. Use this BEFORE editing.' + #10 +
    '                  Example: {"operation":"view","path":"C:/src/main.pas","offset":1,"limit":50}' + #10 +
    '  apply_diff    — path, diff (unified diff text). Optional: backup (save .bak first, default false), encoding.' + #10 +
    '                  The diff engine uses fuzzy matching (+/-20 lines) — line numbers in @@ headers do not need to be exact.' + #10 +
    '                  Diff format: lines starting with " " (context), "+" (add), "-" (remove). @@ header is optional but recommended.' + #10 +
    '                  Example: {"operation":"apply_diff","path":"C:/src/main.pas","diff":"@@ -10,5 +10,5 @@\n context line\n-old line\n+new line\n context line","backup":true}' + #10 +
    '  replace       — path, oldstr, newstr. Replaces ALL occurrences of oldstr. Fails if oldstr not found. Optional: backup, encoding.' + #10 +
    '                  Example: {"operation":"replace","path":"C:/src/main.pas","oldstr":"foo := 1;","newstr":"foo := 2;"}' + #10 +
    '  replace_lines — path, fromline, toline, content. Replaces line range with new content. Optional: backup, encoding.' + #10 +
    '                  Example: {"operation":"replace_lines","path":"C:/src/main.pas","fromline":10,"toline":12,"content":"new line 1\nnew line 2\n"}' + #10 +
    '  insert_lines  — path, content. Optional: line (insert BEFORE this line; 0 = append at end), backup, encoding.' + #10 +
    '                  Example: {"operation":"insert_lines","path":"C:/src/main.pas","line":5,"content":"// inserted comment\n"}';
end;

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-diffeditor',
    function: IAiMCPTool
    begin
      Result := TEditorTool.Create;
    end);
  WriteLn(ErrOutput, '[MCPService]   + mcp-editor');
end;

end.
