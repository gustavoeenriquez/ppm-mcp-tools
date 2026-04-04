// Nombre: Gustavo Enríquez
// Redes Sociales:
// - Email: gustavoeenriquez@gmail.com

// - Telegram: https://t.me/MakerAi_Suite_Delphi
// - Telegram: https://t.me/MakerAi_Delphi_Suite_English

// - LinkedIn: https://www.linkedin.com/in/gustavo-enriquez-3937654a/
// - Youtube: https://www.youtube.com/@cimamaker3945
// - GitHub: https://github.com/gustavoeenriquez/

unit MCPTool.Shell;

{
  MCPTool.Shell  ·  mcp-shell

  Execute shell commands and capture stdout/stderr/exit code.

  Shells supported:
    cmd        - Windows cmd.exe /c (default)
    powershell - powershell.exe -NoProfile -NonInteractive -Command
    bash       - bash.exe -c  (Git Bash, WSL bash, or any bash in PATH)

  Security note: this tool executes arbitrary commands on the host.
  Use only in trusted/authorized environments.

  Params:
    command    - command line to execute (required)
    shell      - cmd (default), powershell, bash
    workdir    - working directory (default: current dir)
    timeout_ms - max milliseconds to wait (default: 30000)
    stdin_data - text to send to the process stdin (optional)
}

interface

uses
  uMakerAi.MCPServer.Core,
  uMakerAi.Utils.System,
  System.SysUtils,
  System.JSON,
  System.Classes,
  System.Diagnostics,
{$IFDEF MSWINDOWS}
  Winapi.Windows;
{$ELSE}
  Posix.Unistd;
{$ENDIF}

