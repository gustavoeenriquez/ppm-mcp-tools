unit MCPTool.Diff;

(*
  MCPTool.Diff
  MCP tool: mcp-diff

  Apply unified diffs to files and parse diff structure.
  Uses uMakerAi.Utils.DiffUpdater (TDiffParser + TDiffApplier) — pure RTL, no FMX.

  Operations:
    apply  - apply a unified diff to a file; write result to outputPath (default: overwrite source)
    parse  - parse a unified diff and return its hunk structure as JSON

  The "diff" parameter must be a unified diff string (--- / +++ / @@ headers).
*)

interface

uses
  uMakerAi.MCPServer.Core,
  uMakerAi.Utils.DiffUpdater,
  System.SysUtils,
  System.JSON,
  System.Classes,
  System.IOUtils,
  System.Generics.Collections;

type

  // ── Parameters ──────────────────────────────────────────────────────────────

  TDiffParams = class
  private
    FOperation:  string;
    FFilePath:   string;
    FDiff:       string;
    FOutputPath: string;
  public
    [AiMCPSchemaDescription('Operation: apply, parse')]
    property Operation:  string read FOperation  write FOperation;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Path to the source file to patch (required for apply)')]
    property FilePath:   string read FFilePath   write FFilePath;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Unified diff string to apply or parse')]
    property Diff:       string read FDiff       write FDiff;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Output file path for apply (omit to overwrite source file)')]
    property OutputPath: string read FOutputPath write FOutputPath;
  end;

  // ── Tool ────────────────────────────────────────────────────────────────────

  TDiffTool = class(TAiMCPToolBase<TDiffParams>)
  private
    function OpApply(const P: TDiffParams): TJSONObject;
    function OpParse(const P: TDiffParams): TJSONObject;
  protected
    function ExecuteWithParams(const AParams: TDiffParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

procedure RegisterTools(AServer: TAiMCPServer);

implementation

// ── Operations ───────────────────────────────────────────────────────────────

function TDiffTool.OpApply(const P: TDiffParams): TJSONObject;
var
  Applier:    TDiffApplier;
  Original:   string;
  NewContent: string;
  ErrorMsg:   string;
  OutPath:    string;
  LinesIn:    Integer;
  LinesOut:   Integer;
  SL:         TStringList;
begin
  if P.FilePath = '' then
    raise Exception.Create('"filePath" is required for apply');
  if P.Diff = '' then
    raise Exception.Create('"diff" is required for apply');
  if not TFile.Exists(P.FilePath) then
    raise Exception.CreateFmt('File not found: %s', [P.FilePath]);

  Original := TFile.ReadAllText(P.FilePath, TEncoding.UTF8);

  SL := TStringList.Create;
  try
    SL.Text := Original;
    LinesIn := SL.Count;
  finally
    SL.Free;
  end;

  Applier := TDiffApplier.Create;
  try
    if not Applier.Apply(Original, P.Diff, NewContent, ErrorMsg) then
      raise Exception.Create('Diff apply failed: ' + ErrorMsg);
  finally
    Applier.Free;
  end;

  OutPath := P.OutputPath;
  if OutPath = '' then
    OutPath := P.FilePath;

  TDirectory.CreateDirectory(ExtractFilePath(OutPath));
  TFile.WriteAllText(OutPath, NewContent, TEncoding.UTF8);

  SL := TStringList.Create;
  try
    SL.Text := NewContent;
    LinesOut := SL.Count;
  finally
    SL.Free;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('output',      OutPath);
  Result.AddPair('lines_before', TJSONNumber.Create(LinesIn));
  Result.AddPair('lines_after',  TJSONNumber.Create(LinesOut));
  Result.AddPair('size_bytes',   TJSONNumber.Create(TFile.GetSize(OutPath)));
end;

function TDiffTool.OpParse(const P: TDiffParams): TJSONObject;
var
  Parser:    TDiffParser;
  Hunks:     TList<TDiffHunk>;
  HunkArr:   TJSONArray;
  HunkObj:   TJSONObject;
  LineArr:   TJSONArray;
  LineObj:   TJSONObject;
  Hunk:      TDiffHunk;
  DL:        TDiffLine;
  i:         Integer;
  OpStr:     string;
  Added:     Integer;
  Deleted:   Integer;
  Context:   Integer;
begin
  if P.Diff = '' then
    raise Exception.Create('"diff" is required for parse');

  Parser := TDiffParser.Create;
  try
    Hunks := Parser.Parse(P.Diff);
    try
      HunkArr := TJSONArray.Create;
      for i := 0 to Hunks.Count - 1 do
      begin
        Hunk := Hunks[i];
        Added   := 0;
        Deleted := 0;
        Context := 0;

        LineArr := TJSONArray.Create;
        for DL in Hunk.Lines do
        begin
          case DL.Operation of
            doAdd:     begin OpStr := '+'; Inc(Added);   end;
            doDelete:  begin OpStr := '-'; Inc(Deleted); end;
          else
            begin OpStr := ' '; Inc(Context); end;
          end;
          LineObj := TJSONObject.Create;
          LineObj.AddPair('op',      OpStr);
          LineObj.AddPair('content', DL.Content);
          LineArr.AddElement(LineObj);
        end;

        HunkObj := TJSONObject.Create;
        HunkObj.AddPair('original_start', TJSONNumber.Create(Hunk.OriginalStart));
        HunkObj.AddPair('original_count', TJSONNumber.Create(Hunk.OriginalCount));
        HunkObj.AddPair('new_start',      TJSONNumber.Create(Hunk.NewStart));
        HunkObj.AddPair('new_count',      TJSONNumber.Create(Hunk.NewCount));
        HunkObj.AddPair('lines_added',    TJSONNumber.Create(Added));
        HunkObj.AddPair('lines_deleted',  TJSONNumber.Create(Deleted));
        HunkObj.AddPair('lines_context',  TJSONNumber.Create(Context));
        HunkObj.AddPair('lines',          LineArr);
        HunkArr.AddElement(HunkObj);
      end;
    finally
      for i := 0 to Hunks.Count - 1 do
        Hunks[i].Free;
      Hunks.Free;
    end;
  finally
    Parser.Free;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('hunk_count', TJSONNumber.Create(HunkArr.Count));
  Result.AddPair('hunks',      HunkArr);
end;

// ── Main dispatch ────────────────────────────────────────────────────────────

function TDiffTool.ExecuteWithParams(const AParams: TDiffParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op:   string;
  Data: TJSONObject;
begin
  try
    Op := LowerCase(Trim(AParams.Operation));

    if      Op = 'apply' then Data := OpApply(AParams)
    else if Op = 'parse' then Data := OpParse(AParams)
    else raise Exception.CreateFmt(
      'Unknown operation: "%s". Valid: apply, parse', [Op]);

    Result := TAiMCPResponseBuilder.New.AddText(Data.ToJSON).Build;
    Data.Free;

  except
    on E: Exception do
      Result := TAiMCPResponseBuilder.New
        .AddText('Error [mcp-diff]: ' + E.Message)
        .Build;
  end;
end;

constructor TDiffTool.Create;
begin
  inherited;
  FName        := 'mcp-diff';
  FDescription :=
    'Apply unified diffs to files and parse diff structure. Pure RTL implementation. ' +
    'apply: read filePath, apply diff patch, write result to outputPath (default: overwrite source). ' +
    'parse: parse diff string into hunk structure — returns hunk count, per-hunk line stats (added/deleted/context) and full line list. ' +
    'Diff format: standard unified diff (--- +++ @@ headers). Fuzzy matching handles ±20 line offset.';
end;

// ── Registration ─────────────────────────────────────────────────────────────

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-diff',
    function: IAiMCPTool
    begin
      Result := TDiffTool.Create;
    end);
  WriteLn(ErrOutput, '[mcp-diff] registered.');
end;

end.
