unit MCPTool.Git;

(*
  MCPTool.Git
  MCP tool: mcp-git

  Operations:
    status   - working tree status (porcelain format parsed to JSON)
    log      - commit history (hash, author, date, subject)
    diff     - show unstaged or staged changes (raw diff text)
    branches - list local and remote branches
    info     - repo summary: current branch, last commit, remotes

  The "path" parameter is the repository root directory.
  Requires git to be installed and available in PATH.
*)

interface

uses
  uMakerAi.MCPServer.Core,
  System.SysUtils,
  System.JSON,
  System.Classes,
  System.IOUtils,
  MCPTool.ProcRunner;

type

  // ── Parameters ─────────────────────────────────────────────────────────────

  TGitParams = class
  private
    FOperation: string;
    FPath:      string;
    FLimit:     Integer;
    FFileName:  string;
    FStaged:    Boolean;
  public
    [AiMCPSchemaDescription('Operation: status, log, diff, branches, info')]
    property Operation: string read FOperation write FOperation;

    [AiMCPSchemaDescription('Repository root directory path (required)')]
    property Path: string read FPath write FPath;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Maximum commits to return for log (default: 20)')]
    property Limit: Integer read FLimit write FLimit;

    [AiMCPOptional]
    [AiMCPSchemaDescription('File path to restrict diff to (optional)')]
    property FileName: string read FFileName write FFileName;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Show staged (cached) diff instead of unstaged (default: false)')]
    property Staged: Boolean read FStaged write FStaged;
  end;

  // ── Tool ───────────────────────────────────────────────────────────────────

  TGitTool = class(TAiMCPToolBase<TGitParams>)
  private
    function RunGit(const Args, RepoPath: string): string;
  protected
    function ExecuteWithParams(const AParams: TGitParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

procedure RegisterTools(AServer: TAiMCPServer);

implementation

// ── Process helper ───────────────────────────────────────────────────────────

function TGitTool.RunGit(const Args, RepoPath: string): string;
var
  Cmd:      string;
  Output:   string;
  ExitCode: Integer;
  TimedOut: Boolean;
begin
  Result := '';

  if RepoPath <> '' then
    Cmd := Format('git -C "%s" %s', [RepoPath, Args])
  else
    Cmd := 'git ' + Args;

  // 15 s era el WaitForSingleObject de la version Windows; se conserva.
  if not RunCaptured(Cmd, '', 15, Output, ExitCode, TimedOut) then
    Exit;

  Result := Trim(Output);
end;

// ── Main execution ──────────────────────────────────────────────────────────

function TGitTool.ExecuteWithParams(const AParams: TGitParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op:   string;
  Repo: string;
  R:    TJSONObject;
begin
  try
    Op   := LowerCase(Trim(AParams.Operation));
    Repo := AParams.Path;

    if Repo = '' then
      raise Exception.Create('"path" (repository directory) is required');

    // ── status ───────────────────────────────────────────────────────────
    if Op = 'status' then
    begin
      var Raw   := RunGit('status --porcelain', Repo);
      var Lines := TStringList.Create;
      try
        Lines.Text := Raw;
        var Files := TJSONArray.Create;
        for var i := 0 to Lines.Count - 1 do
        begin
          var Line := Lines[i];
          if Length(Line) >= 4 then
          begin
            var XY    := Copy(Line, 1, 2);
            var FName := Trim(Copy(Line, 4, MaxInt));
            var Entry := TJSONObject.Create;
            Entry.AddPair('status', Trim(XY));
            Entry.AddPair('file',   FName);
            Files.AddElement(Entry);
          end;
        end;
        var Branch  := RunGit('rev-parse --abbrev-ref HEAD', Repo);
        var IsClean := Files.Count = 0;

        R := TJSONObject.Create;
        R.AddPair('path',   Repo);
        R.AddPair('branch', Branch);
        R.AddPair('clean',  TJSONBool.Create(IsClean));
        R.AddPair('count',  TJSONNumber.Create(Files.Count));
        R.AddPair('files',  Files);
        Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
        R.Free;
      finally
        Lines.Free;
      end;
    end

    // ── log ──────────────────────────────────────────────────────────────
    else if Op = 'log' then
    begin
      var Lim := AParams.Limit;
      if Lim <= 0 then Lim := 20;

      var Raw := RunGit(
        Format('log --format=%%H%%n%%an%%n%%ae%%n%%ai%%n%%s -n %d', [Lim]),
        Repo);

      var Lines := TStringList.Create;
      try
        Lines.Text := Raw;
        var Commits := TJSONArray.Create;
        var i := 0;
        while i + 4 < Lines.Count do
        begin
          var C := TJSONObject.Create;
          C.AddPair('hash',    Lines[i]);
          C.AddPair('author',  Lines[i + 1]);
          C.AddPair('email',   Lines[i + 2]);
          C.AddPair('date',    Lines[i + 3]);
          C.AddPair('subject', Lines[i + 4]);
          Commits.AddElement(C);
          Inc(i, 5);
        end;

        R := TJSONObject.Create;
        R.AddPair('path',    Repo);
        R.AddPair('count',   TJSONNumber.Create(Commits.Count));
        R.AddPair('commits', Commits);
        Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
        R.Free;
      finally
        Lines.Free;
      end;
    end

    // ── diff ─────────────────────────────────────────────────────────────
    else if Op = 'diff' then
    begin
      var GitArgs := 'diff';
      if AParams.Staged then GitArgs := 'diff --cached';
      if AParams.FileName <> '' then
        GitArgs := GitArgs + Format(' -- "%s"', [AParams.FileName]);

      var DiffText := RunGit(GitArgs, Repo);
      R := TJSONObject.Create;
      R.AddPair('path',   Repo);
      R.AddPair('staged', TJSONBool.Create(AParams.Staged));
      R.AddPair('diff',   DiffText);
      R.AddPair('length', TJSONNumber.Create(Length(DiffText)));
      Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
      R.Free;
    end

    // ── branches ─────────────────────────────────────────────────────────
    else if Op = 'branches' then
    begin
      var Raw   := RunGit('branch -a', Repo);
      var Lines := TStringList.Create;
      try
        Lines.Text := Raw;
        var Branches := TJSONArray.Create;
        for var i := 0 to Lines.Count - 1 do
        begin
          var Line := Lines[i];
          if Trim(Line) = '' then Continue;
          var IsCurrent := (Length(Line) > 0) and (Line[1] = '*');
          var BName     := Trim(Line);
          if IsCurrent then BName := Trim(Copy(BName, 2, MaxInt));
          var IsRemote  := BName.StartsWith('remotes/');

          var B := TJSONObject.Create;
          B.AddPair('name',    BName);
          B.AddPair('current', TJSONBool.Create(IsCurrent));
          B.AddPair('remote',  TJSONBool.Create(IsRemote));
          Branches.AddElement(B);
        end;

        R := TJSONObject.Create;
        R.AddPair('path',     Repo);
        R.AddPair('count',    TJSONNumber.Create(Branches.Count));
        R.AddPair('branches', Branches);
        Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
        R.Free;
      finally
        Lines.Free;
      end;
    end

    // ── info ─────────────────────────────────────────────────────────────
    else if Op = 'info' then
    begin
      var Branch  := RunGit('rev-parse --abbrev-ref HEAD', Repo);
      var LastLog := RunGit('log -1 --format=%H%n%an%n%ae%n%ai%n%s', Repo);

      var LogLines   := TStringList.Create;
      var LastCommit := TJSONObject.Create;
      try
        LogLines.Text := LastLog;
        if LogLines.Count >= 5 then
        begin
          LastCommit.AddPair('hash',    LogLines[0]);
          LastCommit.AddPair('author',  LogLines[1]);
          LastCommit.AddPair('email',   LogLines[2]);
          LastCommit.AddPair('date',    LogLines[3]);
          LastCommit.AddPair('subject', LogLines[4]);
        end;
      finally
        LogLines.Free;
      end;

      var RemoteRaw   := RunGit('remote -v', Repo);
      var RemLines    := TStringList.Create;
      var RemotesSeen := TStringList.Create;
      var Remotes     := TJSONArray.Create;
      try
        RemLines.Text          := RemoteRaw;
        RemotesSeen.Sorted     := True;
        RemotesSeen.Duplicates := dupIgnore;
        for var i := 0 to RemLines.Count - 1 do
        begin
          var Line  := RemLines[i];
          var Parts := TStringList.Create;
          try
            Parts.Delimiter     := #9;
            Parts.DelimitedText := Line;
            if Parts.Count >= 2 then
            begin
              var RemName := Trim(Parts[0]);
              if RemotesSeen.IndexOf(RemName) < 0 then
              begin
                RemotesSeen.Add(RemName);
                var URL   := Trim(Parts[1]);
                var Paren := Pos(' (', URL);
                if Paren > 0 then URL := Trim(Copy(URL, 1, Paren - 1));
                var Rem := TJSONObject.Create;
                Rem.AddPair('name', RemName);
                Rem.AddPair('url',  URL);
                Remotes.AddElement(Rem);
              end;
            end;
          finally
            Parts.Free;
          end;
        end;
      finally
        RemLines.Free;
        RemotesSeen.Free;
      end;

      var TotalCommits := RunGit('rev-list --count HEAD', Repo);
      var CommitCount  := StrToIntDef(TotalCommits, 0);

      R := TJSONObject.Create;
      R.AddPair('path',         Repo);
      R.AddPair('branch',       Branch);
      R.AddPair('commit_count', TJSONNumber.Create(CommitCount));
      R.AddPair('last_commit',  LastCommit);
      R.AddPair('remotes',      Remotes);
      Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
      R.Free;
    end

    else
      raise Exception.CreateFmt(
        'Unknown operation: "%s". Valid: status, log, diff, branches, info', [Op]);

  except
    on E: Exception do
      Result := TAiMCPResponseBuilder.New
        .AddText('Error [mcp-git]: ' + E.Message)
        .Build;
  end;
end;

constructor TGitTool.Create;
begin
  inherited;
  FName        := 'mcp-git';
  FDescription :=
    'Git repository operations. Requires git in PATH. ' +
    'status: working tree status (modified/added/deleted/untracked files). ' +
    'log: commit history (hash, author, date, subject); limit controls max commits. ' +
    'diff: show unstaged or staged (staged=true) changes as raw diff text; ' +
    'fileName restricts diff to one file. ' +
    'branches: list local and remote branches. ' +
    'info: repo summary — current branch, last commit, remotes, total commit count.';
end;

// ── Registration ─────────────────────────────────────────────────────────────

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-git',
    function: IAiMCPTool
    begin
      Result := TGitTool.Create;
    end);
  WriteLn(ErrOutput, '[mcp-git] registered.');
end;

end.
