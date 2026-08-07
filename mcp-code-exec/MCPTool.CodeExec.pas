unit MCPTool.CodeExec;

(*
  MCPTool.CodeExec  Â·  mcp-code-exec  (port 8651)
  Execute code snippets in various languages via subprocesses.

  Operations:
    run_python        - execute Python code via python runtime
    run_javascript    - execute JavaScript code via Node.js
    run_bash          - execute shell script via cmd.exe /c (.bat)
    run_powershell    - execute PowerShell script via powershell.exe
    run_sql           - execute SQL against SQLite via sqlite3 CLI
    eval_expression   - evaluate a mathematical/Python expression
    list_runtimes     - check which runtimes are available (python, node, powershell, sqlite3)
*)

interface

uses
  uMakerAi.MCPServer.Core,
  System.JSON;

type
  TCodeExecParams = class
  private
    FOperation    : string;
    FCode         : string;
    FArgs         : string;
    FTimeoutSec   : Integer;
    FDatabasePath : string;
    FWorkDir      : string;
  public
    constructor Create;

    [AiMCPSchemaDescription('Operation: run_python, run_javascript, run_bash, run_powershell, run_sql, eval_expression, list_runtimes')]
    property Operation    : string  read FOperation    write FOperation;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Source code or SQL to execute')]
    property Code         : string  read FCode         write FCode;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Command-line arguments string appended after the temp file (run_python only)')]
    property Args         : string  read FArgs         write FArgs;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Execution timeout in seconds (default: 30)')]
    property TimeoutSec   : Integer read FTimeoutSec   write FTimeoutSec;

    [AiMCPOptional]
    [AiMCPSchemaDescription('SQLite database file path for run_sql (default: in-memory scratch file)')]
    property DatabasePath : string  read FDatabasePath write FDatabasePath;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Working directory for the spawned process')]
    property WorkDir      : string  read FWorkDir      write FWorkDir;
  end;

  TCodeExecTool = class(TAiMCPToolBase<TCodeExecParams>)
  private
    function RunCmd(const Cmd: string; TimeoutSec: Integer;
      const WorkDir: string): TJSONObject;

    function DoRunPython(const P: TCodeExecParams): TJSONObject;
    function DoRunJavaScript(const P: TCodeExecParams): TJSONObject;
    function DoRunBash(const P: TCodeExecParams): TJSONObject;
    function DoRunPowerShell(const P: TCodeExecParams): TJSONObject;
    function DoRunSQL(const P: TCodeExecParams): TJSONObject;
    function DoEvalExpression(const P: TCodeExecParams): TJSONObject;
    function DoListRuntimes(const P: TCodeExecParams): TJSONObject;
  protected
    function ExecuteWithParams(const AParams: TCodeExecParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

procedure RegisterTools(AServer: TAiMCPServer);

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  MCPTool.ProcRunner;

{ TCodeExecParams }

constructor TCodeExecParams.Create;
begin
  inherited;
  FTimeoutSec := 30;
end;

{ TCodeExecTool }

constructor TCodeExecTool.Create;
begin
  inherited;
  FName        := 'mcp-code-exec';
  FDescription :=
    'Execute code snippets in various languages by spawning subprocesses. ' +
    'Operations: run_python (code, args?, timeoutSec?), ' +
    'run_javascript (code, timeoutSec?), ' +
    'run_bash (code â€” written to .bat and run via cmd.exe /c, timeoutSec?), ' +
    'run_powershell (code, timeoutSec?), ' +
    'run_sql (code=SQL, databasePath?, timeoutSec?), ' +
    'eval_expression (code=expression, timeoutSec?), ' +
    'list_runtimes (no params â€” checks python, node, powershell, sqlite3). ' +
    'Temp files are deleted after each run. ' +
    'Requires runtimes installed and in PATH.';
end;

function TCodeExecTool.RunCmd(const Cmd: string; TimeoutSec: Integer;
  const WorkDir: string): TJSONObject;
var
  Output:   string;
  ExitCode: Integer;
  TimedOut: Boolean;
  TOut:     Integer;
begin
  TOut := TimeoutSec;
  if TOut <= 0 then TOut := 30;   // ejecutar codigo ajeno: timeout corto

  if not RunCaptured(Cmd, Trim(WorkDir), TOut, Output, ExitCode, TimedOut) then
    raise Exception.Create('Failed to run command: ' + SysErrorMessage(GetLastError));

  Result := TJSONObject.Create;
  Result.AddPair('output',    Output.Trim);
  Result.AddPair('exit_code', TJSONNumber.Create(ExitCode));
  Result.AddPair('ok',        TJSONBool.Create(ExitCode = 0));
  if TimedOut then
    Result.AddPair('timeout', TJSONBool.Create(True));
end;

function TCodeExecTool.DoRunPython(const P: TCodeExecParams): TJSONObject;
var
  TmpFile: string;
  Cmd:     string;
  TimeOut: Integer;
begin
  if Trim(P.Code) = '' then
    raise Exception.Create('"code" is required for run_python');

  TmpFile := TPath.Combine(TPath.GetTempPath, 'mcp_exec_' + IntToStr(TThread.GetTickCount) + '.py');
  TimeOut  := P.TimeoutSec;
  if TimeOut <= 0 then TimeOut := 30;

  // Sin BOM (GetBytes no lo emite, SaveToFile si): sh no lo tolera.
  TFile.WriteAllBytes(TmpFile, TEncoding.UTF8.GetBytes(P.Code));

  try
    Cmd := 'python "' + TmpFile + '"';
    if Trim(P.Args) <> '' then
      Cmd := Cmd + ' ' + Trim(P.Args);
    Result := RunCmd(Cmd, TimeOut, Trim(P.WorkDir));
    Result.AddPair('language', 'python');
  finally
    if TFile.Exists(TmpFile) then
      TFile.Delete(TmpFile);
  end;
end;

function TCodeExecTool.DoRunJavaScript(const P: TCodeExecParams): TJSONObject;
var
  TmpFile: string;
  TimeOut: Integer;
begin
  if Trim(P.Code) = '' then
    raise Exception.Create('"code" is required for run_javascript');

  TmpFile := TPath.Combine(TPath.GetTempPath, 'mcp_exec_' + IntToStr(TThread.GetTickCount) + '.js');
  TimeOut  := P.TimeoutSec;
  if TimeOut <= 0 then TimeOut := 30;

  // Sin BOM (GetBytes no lo emite, SaveToFile si): sh no lo tolera.
  TFile.WriteAllBytes(TmpFile, TEncoding.UTF8.GetBytes(P.Code));

  try
    Result := RunCmd('node "' + TmpFile + '"', TimeOut, Trim(P.WorkDir));
    Result.AddPair('language', 'javascript');
  finally
    if TFile.Exists(TmpFile) then
      TFile.Delete(TmpFile);
  end;
end;

function TCodeExecTool.DoRunBash(const P: TCodeExecParams): TJSONObject;
var
  TmpFile: string;
  TimeOut: Integer;
begin
  if Trim(P.Code) = '' then
    raise Exception.Create('"code" is required for run_bash');

  // En Windows el script va a .bat (lo ejecuta cmd.exe); en POSIX a .sh
  // invocado explicitamente con sh, para no depender del bit de ejecucion.
{$IFDEF MSWINDOWS}
  TmpFile := TPath.Combine(TPath.GetTempPath, 'mcp_exec_' + IntToStr(TThread.GetTickCount) + '.bat');
{$ELSE}
  TmpFile := TPath.Combine(TPath.GetTempPath, 'mcp_exec_' + IntToStr(TThread.GetTickCount) + '.sh');
{$ENDIF}
  TimeOut  := P.TimeoutSec;
  if TimeOut <= 0 then TimeOut := 30;

  // Sin BOM (GetBytes no lo emite, SaveToFile si): sh no lo tolera.
  TFile.WriteAllBytes(TmpFile, TEncoding.UTF8.GetBytes(P.Code));

  try
{$IFDEF MSWINDOWS}
    Result := RunCmd('"' + TmpFile + '"', TimeOut, Trim(P.WorkDir));
{$ELSE}
    Result := RunCmd('sh "' + TmpFile + '"', TimeOut, Trim(P.WorkDir));
{$ENDIF}
    Result.AddPair('language', 'bash');
  finally
    if TFile.Exists(TmpFile) then
      TFile.Delete(TmpFile);
  end;
end;

function TCodeExecTool.DoRunPowerShell(const P: TCodeExecParams): TJSONObject;
var
  TmpFile: string;
  TimeOut: Integer;
begin
  if Trim(P.Code) = '' then
    raise Exception.Create('"code" is required for run_powershell');

  TmpFile := TPath.Combine(TPath.GetTempPath, 'mcp_exec_' + IntToStr(TThread.GetTickCount) + '.ps1');
  TimeOut  := P.TimeoutSec;
  if TimeOut <= 0 then TimeOut := 30;

  // Sin BOM (GetBytes no lo emite, SaveToFile si): sh no lo tolera.
  TFile.WriteAllBytes(TmpFile, TEncoding.UTF8.GetBytes(P.Code));

  try
    Result := RunCmd(
      'powershell -ExecutionPolicy Bypass -File "' + TmpFile + '"',
      TimeOut, Trim(P.WorkDir));
    Result.AddPair('language', 'powershell');
  finally
    if TFile.Exists(TmpFile) then
      TFile.Delete(TmpFile);
  end;
end;

function TCodeExecTool.DoRunSQL(const P: TCodeExecParams): TJSONObject;
var
  TmpFile:  string;
  DbPath:   string;
  TimeOut:  Integer;
  TmpDb:    string;
  UseTmpDb: Boolean;
begin
  if Trim(P.Code) = '' then
    raise Exception.Create('"code" is required for run_sql');

  TmpFile  := TPath.Combine(TPath.GetTempPath, 'mcp_exec_' + IntToStr(TThread.GetTickCount) + '.sql');
  TimeOut  := P.TimeoutSec;
  if TimeOut <= 0 then TimeOut := 30;

  DbPath   := Trim(P.DatabasePath);
  TmpDb    := '';
  UseTmpDb := False;

  if DbPath = '' then
  begin
    TmpDb    := TPath.Combine(TPath.GetTempPath, 'mcp_exec_' + IntToStr(TThread.GetTickCount) + '.db');
    DbPath   := TmpDb;
    UseTmpDb := True;
  end;

  // Sin BOM (GetBytes no lo emite, SaveToFile si): sh no lo tolera.
  TFile.WriteAllBytes(TmpFile, TEncoding.UTF8.GetBytes(P.Code));

  try
    Result := RunCmd(
      'sqlite3 "' + DbPath + '" ".read ' + TmpFile + '"',
      TimeOut, Trim(P.WorkDir));
    Result.AddPair('language', 'sql');
  finally
    if TFile.Exists(TmpFile) then
      TFile.Delete(TmpFile);
    if UseTmpDb and TFile.Exists(TmpDb) then
      TFile.Delete(TmpDb);
  end;
end;

function TCodeExecTool.DoEvalExpression(const P: TCodeExecParams): TJSONObject;
var
  TmpFile:  string;
  TimeOut:  Integer;
  PyCode:   string;
  Expr:     string;
begin
  if Trim(P.Code) = '' then
    raise Exception.Create('"code" is required for eval_expression');

  TmpFile := TPath.Combine(TPath.GetTempPath, 'mcp_exec_' + IntToStr(TThread.GetTickCount) + '.py');
  TimeOut  := P.TimeoutSec;
  if TimeOut <= 0 then TimeOut := 30;

  Expr := Trim(P.Code);

  (* If the expression contains newlines or "import"/"print", run as-is;
     otherwise wrap in print(eval(...)) for simple arithmetic expressions *)
  if (Pos(#10, Expr) > 0) or (Pos('import', LowerCase(Expr)) > 0)
    or (Pos('print(', LowerCase(Expr)) > 0) then
    PyCode := Expr
  else
    PyCode := 'print(eval("' + Expr.Replace('\','\\').Replace('"','\"') + '"))';

  TFile.WriteAllBytes(TmpFile, TEncoding.UTF8.GetBytes(PyCode));

  try
    Result := RunCmd('python "' + TmpFile + '"', TimeOut, Trim(P.WorkDir));
    Result.AddPair('language', 'python');
    Result.AddPair('expression', Expr);
  finally
    if TFile.Exists(TmpFile) then
      TFile.Delete(TmpFile);
  end;
end;

function TCodeExecTool.DoListRuntimes(const P: TCodeExecParams): TJSONObject;
var
  R:          TJSONObject;
  Available:  TJSONObject;
  Ver:        TJSONObject;
  TimeOut:    Integer;

  function GetVersion(const Cmd: string): string;
  var
    VR: TJSONObject;
    S:  string;
  begin
    Result := '';
    try
      VR := RunCmd(Cmd, 10, '');
      try
        S := Trim(VR.GetValue<string>('output'));
        if (VR.GetValue<Integer>('exit_code') = 0) and (S <> '') then
          Result := S;
      finally
        VR.Free;
      end;
    except
      Result := '';
    end;
  end;

var
  PyVer, NodeVer, PsVer, SqlVer: string;
begin
  TimeOut := P.TimeoutSec;
  if TimeOut <= 0 then TimeOut := 30;

  PyVer   := GetVersion('python --version');
  NodeVer := GetVersion('node --version');
  PsVer   := GetVersion('powershell -NoProfile -Command "$PSVersionTable.PSVersion.ToString()"');
  SqlVer  := GetVersion('sqlite3 --version');

  Available := TJSONObject.Create;

  if PyVer <> '' then
    Available.AddPair('python', PyVer)
  else
    Available.AddPair('python', 'not found');

  if NodeVer <> '' then
    Available.AddPair('node', NodeVer)
  else
    Available.AddPair('node', 'not found');

  if PsVer <> '' then
    Available.AddPair('powershell', PsVer)
  else
    Available.AddPair('powershell', 'not found');

  if SqlVer <> '' then
    Available.AddPair('sqlite3', SqlVer)
  else
    Available.AddPair('sqlite3', 'not found');

  R := TJSONObject.Create;
  R.AddPair('ok',        TJSONBool.Create(True));
  R.AddPair('available', Available);
  Result := R;
end;

function TCodeExecTool.ExecuteWithParams(const AParams: TCodeExecParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op: string;
  R:  TJSONObject;
begin
  try
    Op := LowerCase(Trim(AParams.Operation));
    if Op = '' then
      raise Exception.Create('"operation" is required');

    if      Op = 'run_python'       then R := DoRunPython(AParams)
    else if Op = 'run_javascript'   then R := DoRunJavaScript(AParams)
    else if Op = 'run_bash'         then R := DoRunBash(AParams)
    else if Op = 'run_powershell'   then R := DoRunPowerShell(AParams)
    else if Op = 'run_sql'          then R := DoRunSQL(AParams)
    else if Op = 'eval_expression'  then R := DoEvalExpression(AParams)
    else if Op = 'list_runtimes'    then R := DoListRuntimes(AParams)
    else raise Exception.CreateFmt('Unknown operation "%s"', [Op]);

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

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-code-exec',
    function: IAiMCPTool
    begin
      Result := TCodeExecTool.Create;
    end);
  WriteLn(ErrOutput, '[MCPService]   + mcp-code-exec');
end;

end.
