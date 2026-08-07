unit MCPTool.Process;

{
  MCPTool.Process  ·  mcp-process

  Gestion de procesos sobre el runner compartido (MCPTool.ProcRunner).
  Windows: tasklist, taskkill, CreateProcess.
  POSIX:   ps, kill/pkill, y para "start" un lanzamiento en segundo plano
           del que el shell devuelve el PID.

  Operations:
    list  - list running processes (optional name filter).
    get   - get info about a specific process by name or PID.
    kill  - terminate a process by PID or name.
    start - launch a process fire-and-forget, returns PID.
    run   - execute a command synchronously and capture output.
    env   - list system environment variables (optional key filter).
}

interface

uses
  uMakerAi.MCPServer.Core,
  uMakerAi.Utils.System,
  System.SysUtils,
  System.JSON,
  System.Classes,
  MCPTool.ProcRunner
{$IFDEF MSWINDOWS}
  , Winapi.Windows   // solo para el CreateProcess de "start"
{$ENDIF}
  ;

type

  TProcessParams = class
  private
    FOperation: string;
    FName:      string;
    FPid:       Integer;
    FCommand:   string;
    FFilter:    string;
    FTimeout:   Integer;
  public
    constructor Create;

    [AiMCPSchemaDescription('Operation: list, get, kill, start, run, env')]
    property Operation: string  read FOperation write FOperation;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Process name (for get/kill; e.g. "notepad.exe")')]
    property Name:      string  read FName      write FName;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Process PID (for get/kill)')]
    property Pid:       Integer read FPid       write FPid;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Command to execute (for start/run)')]
    property Command:   string  read FCommand   write FCommand;

    [AiMCPOptional]
    [AiMCPSchemaDescription('list: filter by process name substring; env: filter by key substring')]
    property Filter:    string  read FFilter    write FFilter;

    [AiMCPOptional]
    [AiMCPSchemaDescription('run: timeout in milliseconds (default 30000)')]
    property Timeout:   Integer read FTimeout   write FTimeout;
  end;

  TProcessTool = class(TAiMCPToolBase<TProcessParams>)
  private
    function ParseCSVLine(const Line: string): TArray<string>;
    function GetProcessList(const Filter: string): TJSONArray;
    function DoList(const P: TProcessParams): TJSONObject;
    function DoGet(const P: TProcessParams): TJSONObject;
    function DoKill(const P: TProcessParams): TJSONObject;
    function DoStart(const P: TProcessParams): TJSONObject;
    function DoRun(const P: TProcessParams): TJSONObject;
    function DoEnv(const P: TProcessParams): TJSONObject;
  protected
    function ExecuteWithParams(const AParams: TProcessParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

procedure RegisterTools(AServer: TAiMCPServer);

implementation

{ Sustituye a TUtilsSystem.RunCommandLine, que solo existe en Windows. }
function RunShell(const ACmd: string): string;
var
  Output:   string;
  ExitCode: Integer;
  TimedOut: Boolean;
begin
  if not RunCaptured(ACmd, '', 60, Output, ExitCode, TimedOut) then
    raise Exception.Create('No se pudo ejecutar: ' + ACmd);
  Result := Output;
end;

{ TProcessParams }

constructor TProcessParams.Create;
begin
  inherited;
  FTimeout := 30000;
end;

{ TProcessTool }

function TProcessTool.ParseCSVLine(const Line: string): TArray<string>;
var
  S: string;
begin
  S := Trim(Line);
  // tasklist /FO CSV /NH format: "name","pid","session","sess#","mem"
  if S.StartsWith('"') then S := S.Substring(1);
  if S.EndsWith('"')   then S := S.Substring(0, Length(S) - 1);
  Result := S.Split(['","']);
end;

function TProcessTool.GetProcessList(const Filter: string): TJSONArray;
var
  Output: string;
  Lines:  TStringList;
  Fields: TArray<string>;
  Line:   string;
  LFilter: string;
  Proc:   TJSONObject;
begin
  Result  := TJSONArray.Create;
  LFilter := LowerCase(Trim(Filter));
  Output  := RunShell(
{$IFDEF MSWINDOWS}
    'tasklist /FO CSV /NH'
{$ELSE}
    // ps con columnas fijas y sin cabecera: el orden imita al de tasklist
    // (nombre, pid, sesion, memoria) para reusar el mismo bucle de parseo.
    'ps -eo comm=,pid=,tty=,rss='
{$ENDIF}
    );

  Lines := TStringList.Create;
  try
    Lines.Text := Output;
    for Line in Lines do
    begin
      var L := Trim(Line);
      if L = '' then Continue;

{$IFDEF MSWINDOWS}
      Fields := ParseCSVLine(L);
      if Length(Fields) < 5 then Continue;
      var ProcName := Fields[0];
      var ProcPid  := StrToIntDef(Fields[1], 0);
      var Session  := Fields[2];
      var MemStr   := Fields[4]; // p.ej. "45,678 K"
{$ELSE}
      Fields := L.Split([' '], TStringSplitOptions.ExcludeEmpty);
      if Length(Fields) < 4 then Continue;
      var ProcName := Fields[0];
      var ProcPid  := StrToIntDef(Fields[1], 0);
      var Session  := Fields[2];
      var MemStr   := Fields[3] + ' K';   // ps da rss en KiB
{$ENDIF}

      if (LFilter <> '') and not LowerCase(ProcName).Contains(LFilter) then
        Continue;

      var MemClean := MemStr.Replace(',', '').Replace('.', '').Replace(' K', '').Trim;
      var MemKB    := StrToIntDef(MemClean, 0);

      Proc := TJSONObject.Create;
      Proc.AddPair('name',       ProcName);
      Proc.AddPair('pid',        TJSONNumber.Create(ProcPid));
      Proc.AddPair('session',    Session);
      Proc.AddPair('memory_kb',  TJSONNumber.Create(MemKB));
      Proc.AddPair('memory',     MemStr);
      Result.Add(Proc);
    end;
  finally
    Lines.Free;
  end;
end;

function TProcessTool.DoList(const P: TProcessParams): TJSONObject;
var
  Procs: TJSONArray;
begin
  Procs := GetProcessList(P.Filter);

  Result := TJSONObject.Create;
  Result.AddPair('processes', Procs);
  Result.AddPair('count',     TJSONNumber.Create(Procs.Count));
  if P.Filter <> '' then
    Result.AddPair('filter', P.Filter);
  Result.AddPair('ok', TJSONTrue.Create);
end;

function TProcessTool.DoGet(const P: TProcessParams): TJSONObject;
var
  All:   TJSONArray;
  Found: TJSONObject;
  i:     Integer;
begin
  if (P.Pid <= 0) and (P.Name = '') then
    raise Exception.Create('"pid" or "name" required for get');

  All   := GetProcessList('');
  Found := nil;
  try
    for i := 0 to All.Count - 1 do
    begin
      var Item := All.Items[i] as TJSONObject;
      var Match := False;

      if P.Pid > 0 then
        Match := Item.GetValue<Integer>('pid', 0) = P.Pid
      else
        Match := SameText(Item.GetValue<string>('name', ''), P.Name);

      if Match then
      begin
        Found := Item.Clone as TJSONObject;
        Break;
      end;
    end;
  finally
    All.Free;
  end;

  Result := TJSONObject.Create;
  if Found <> nil then
  begin
    Result.AddPair('found',   TJSONTrue.Create);
    Result.AddPair('process', Found);
  end
  else
  begin
    Result.AddPair('found', TJSONFalse.Create);
    if P.Pid > 0 then
      Result.AddPair('pid',  TJSONNumber.Create(P.Pid))
    else
      Result.AddPair('name', P.Name);
  end;
  Result.AddPair('ok', TJSONTrue.Create);
end;

function TProcessTool.DoKill(const P: TProcessParams): TJSONObject;
var
  Cmd, Output: string;
begin
  if (P.Pid <= 0) and (P.Name = '') then
    raise Exception.Create('"pid" or "name" required for kill');

{$IFDEF MSWINDOWS}
  if P.Pid > 0 then
    Cmd := Format('taskkill /PID %d /F', [P.Pid])
  else
    Cmd := Format('taskkill /IM "%s" /F', [P.Name]);
{$ELSE}
  if P.Pid > 0 then
    Cmd := Format('kill -9 %d', [P.Pid])
  else
    Cmd := Format('pkill -9 -x "%s"', [P.Name]);
{$ENDIF}

  Output := RunShell(Cmd);

{$IFDEF MSWINDOWS}
  var Success := Output.Contains('SUCCESS') or Output.Contains('xito') or
                 Output.Contains('ito');
{$ELSE}
  // kill y pkill no dicen nada al acertar: el silencio ES el exito.
  var Success := Trim(Output) = '';
{$ENDIF}

  Result := TJSONObject.Create;
  if P.Pid > 0 then
    Result.AddPair('pid',  TJSONNumber.Create(P.Pid))
  else
    Result.AddPair('name', P.Name);
  Result.AddPair('success', TJSONBool.Create(Success));
  Result.AddPair('output',  Trim(Output));
  Result.AddPair('ok',      TJSONTrue.Create);
end;

function TProcessTool.DoStart(const P: TProcessParams): TJSONObject;
var
  Cmd: string;
  PID: Cardinal;
{$IFDEF MSWINDOWS}
  SI:  TStartupInfo;
  PI:  TProcessInformation;
{$ENDIF}
begin
  if P.Command = '' then raise Exception.Create('"command" required for start');

{$IFDEF MSWINDOWS}
  FillChar(SI, SizeOf(SI), 0);
  SI.cb          := SizeOf(SI);
  SI.dwFlags     := STARTF_USESHOWWINDOW;
  SI.wShowWindow := SW_HIDE;

  Cmd := P.Command;
  UniqueString(Cmd);

  FillChar(PI, SizeOf(PI), 0);
  if not CreateProcess(nil, PChar(Cmd), nil, nil, False,
    CREATE_NO_WINDOW, nil, nil, SI, PI) then
    RaiseLastOSError;

  PID := PI.dwProcessId;
  CloseHandle(PI.hProcess);
  CloseHandle(PI.hThread);
{$ELSE}
  // Lanzar en segundo plano desligado del server y quedarse con su PID:
  // el propio shell lo imprime con $!. La salida del hijo se descarta,
  // que es justo lo que "start" promete (arrancar, no esperar).
  Cmd := Format('%s >/dev/null 2>&1 & echo $!', [P.Command]);
  PID := StrToIntDef(Trim(RunShell(Cmd)), 0);
  if PID = 0 then
    raise Exception.Create('No se pudo lanzar: ' + P.Command);
{$ENDIF}

  Result := TJSONObject.Create;
  Result.AddPair('command', P.Command);
  Result.AddPair('pid',     TJSONNumber.Create(PID));
  Result.AddPair('ok',      TJSONTrue.Create);
end;

function TProcessTool.DoRun(const P: TProcessParams): TJSONObject;
var
  Output: string;
begin
  if P.Command = '' then raise Exception.Create('"command" required for run');

  Output := RunShell(P.Command);

  Result := TJSONObject.Create;
  Result.AddPair('command', P.Command);
  Result.AddPair('output',  Output);
  Result.AddPair('ok',      TJSONTrue.Create);
end;

function TProcessTool.DoEnv(const P: TProcessParams): TJSONObject;
var
  Env:     TStringList;
  EnvObj:  TJSONObject;
  LFilter: string;
  Item:    string;
  EqPos:   Integer;
  Key, Val: string;
begin
  LFilter := LowerCase(Trim(P.Filter));
  Env     := TUtilsSystem.GetSystemEnvironment;
  EnvObj  := TJSONObject.Create;
  try
    for Item in Env do
    begin
      EqPos := Pos('=', Item);
      if EqPos <= 0 then Continue;
      Key := Copy(Item, 1, EqPos - 1);
      Val := Copy(Item, EqPos + 1, MaxInt);
      if (LFilter = '') or LowerCase(Key).Contains(LFilter) then
        EnvObj.AddPair(Key, Val);
    end;
  finally
    Env.Free;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('env',   EnvObj);
  Result.AddPair('count', TJSONNumber.Create(EnvObj.Count));
  if LFilter <> '' then
    Result.AddPair('filter', P.Filter);
  Result.AddPair('ok', TJSONTrue.Create);
end;

function TProcessTool.ExecuteWithParams(const AParams: TProcessParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op: string;
  R:  TJSONObject;
begin
  try
    Op := LowerCase(Trim(AParams.Operation));
    if Op = '' then raise Exception.Create('"operation" is required');

    if      Op = 'list'  then R := DoList(AParams)
    else if Op = 'get'   then R := DoGet(AParams)
    else if Op = 'kill'  then R := DoKill(AParams)
    else if Op = 'start' then R := DoStart(AParams)
    else if Op = 'run'   then R := DoRun(AParams)
    else if Op = 'env'   then R := DoEnv(AParams)
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

constructor TProcessTool.Create;
begin
  inherited;
  FName        := 'mcp-process';
  FDescription :=
    'Process management. ' +
    'Operations: ' +
    'list (list running processes; param: filter for name substring), ' +
    'get (get process info; params: pid or name), ' +
    'kill (terminate process; params: pid or name), ' +
    'start (launch process fire-and-forget, returns pid; param: command), ' +
    'run (execute command and capture output; params: command, timeout), ' +
    'env (list environment variables; param: filter for key substring).';
end;

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-process',
    function: IAiMCPTool
    begin
      Result := TProcessTool.Create;
    end);
  WriteLn(ErrOutput, '[mcp-process] ready');
end;

end.
