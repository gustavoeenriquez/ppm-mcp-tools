unit MCPTool.Terraform;

{
  MCPTool.Terraform  ·  mcp-terraform  (port 8638)
  HashiCorp Terraform CLI wrapper — run terraform commands via shell.

  Operations:
    init      - terraform init
    validate  - terraform validate
    plan      - terraform plan [-out=planfile]
    apply     - terraform apply [planfile or -auto-approve]
    destroy   - terraform destroy -auto-approve
    show      - terraform show [planfile]
    output    - terraform output [-json]
    fmt       - terraform fmt [-check]
    state_list- terraform state list
    state_show- terraform state show <resource>
    workspace_list - terraform workspace list
    workspace_select - terraform workspace select <name>
}

interface

uses
  uMakerAi.MCPServer.Core,
  System.JSON;

type
  TTerraformParams = class
  private
    FOperation  : string;
    FWorkdir    : string;
    FPlanFile   : string;
    FResource   : string;
    FWorkspace  : string;
    FVars       : string;
    FVarFile    : string;
    FTarget     : string;
    FAutoApprove: Boolean;
    FCheck      : Boolean;
    FTimeout    : Integer;
  public
    constructor Create;

    [AiMCPSchemaDescription('Operation: init, validate, plan, apply, destroy, show, output, fmt, state_list, state_show, workspace_list, workspace_select')]
    property Operation  : string  read FOperation  write FOperation;

    [AiMCPSchemaDescription('Working directory containing .tf files (absolute path)')]
    property Workdir    : string  read FWorkdir    write FWorkdir;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Plan output file path (for plan -out= and apply with saved plan)')]
    property PlanFile   : string  read FPlanFile   write FPlanFile;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Resource address for state_show (e.g. aws_instance.example)')]
    property Resource   : string  read FResource   write FResource;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Workspace name for workspace_select')]
    property Workspace  : string  read FWorkspace  write FWorkspace;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Extra variables as -var key=val pairs, comma-separated e.g. region=us-east-1,env=prod')]
    property Vars       : string  read FVars       write FVars;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Path to .tfvars file')]
    property VarFile    : string  read FVarFile    write FVarFile;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Target resource for plan/apply/destroy (-target=)')]
    property Target     : string  read FTarget     write FTarget;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Auto-approve for apply/destroy (default: true)')]
    property AutoApprove: Boolean read FAutoApprove write FAutoApprove;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Check mode for fmt — only reports diffs (default: false)')]
    property Check      : Boolean read FCheck      write FCheck;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Command timeout in seconds (default: 300)')]
    property Timeout    : Integer read FTimeout    write FTimeout;
  end;

  TTerraformTool = class(TAiMCPToolBase<TTerraformParams>)
  private
    function RunTerraform(const Workdir, Args: string; TimeoutSec: Integer): TJSONObject;
    function BuildVarArgs(const Vars, VarFile, Target: string): string;

    function DoInit(const P: TTerraformParams): TJSONObject;
    function DoValidate(const P: TTerraformParams): TJSONObject;
    function DoPlan(const P: TTerraformParams): TJSONObject;
    function DoApply(const P: TTerraformParams): TJSONObject;
    function DoDestroy(const P: TTerraformParams): TJSONObject;
    function DoShow(const P: TTerraformParams): TJSONObject;
    function DoOutput(const P: TTerraformParams): TJSONObject;
    function DoFmt(const P: TTerraformParams): TJSONObject;
    function DoStateList(const P: TTerraformParams): TJSONObject;
    function DoStateShow(const P: TTerraformParams): TJSONObject;
    function DoWorkspaceList(const P: TTerraformParams): TJSONObject;
    function DoWorkspaceSelect(const P: TTerraformParams): TJSONObject;
  protected
    function ExecuteWithParams(const AParams: TTerraformParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

procedure RegisterTools(AServer: TAiMCPServer);

implementation

uses
  System.SysUtils,
  System.Classes,
  Winapi.Windows,
  Winapi.ShellAPI;

{ TTerraformParams }

constructor TTerraformParams.Create;
begin
  inherited;
  FAutoApprove := True;
  FCheck       := False;
  FTimeout     := 300;
end;

{ TTerraformTool }

constructor TTerraformTool.Create;
begin
  inherited;
  FName        := 'mcp-terraform';
  FDescription :=
    'HashiCorp Terraform CLI wrapper — init, plan, apply, destroy, show, output, fmt, state, workspaces. ' +
    'Operations: init (workdir), validate (workdir), plan (workdir, planFile?, vars?, varFile?, target?), ' +
    'apply (workdir, planFile?, autoApprove?), destroy (workdir, autoApprove?), ' +
    'show (workdir, planFile?), output (workdir), fmt (workdir, check?), ' +
    'state_list (workdir), state_show (workdir, resource), ' +
    'workspace_list (workdir), workspace_select (workdir, workspace). ' +
    'Requires terraform binary in PATH.';
end;

function TTerraformTool.BuildVarArgs(const Vars, VarFile, Target: string): string;
var
  Parts: TArray<string>;
  V, R: string;
begin
  R := '';
  if Trim(VarFile) <> '' then
    R := R + ' -var-file="' + Trim(VarFile).Replace('"','\"') + '"';
  if Trim(Vars) <> '' then
  begin
    Parts := Trim(Vars).Split([',']);
    for V in Parts do
    begin
      var KV := Trim(V);
      if KV <> '' then R := R + ' -var "' + KV.Replace('"','\"') + '"';
    end;
  end;
  if Trim(Target) <> '' then
    R := R + ' -target="' + Trim(Target).Replace('"','\"') + '"';
  Result := R;
end;

function TTerraformTool.RunTerraform(const Workdir, Args: string; TimeoutSec: Integer): TJSONObject;
var
  SA:         TSecurityAttributes;
  PipeRead, PipeWrite: THandle;
  PI:         TProcessInformation;
  SI:         TStartupInfo;
  Cmd:        string;
  ExitCode:   DWORD;
  WaitResult: DWORD;
  Buffer:     array[0..4095] of AnsiChar;
  BytesRead:  DWORD;
  Output:     string;
  TOut:       DWORD;
begin
  // Create pipe for stdout/stderr
  SA.nLength              := SizeOf(SA);
  SA.lpSecurityDescriptor := nil;
  SA.bInheritHandle       := True;

  if not CreatePipe(PipeRead, PipeWrite, @SA, 0) then
    raise Exception.Create('CreatePipe failed: ' + SysErrorMessage(GetLastError));

  // Ensure read handle is not inherited
  SetHandleInformation(PipeRead, HANDLE_FLAG_INHERIT, 0);

  FillChar(SI, SizeOf(SI), 0);
  SI.cb          := SizeOf(SI);
  SI.dwFlags     := STARTF_USESTDHANDLES;
  SI.hStdOutput  := PipeWrite;
  SI.hStdError   := PipeWrite;
  SI.hStdInput   := INVALID_HANDLE_VALUE;

  Cmd := 'cmd.exe /c "cd /d "' + Workdir + '" && terraform ' + Args + ' 2>&1"';

  TOut := TimeoutSec;
  if TOut <= 0 then TOut := 300;

  FillChar(PI, SizeOf(PI), 0);
  if not CreateProcess(nil, PChar(Cmd), nil, nil, True,
    CREATE_NO_WINDOW, nil, PChar(Workdir), SI, PI) then
  begin
    CloseHandle(PipeWrite);
    CloseHandle(PipeRead);
    raise Exception.Create('Failed to start terraform: ' + SysErrorMessage(GetLastError));
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

function TTerraformTool.DoInit(const P: TTerraformParams): TJSONObject;
begin
  Result := RunTerraform(Trim(P.Workdir), 'init -no-color', P.Timeout);
end;

function TTerraformTool.DoValidate(const P: TTerraformParams): TJSONObject;
begin
  Result := RunTerraform(Trim(P.Workdir), 'validate -no-color', P.Timeout);
end;

function TTerraformTool.DoPlan(const P: TTerraformParams): TJSONObject;
var
  Args: string;
begin
  Args := 'plan -no-color' + BuildVarArgs(P.Vars, P.VarFile, P.Target);
  if Trim(P.PlanFile) <> '' then
    Args := Args + ' -out="' + Trim(P.PlanFile).Replace('"','\"') + '"';
  Result := RunTerraform(Trim(P.Workdir), Args, P.Timeout);
end;

function TTerraformTool.DoApply(const P: TTerraformParams): TJSONObject;
var
  Args: string;
begin
  if Trim(P.PlanFile) <> '' then
    Args := 'apply -no-color "' + Trim(P.PlanFile).Replace('"','\"') + '"'
  else
  begin
    Args := 'apply -no-color' + BuildVarArgs(P.Vars, P.VarFile, P.Target);
    if P.AutoApprove then Args := Args + ' -auto-approve';
  end;
  Result := RunTerraform(Trim(P.Workdir), Args, P.Timeout);
end;

function TTerraformTool.DoDestroy(const P: TTerraformParams): TJSONObject;
var
  Args: string;
begin
  Args := 'destroy -no-color' + BuildVarArgs(P.Vars, P.VarFile, P.Target);
  if P.AutoApprove then Args := Args + ' -auto-approve';
  Result := RunTerraform(Trim(P.Workdir), Args, P.Timeout);
end;

function TTerraformTool.DoShow(const P: TTerraformParams): TJSONObject;
var
  Args: string;
begin
  Args := 'show -no-color -json';
  if Trim(P.PlanFile) <> '' then
    Args := Args + ' "' + Trim(P.PlanFile).Replace('"','\"') + '"';
  Result := RunTerraform(Trim(P.Workdir), Args, P.Timeout);
end;

function TTerraformTool.DoOutput(const P: TTerraformParams): TJSONObject;
begin
  Result := RunTerraform(Trim(P.Workdir), 'output -no-color -json', P.Timeout);
end;

function TTerraformTool.DoFmt(const P: TTerraformParams): TJSONObject;
var
  Args: string;
begin
  Args := 'fmt -no-color';
  if P.Check then Args := Args + ' -check';
  Result := RunTerraform(Trim(P.Workdir), Args, P.Timeout);
end;

function TTerraformTool.DoStateList(const P: TTerraformParams): TJSONObject;
begin
  Result := RunTerraform(Trim(P.Workdir), 'state list', P.Timeout);
end;

function TTerraformTool.DoStateShow(const P: TTerraformParams): TJSONObject;
begin
  if Trim(P.Resource) = '' then raise Exception.Create('"resource" required for state_show');
  Result := RunTerraform(Trim(P.Workdir),
    'state show "' + Trim(P.Resource).Replace('"','\"') + '"', P.Timeout);
end;

function TTerraformTool.DoWorkspaceList(const P: TTerraformParams): TJSONObject;
begin
  Result := RunTerraform(Trim(P.Workdir), 'workspace list', P.Timeout);
end;

function TTerraformTool.DoWorkspaceSelect(const P: TTerraformParams): TJSONObject;
begin
  if Trim(P.Workspace) = '' then raise Exception.Create('"workspace" required');
  Result := RunTerraform(Trim(P.Workdir),
    'workspace select "' + Trim(P.Workspace).Replace('"','\"') + '"', P.Timeout);
end;

function TTerraformTool.ExecuteWithParams(const AParams: TTerraformParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op: string;
  R:  TJSONObject;
begin
  try
    Op := LowerCase(Trim(AParams.Operation));
    if Op = '' then raise Exception.Create('"operation" is required');
    if Trim(AParams.Workdir) = '' then raise Exception.Create('"workdir" is required');

    if      Op = 'init'             then R := DoInit(AParams)
    else if Op = 'validate'         then R := DoValidate(AParams)
    else if Op = 'plan'             then R := DoPlan(AParams)
    else if Op = 'apply'            then R := DoApply(AParams)
    else if Op = 'destroy'          then R := DoDestroy(AParams)
    else if Op = 'show'             then R := DoShow(AParams)
    else if Op = 'output'           then R := DoOutput(AParams)
    else if Op = 'fmt'              then R := DoFmt(AParams)
    else if Op = 'state_list'       then R := DoStateList(AParams)
    else if Op = 'state_show'       then R := DoStateShow(AParams)
    else if Op = 'workspace_list'   then R := DoWorkspaceList(AParams)
    else if Op = 'workspace_select' then R := DoWorkspaceSelect(AParams)
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
  AServer.RegisterTool('mcp-terraform',
    function: IAiMCPTool
    begin
      Result := TTerraformTool.Create;
    end);
  WriteLn(ErrOutput, '[MCPService]   + mcp-terraform');
end;

end.
