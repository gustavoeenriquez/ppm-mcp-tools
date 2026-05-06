unit MCPTool.Ansible;

{
  MCPTool.Ansible  ·  mcp-ansible  (port 8639)
  Ansible CLI wrapper — run playbooks, ad-hoc modules, inventory.

  Operations:
    ping          - ansible all -m ping
    run_module    - run ad-hoc module on hosts
    run_playbook  - run ansible-playbook
    list_hosts    - ansible --list-hosts
    list_tasks    - ansible-playbook --list-tasks
    check         - ansible-playbook --check (dry-run)
    syntax_check  - ansible-playbook --syntax-check
    gather_facts  - run setup module to gather facts
}

interface

uses
  uMakerAi.MCPServer.Core,
  System.JSON;

type
  TAnsibleParams = class
  private
    FOperation   : string;
    FInventory   : string;
    FHosts       : string;
    FPlaybook    : string;
    FModule      : string;
    FModuleArgs  : string;
    FExtraVars   : string;
    FTags        : string;
    FSkipTags    : string;
    FLimit       : string;
    FUser        : string;
    FPrivateKey  : string;
    FForks       : Integer;
    FVerbose     : Boolean;
    FTimeout     : Integer;
  public
    constructor Create;

    [AiMCPSchemaDescription('Operation: ping, run_module, run_playbook, list_hosts, list_tasks, check, syntax_check, gather_facts')]
    property Operation   : string  read FOperation  write FOperation;

    [AiMCPSchemaDescription('Path to inventory file or directory (or comma-separated hosts e.g. host1,host2,)')]
    property Inventory   : string  read FInventory  write FInventory;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Host pattern (default: all) e.g. webservers, 192.168.1.0/24')]
    property Hosts       : string  read FHosts      write FHosts;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Path to playbook .yml file (for run_playbook, list_tasks, check, syntax_check)')]
    property Playbook    : string  read FPlaybook   write FPlaybook;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Module name for run_module / gather_facts (default: command)')]
    property Module      : string  read FModule     write FModule;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Module arguments e.g. "cmd=uptime" or for command module just the command')]
    property ModuleArgs  : string  read FModuleArgs write FModuleArgs;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Extra variables as JSON string or key=val pairs')]
    property ExtraVars   : string  read FExtraVars  write FExtraVars;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Tags to run (comma-separated)')]
    property Tags        : string  read FTags       write FTags;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Tags to skip (comma-separated)')]
    property SkipTags    : string  read FSkipTags   write FSkipTags;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Limit to subset of hosts')]
    property Limit       : string  read FLimit      write FLimit;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Remote user (-u)')]
    property User        : string  read FUser       write FUser;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Path to private key file')]
    property PrivateKey  : string  read FPrivateKey write FPrivateKey;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Number of parallel forks (default: 5)')]
    property Forks       : Integer read FForks      write FForks;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Verbose output (-v)')]
    property Verbose     : Boolean read FVerbose    write FVerbose;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Command timeout in seconds (default: 300)')]
    property Timeout     : Integer read FTimeout    write FTimeout;
  end;

  TAnsibleTool = class(TAiMCPToolBase<TAnsibleParams>)
  private
    function RunCmd(const Cmd: string; TimeoutSec: Integer): TJSONObject;
    function BuildCommonArgs(const P: TAnsibleParams): string;
    function BuildPlaybookArgs(const P: TAnsibleParams): string;

    function DoPing(const P: TAnsibleParams): TJSONObject;
    function DoRunModule(const P: TAnsibleParams): TJSONObject;
    function DoRunPlaybook(const P: TAnsibleParams): TJSONObject;
    function DoListHosts(const P: TAnsibleParams): TJSONObject;
    function DoListTasks(const P: TAnsibleParams): TJSONObject;
    function DoCheck(const P: TAnsibleParams): TJSONObject;
    function DoSyntaxCheck(const P: TAnsibleParams): TJSONObject;
    function DoGatherFacts(const P: TAnsibleParams): TJSONObject;
  protected
    function ExecuteWithParams(const AParams: TAnsibleParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

procedure RegisterTools(AServer: TAiMCPServer);

implementation

uses
  System.SysUtils,
  System.Classes,
  Winapi.Windows;

{ TAnsibleParams }

constructor TAnsibleParams.Create;
begin
  inherited;
  FHosts   := 'all';
  FModule  := 'command';
  FForks   := 5;
  FVerbose := False;
  FTimeout := 300;
end;

{ TAnsibleTool }

constructor TAnsibleTool.Create;
begin
  inherited;
  FName        := 'mcp-ansible';
  FDescription :=
    'Ansible CLI wrapper — ping hosts, run modules, execute playbooks, gather facts. ' +
    'Operations: ping (inventory, hosts?), run_module (inventory, module, moduleArgs, hosts?), ' +
    'run_playbook (inventory, playbook, extraVars?, tags?, skipTags?, limit?), ' +
    'list_hosts (inventory, hosts?), list_tasks (inventory, playbook), ' +
    'check (inventory, playbook — dry-run), syntax_check (inventory, playbook), ' +
    'gather_facts (inventory, hosts?). ' +
    'Requires ansible/ansible-playbook in PATH.';
end;

function TAnsibleTool.RunCmd(const Cmd: string; TimeoutSec: Integer): TJSONObject;
var
  SA:        TSecurityAttributes;
  PipeRead, PipeWrite: THandle;
  PI:        TProcessInformation;
  SI:        TStartupInfo;
  ExitCode:  DWORD;
  WaitResult: DWORD;
  Buffer:    array[0..4095] of AnsiChar;
  BytesRead: DWORD;
  Output:    string;
  TOut:      DWORD;
  CmdLine:   string;
begin
  SA.nLength              := SizeOf(SA);
  SA.lpSecurityDescriptor := nil;
  SA.bInheritHandle       := True;

  if not CreatePipe(PipeRead, PipeWrite, @SA, 0) then
    raise Exception.Create('CreatePipe failed: ' + SysErrorMessage(GetLastError));
  SetHandleInformation(PipeRead, HANDLE_FLAG_INHERIT, 0);

  FillChar(SI, SizeOf(SI), 0);
  SI.cb         := SizeOf(SI);
  SI.dwFlags    := STARTF_USESTDHANDLES;
  SI.hStdOutput := PipeWrite;
  SI.hStdError  := PipeWrite;
  SI.hStdInput  := INVALID_HANDLE_VALUE;

  TOut    := TimeoutSec; if TOut <= 0 then TOut := 300;
  CmdLine := 'cmd.exe /c ' + Cmd + ' 2>&1';

  FillChar(PI, SizeOf(PI), 0);
  if not CreateProcess(nil, PChar(CmdLine), nil, nil, True,
    CREATE_NO_WINDOW, nil, nil, SI, PI) then
  begin
    CloseHandle(PipeWrite);
    CloseHandle(PipeRead);
    raise Exception.Create('Failed to run command: ' + SysErrorMessage(GetLastError));
  end;

  CloseHandle(PipeWrite);
  Output := '';
  repeat
    if not ReadFile(PipeRead, Buffer, SizeOf(Buffer) - 1, BytesRead, nil) then Break;
    if BytesRead = 0 then Break;
    Buffer[BytesRead] := #0;
    Output := Output + string(AnsiString(PChar(@Buffer[0])));
  until False;

  WaitResult := WaitForSingleObject(PI.hProcess, TOut * 1000);
  GetExitCodeProcess(PI.hProcess, ExitCode);
  CloseHandle(PI.hProcess);
  CloseHandle(PI.hThread);
  CloseHandle(PipeRead);

  Result := TJSONObject.Create;
  Result.AddPair('output', Output.Trim);
  Result.AddPair('exit_code', TJSONNumber.Create(ExitCode));
  Result.AddPair('ok', TJSONBool.Create(ExitCode = 0));
  if WaitResult = WAIT_TIMEOUT then
    Result.AddPair('timeout', TJSONBool.Create(True));
end;

function TAnsibleTool.BuildCommonArgs(const P: TAnsibleParams): string;
var
  R: string;
begin
  R := ' -i "' + Trim(P.Inventory).Replace('"','\"') + '"';
  if Trim(P.User)       <> '' then R := R + ' -u "' + Trim(P.User).Replace('"','\"') + '"';
  if Trim(P.PrivateKey) <> '' then R := R + ' --private-key="' + Trim(P.PrivateKey).Replace('"','\"') + '"';
  if P.Forks > 0             then R := R + ' -f ' + IntToStr(P.Forks);
  if P.Verbose               then R := R + ' -v';
  Result := R;
end;

function TAnsibleTool.BuildPlaybookArgs(const P: TAnsibleParams): string;
var
  R: string;
begin
  R := BuildCommonArgs(P);
  if Trim(P.ExtraVars) <> '' then R := R + ' -e "' + Trim(P.ExtraVars).Replace('"','\"') + '"';
  if Trim(P.Tags)      <> '' then R := R + ' --tags "' + Trim(P.Tags).Replace('"','\"') + '"';
  if Trim(P.SkipTags)  <> '' then R := R + ' --skip-tags "' + Trim(P.SkipTags).Replace('"','\"') + '"';
  if Trim(P.Limit)     <> '' then R := R + ' --limit "' + Trim(P.Limit).Replace('"','\"') + '"';
  Result := R;
end;

function TAnsibleTool.DoPing(const P: TAnsibleParams): TJSONObject;
var
  H: string;
begin
  H := Trim(P.Hosts); if H = '' then H := 'all';
  Result := RunCmd(
    'ansible "' + H.Replace('"','\"') + '"' + BuildCommonArgs(P) + ' -m ping',
    P.Timeout);
end;

function TAnsibleTool.DoRunModule(const P: TAnsibleParams): TJSONObject;
var
  ModName, H, Cmd: string;
begin
  ModName := Trim(P.Module); if ModName = '' then ModName := 'command';
  H       := Trim(P.Hosts);  if H       = '' then H       := 'all';
  Cmd := 'ansible "' + H.Replace('"','\"') + '"' + BuildCommonArgs(P) +
    ' -m "' + ModName.Replace('"','\"') + '"';
  if Trim(P.ModuleArgs) <> '' then
    Cmd := Cmd + ' -a "' + Trim(P.ModuleArgs).Replace('"','\"') + '"';
  Result := RunCmd(Cmd, P.Timeout);
end;

function TAnsibleTool.DoRunPlaybook(const P: TAnsibleParams): TJSONObject;
begin
  if Trim(P.Playbook) = '' then raise Exception.Create('"playbook" required');
  Result := RunCmd(
    'ansible-playbook "' + Trim(P.Playbook).Replace('"','\"') + '"' + BuildPlaybookArgs(P),
    P.Timeout);
end;

function TAnsibleTool.DoListHosts(const P: TAnsibleParams): TJSONObject;
var
  H: string;
begin
  H := Trim(P.Hosts); if H = '' then H := 'all';
  Result := RunCmd(
    'ansible "' + H.Replace('"','\"') + '"' + BuildCommonArgs(P) + ' --list-hosts',
    P.Timeout);
end;

function TAnsibleTool.DoListTasks(const P: TAnsibleParams): TJSONObject;
begin
  if Trim(P.Playbook) = '' then raise Exception.Create('"playbook" required');
  Result := RunCmd(
    'ansible-playbook "' + Trim(P.Playbook).Replace('"','\"') + '"' +
    BuildPlaybookArgs(P) + ' --list-tasks',
    P.Timeout);
end;

function TAnsibleTool.DoCheck(const P: TAnsibleParams): TJSONObject;
begin
  if Trim(P.Playbook) = '' then raise Exception.Create('"playbook" required');
  Result := RunCmd(
    'ansible-playbook "' + Trim(P.Playbook).Replace('"','\"') + '"' +
    BuildPlaybookArgs(P) + ' --check',
    P.Timeout);
end;

function TAnsibleTool.DoSyntaxCheck(const P: TAnsibleParams): TJSONObject;
begin
  if Trim(P.Playbook) = '' then raise Exception.Create('"playbook" required');
  Result := RunCmd(
    'ansible-playbook "' + Trim(P.Playbook).Replace('"','\"') + '"' +
    BuildPlaybookArgs(P) + ' --syntax-check',
    P.Timeout);
end;

function TAnsibleTool.DoGatherFacts(const P: TAnsibleParams): TJSONObject;
var
  H: string;
begin
  H := Trim(P.Hosts); if H = '' then H := 'all';
  Result := RunCmd(
    'ansible "' + H.Replace('"','\"') + '"' + BuildCommonArgs(P) + ' -m setup',
    P.Timeout);
end;

function TAnsibleTool.ExecuteWithParams(const AParams: TAnsibleParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op: string;
  R:  TJSONObject;
begin
  try
    Op := LowerCase(Trim(AParams.Operation));
    if Op = '' then raise Exception.Create('"operation" is required');
    if Trim(AParams.Inventory) = '' then raise Exception.Create('"inventory" is required');

    if      Op = 'ping'         then R := DoPing(AParams)
    else if Op = 'run_module'   then R := DoRunModule(AParams)
    else if Op = 'run_playbook' then R := DoRunPlaybook(AParams)
    else if Op = 'list_hosts'   then R := DoListHosts(AParams)
    else if Op = 'list_tasks'   then R := DoListTasks(AParams)
    else if Op = 'check'        then R := DoCheck(AParams)
    else if Op = 'syntax_check' then R := DoSyntaxCheck(AParams)
    else if Op = 'gather_facts' then R := DoGatherFacts(AParams)
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
  AServer.RegisterTool('mcp-ansible',
    function: IAiMCPTool
    begin
      Result := TAnsibleTool.Create;
    end);
  WriteLn(ErrOutput, '[MCPService]   + mcp-ansible');
end;

end.