type

  TShellParams = class
  private
    FCommand:   string;
    FShell:     string;
    FWorkDir:   string;
    FTimeoutMs: Integer;
    FStdinData: string;
  public
    [AiMCPSchemaDescription('Command line to execute')]
    property Command:   string  read FCommand   write FCommand;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Shell: cmd (default), powershell, bash')]
    property Shell:     string  read FShell     write FShell;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Working directory (default: service working directory)')]
    property WorkDir:   string  read FWorkDir   write FWorkDir;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Timeout in milliseconds (default: 30000)')]
    property TimeoutMs: Integer read FTimeoutMs write FTimeoutMs;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Text to write to stdin before execution')]
    property StdinData: string  read FStdinData write FStdinData;
  end;

  TShellTool = class(TAiMCPToolBase<TShellParams>)
  private
    function BuildCmdLine(const AShell, ACommand: string): string;
    function RunProcess(const ACmdLine, AWorkDir, AStdinData: string;
      ATimeoutMs: Integer;
      out AStdOut, AStdErr: string; out AExitCode: Integer): Boolean;
  protected
    function ExecuteWithParams(const AParams: TShellParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

procedure RegisterTools(AServer: TAiMCPServer);

implementation

function TShellTool.BuildCmdLine(const AShell, ACommand: string): string;
var
  S: string;
begin
  S := LowerCase(Trim(AShell));
{$IFDEF MSWINDOWS}
  if S = '' then S := 'cmd';
  if S = 'powershell' then
    Result := 'powershell.exe -NoProfile -NonInteractive -Command ' + ACommand
  else if S = 'bash' then
    Result := 'bash.exe -c "' + ACommand.Replace('"', '\"') + '"'
  else
    // chcp 65001: switch cmd.exe to UTF-8 codepage so Python and other tools
    // output UTF-8 bytes, which we then decode correctly below.
    Result := 'cmd.exe /c chcp 65001 > nul 2>&1 && ' + ACommand;
{$ELSE}
  if S = '' then S := 'sh';
  if S = 'bash' then
    Result := 'bash -c "' + ACommand.Replace('"', '\"') + '"'
  else
    Result := 'sh -c "' + ACommand.Replace('"', '\"') + '"';
{$ENDIF}
end;

function TShellTool.RunProcess(const ACmdLine, AWorkDir, AStdinData: string;
  ATimeoutMs: Integer;
  out AStdOut, AStdErr: string; out AExitCode: Integer): Boolean;
var
  Proc:      TInteractiveProcessInfo;
  Buf:       array[0..4095] of Byte;
  N:         Integer;
  SBOut, SBErr: TStringBuilder;
  StdinBytes, RawBytes: TBytes;
  SW:        TStopwatch;
begin
  Result    := False;
  AStdOut   := '';
  AStdErr   := '';
  AExitCode := -1;

  Proc := TUtilsSystem.StartInteractiveProcess(ACmdLine, AWorkDir, nil);
  if Proc = nil then
    raise Exception.Create('Failed to start process: ' + ACmdLine);
  try
    if AStdinData <> '' then
    begin
      StdinBytes := TEncoding.UTF8.GetBytes(AStdinData);
      Proc.WriteInput(StdinBytes[0], Length(StdinBytes));
    end;
    // Cerrar stdin para que el proceso reciba EOF y no quede esperando input
{$IFDEF MSWINDOWS}
    if Proc.PipeHandles.InputWrite <> 0 then
    begin
      CloseHandle(Proc.PipeHandles.InputWrite);
      Proc.PipeHandles.InputWrite := 0;
    end;
{$ELSE}
    if Proc.PipeHandles.InputWrite <> 0 then
    begin
      Posix.Unistd.__close(Proc.PipeHandles.InputWrite);
      Proc.PipeHandles.InputWrite := 0;
    end;
{$ENDIF}

    SBOut := TStringBuilder.Create;
    SBErr := TStringBuilder.Create;
    try
      SW := TStopwatch.StartNew;
      repeat
        N := Proc.ReadOutput(Buf[0], SizeOf(Buf));
        if N > 0 then begin SetLength(RawBytes, N); Move(Buf[0], RawBytes[0], N); SBOut.Append(TEncoding.UTF8.GetString(RawBytes)); end;
        N := Proc.ReadError(Buf[0], SizeOf(Buf));
        if N > 0 then begin SetLength(RawBytes, N); Move(Buf[0], RawBytes[0], N); SBErr.Append(TEncoding.UTF8.GetString(RawBytes)); end;
        if not Proc.IsRunning then Break;
        if SW.ElapsedMilliseconds > ATimeoutMs then
        begin
          Proc.Kill;
          AStdErr   := '[TIMEOUT after ' + ATimeoutMs.ToString + ' ms]';
          AExitCode := -1;
          Result    := True;
          Exit;
        end;
        Sleep(20);
      until False;
      // Drain remaining
      repeat
        N := Proc.ReadOutput(Buf[0], SizeOf(Buf));
        if N > 0 then begin SetLength(RawBytes, N); Move(Buf[0], RawBytes[0], N); SBOut.Append(TEncoding.UTF8.GetString(RawBytes)); end;
      until N <= 0;
      repeat
        N := Proc.ReadError(Buf[0], SizeOf(Buf));
        if N > 0 then begin SetLength(RawBytes, N); Move(Buf[0], RawBytes[0], N); SBErr.Append(TEncoding.UTF8.GetString(RawBytes)); end;
      until N <= 0;
      AStdOut   := SBOut.ToString;
      AStdErr   := SBErr.ToString;
      AExitCode := Proc.ExitCode;
      Result    := True;
    finally
      SBOut.Free;
      SBErr.Free;
    end;
  finally
    TUtilsSystem.StopInteractiveProcess(Proc);
  end;
end;

function TShellTool.ExecuteWithParams(const AParams: TShellParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  StdOut, StdErr: string;
  ExitCode: Integer;
begin
  try
    if AParams.Command = '' then
      raise Exception.Create('"command" is required');

    var CmdLine   := BuildCmdLine(AParams.Shell, AParams.Command);
    var Timeout   := AParams.TimeoutMs;
    if Timeout <= 0 then Timeout := 30000;

    RunProcess(CmdLine, AParams.WorkDir, AParams.StdinData, Timeout,
      StdOut, StdErr, ExitCode);

    var R := TJSONObject.Create;
    R.AddPair('exit_code', TJSONNumber.Create(ExitCode));
    R.AddPair('stdout',    StdOut);
    R.AddPair('stderr',    StdErr);
    R.AddPair('ok',        TJSONBool.Create(ExitCode = 0));
    Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
    R.Free;
  except
    on E: Exception do
      Result := TAiMCPResponseBuilder.New
        .AddText('Error [mcp-shell]: ' + E.Message)
        .Build;
  end;
end;

constructor TShellTool.Create;
begin
  inherited;
  FName        := 'mcp-shell';
  FDescription :=
    'Execute shell commands and capture stdout, stderr, and exit code. ' +
    'shell param: cmd (default, Windows cmd.exe with UTF-8 codepage), powershell, bash. ' +
    'Params: command (required), shell, workdir, timeout_ms (30000), stdin_data. ' +
    'Returns: stdout, stderr, exit_code, ok (exit_code=0). ' +
    'Examples: dir (cmd), Get-Process (powershell), ls -la (bash). ' +
    'NOTE: to execute Python code, use mcp-python instead — it handles Unicode natively. ' +
    'WARNING: executes arbitrary commands — use only in trusted environments.';
end;

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-shell',
    function: IAiMCPTool
    begin
      Result := TShellTool.Create;
    end);
  WriteLn(ErrOutput, '[MCPService]   + mcp-shell');
end;

end.
