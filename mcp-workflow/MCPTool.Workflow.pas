unit MCPTool.Workflow;

(*
  MCPTool.Workflow  ·  mcp-workflow

  Simple workflow/task pipeline engine with persistent JSON storage.

  Operations:
    create_workflow  - define a new workflow with ordered steps
    get_workflow     - retrieve a workflow definition
    delete_workflow  - remove a workflow definition
    list_workflows   - list all defined workflows
    start_workflow   - create and start a new run of a workflow
    complete_step    - mark a step as completed/skipped/failed
    get_run          - get current state of a workflow run
    list_runs        - list runs, optionally filtered by WorkflowId
    cancel_run       - cancel a running workflow

  Storage: JSON file at {StoragePath}/mcp_workflows.json
  Default StoragePath: TPath.GetDocumentsPath
  Port: 8650
*)

interface

uses
  uMakerAi.MCPServer.Core,
  System.JSON;

type

  TWorkflowParams = class
  private
    FOperation:   string;
    FStoragePath: string;
    FWorkflowId:  string;
    FWorkflowName: string;
    FRunId:       string;
    FStepId:      string;
    FSteps:       string;
    FInput:       string;
    FStepOutput:  string;
    FStepStatus:  string;
  public
    [AiMCPSchemaDescription('Operation: create_workflow, get_workflow, delete_workflow, list_workflows, start_workflow, complete_step, get_run, list_runs, cancel_run')]
    property Operation:    string read FOperation   write FOperation;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Directory path for the JSON storage file (default: Documents folder)')]
    property StoragePath:  string read FStoragePath write FStoragePath;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Workflow ID (optional for create_workflow; auto-generated if empty)')]
    property WorkflowId:   string read FWorkflowId  write FWorkflowId;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Human-readable workflow name (required for create_workflow)')]
    property WorkflowName: string read FWorkflowName write FWorkflowName;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Run ID (optional for start_workflow; auto-generated if empty)')]
    property RunId:        string read FRunId        write FRunId;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Step ID (required for complete_step)')]
    property StepId:       string read FStepId       write FStepId;

    [AiMCPOptional]
    [AiMCPSchemaDescription('JSON array of step objects: [{"id":"s1","name":"Step 1","description":"..."}] (required for create_workflow)')]
    property Steps:        string read FSteps        write FSteps;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Optional context/input JSON string for a workflow run')]
    property WorkflowInput: string read FInput        write FInput;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Optional output/result text for a completed step')]
    property StepOutput:   string read FStepOutput   write FStepOutput;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Step completion status: completed (default), skipped, failed')]
    property StepStatus:   string read FStepStatus   write FStepStatus;
  end;

  TWorkflowTool = class(TAiMCPToolBase<TWorkflowParams>)
  private
    function ResolveStoragePath(const StoragePath: string): string;
    function GetFilePath(const StoragePath: string): string;
    function LoadData(const Dir: string): TJSONObject;
    procedure SaveData(const Dir: string; Data: TJSONObject);
    function GetOrCreateSection(Data: TJSONObject; const Key: string): TJSONObject;
    function NowISO: string;
    function GenerateWorkflowId: string;
    function GenerateRunId: string;
    function DoCreateWorkflow(const P: TWorkflowParams): TJSONObject;
    function DoGetWorkflow(const P: TWorkflowParams): TJSONObject;
    function DoDeleteWorkflow(const P: TWorkflowParams): TJSONObject;
    function DoListWorkflows(const P: TWorkflowParams): TJSONObject;
    function DoStartWorkflow(const P: TWorkflowParams): TJSONObject;
    function DoCompleteStep(const P: TWorkflowParams): TJSONObject;
    function DoGetRun(const P: TWorkflowParams): TJSONObject;
    function DoListRuns(const P: TWorkflowParams): TJSONObject;
    function DoCancelRun(const P: TWorkflowParams): TJSONObject;
  protected
    function ExecuteWithParams(const AParams: TWorkflowParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

procedure RegisterTools(AServer: TAiMCPServer);

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils;

{ TWorkflowTool }

function TWorkflowTool.ResolveStoragePath(const StoragePath: string): string;
begin
  if Trim(StoragePath) = '' then
    Result := TPath.GetDocumentsPath
  else
    Result := StoragePath;
end;

function TWorkflowTool.GetFilePath(const StoragePath: string): string;
begin
  Result := TPath.Combine(StoragePath, 'mcp_workflows.json');
end;

function TWorkflowTool.LoadData(const Dir: string): TJSONObject;
var
  FilePath: string;
  Content:  string;
  Parsed:   TJSONValue;
begin
  FilePath := GetFilePath(Dir);
  if not TFile.Exists(FilePath) then
  begin
    Result := TJSONObject.Create;
    Result.AddPair('workflows', TJSONObject.Create);
    Result.AddPair('runs',      TJSONObject.Create);
    Exit;
  end;
  Content := TFile.ReadAllText(FilePath, TEncoding.UTF8);
  if Trim(Content) = '' then
  begin
    Result := TJSONObject.Create;
    Result.AddPair('workflows', TJSONObject.Create);
    Result.AddPair('runs',      TJSONObject.Create);
    Exit;
  end;
  Parsed := TJSONObject.ParseJSONValue(Content);
  if (Parsed <> nil) and (Parsed is TJSONObject) then
    Result := Parsed as TJSONObject
  else
  begin
    if Parsed <> nil then
      Parsed.Free;
    Result := TJSONObject.Create;
    Result.AddPair('workflows', TJSONObject.Create);
    Result.AddPair('runs',      TJSONObject.Create);
  end;
end;

procedure TWorkflowTool.SaveData(const Dir: string; Data: TJSONObject);
var
  FilePath: string;
  DirPath:  string;
begin
  FilePath := GetFilePath(Dir);
  DirPath  := TPath.GetDirectoryName(FilePath);
  if not TDirectory.Exists(DirPath) then
    TDirectory.CreateDirectory(DirPath);
  TFile.WriteAllText(FilePath, Data.ToJSON, TEncoding.UTF8);
end;

function TWorkflowTool.GetOrCreateSection(Data: TJSONObject;
  const Key: string): TJSONObject;
var
  Val: TJSONValue;
begin
  Val := Data.GetValue(Key);
  if (Val <> nil) and (Val is TJSONObject) then
    Result := Val as TJSONObject
  else
  begin
    Result := TJSONObject.Create;
    if Val <> nil then
      Data.RemovePair(Key).Free;
    Data.AddPair(Key, Result);
  end;
end;

function TWorkflowTool.NowISO: string;
begin
  Result := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', Now);
end;

function TWorkflowTool.GenerateWorkflowId: string;
begin
  Result := 'wf-' + FormatDateTime('yyyymmddhhnnss', Now);
end;

function TWorkflowTool.GenerateRunId: string;
begin
  Result := 'run-' + FormatDateTime('yyyymmddhhnnss', Now);
end;

function TWorkflowTool.DoCreateWorkflow(const P: TWorkflowParams): TJSONObject;
var
  Dir:        string;
  Data:       TJSONObject;
  Workflows:  TJSONObject;
  WfId:       string;
  WfName:     string;
  StepsArr:   TJSONValue;
  StepsParsed: TJSONArray;
  WfDef:      TJSONObject;
  StepCount:  Integer;
begin
  WfName := Trim(P.WorkflowName);
  if WfName = '' then
    raise Exception.Create('"WorkflowName" is required for create_workflow');
  if Trim(P.Steps) = '' then
    raise Exception.Create('"Steps" JSON array is required for create_workflow');

  StepsArr := TJSONObject.ParseJSONValue(P.Steps);
  if (StepsArr = nil) or not (StepsArr is TJSONArray) then
  begin
    if StepsArr <> nil then
      StepsArr.Free;
    raise Exception.Create('"Steps" must be a valid JSON array');
  end;
  StepsParsed := StepsArr as TJSONArray;
  StepCount   := StepsParsed.Count;

  WfId := Trim(P.WorkflowId);
  if WfId = '' then
    WfId := GenerateWorkflowId;

  Dir  := ResolveStoragePath(P.StoragePath);
  Data := LoadData(Dir);
  try
    Workflows := GetOrCreateSection(Data, 'workflows');

    WfDef := TJSONObject.Create;
    WfDef.AddPair('workflow_id', WfId);
    WfDef.AddPair('name',        WfName);
    WfDef.AddPair('created',     NowISO);
    WfDef.AddPair('steps',       StepsParsed.Clone as TJSONArray);

    if Workflows.GetValue(WfId) <> nil then
      Workflows.RemovePair(WfId).Free;
    Workflows.AddPair(WfId, WfDef);

    SaveData(Dir, Data);
  finally
    Data.Free;
    StepsParsed.Free;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('ok',          TJSONTrue.Create);
  Result.AddPair('workflow_id', WfId);
  Result.AddPair('name',        WfName);
  Result.AddPair('steps',       TJSONNumber.Create(StepCount));
end;

function TWorkflowTool.DoGetWorkflow(const P: TWorkflowParams): TJSONObject;
var
  Dir:      string;
  Data:     TJSONObject;
  Workflows: TJSONObject;
  WfId:     string;
  WfVal:    TJSONValue;
  WfDef:    TJSONObject;
  WfClone:  TJSONObject;
begin
  WfId := Trim(P.WorkflowId);
  if WfId = '' then
    raise Exception.Create('"WorkflowId" is required for get_workflow');

  Dir  := ResolveStoragePath(P.StoragePath);
  Data := LoadData(Dir);
  try
    Workflows := GetOrCreateSection(Data, 'workflows');
    WfVal     := Workflows.GetValue(WfId);
    if (WfVal = nil) or not (WfVal is TJSONObject) then
      raise Exception.CreateFmt('Workflow "%s" not found', [WfId]);
    WfDef   := WfVal as TJSONObject;
    WfClone := WfDef.Clone as TJSONObject;
  finally
    Data.Free;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('ok',          TJSONTrue.Create);
  Result.AddPair('workflow_id', WfId);
  Result.AddPair('name',        WfClone.GetValue<string>('name', ''));
  Result.AddPair('steps',       (WfClone.GetValue('steps') as TJSONArray).Clone as TJSONArray);
  WfClone.Free;
end;

function TWorkflowTool.DoDeleteWorkflow(const P: TWorkflowParams): TJSONObject;
var
  Dir:       string;
  Data:      TJSONObject;
  Workflows: TJSONObject;
  WfId:      string;
  Removed:   TJSONPair;
begin
  WfId := Trim(P.WorkflowId);
  if WfId = '' then
    raise Exception.Create('"WorkflowId" is required for delete_workflow');

  Dir  := ResolveStoragePath(P.StoragePath);
  Data := LoadData(Dir);
  try
    Workflows := GetOrCreateSection(Data, 'workflows');
    Removed   := Workflows.RemovePair(WfId);
    if Removed <> nil then
    begin
      Removed.Free;
      SaveData(Dir, Data);
    end
    else
      raise Exception.CreateFmt('Workflow "%s" not found', [WfId]);
  finally
    Data.Free;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('ok',      TJSONTrue.Create);
  Result.AddPair('deleted', WfId);
end;

function TWorkflowTool.DoListWorkflows(const P: TWorkflowParams): TJSONObject;
var
  Dir:       string;
  Data:      TJSONObject;
  Workflows: TJSONObject;
  Pair:      TJSONPair;
  Arr:       TJSONArray;
  Item:      TJSONObject;
  WfDef:     TJSONObject;
  StepsVal:  TJSONValue;
  StepCount: Integer;
begin
  Dir  := ResolveStoragePath(P.StoragePath);
  Data := LoadData(Dir);
  try
    Workflows := GetOrCreateSection(Data, 'workflows');
    Arr := TJSONArray.Create;
    for Pair in Workflows do
    begin
      if not (Pair.JsonValue is TJSONObject) then
        Continue;
      WfDef    := Pair.JsonValue as TJSONObject;
      StepsVal := WfDef.GetValue('steps');
      if (StepsVal <> nil) and (StepsVal is TJSONArray) then
        StepCount := (StepsVal as TJSONArray).Count
      else
        StepCount := 0;
      Item := TJSONObject.Create;
      Item.AddPair('workflow_id', WfDef.GetValue<string>('workflow_id', Pair.JsonString.Value));
      Item.AddPair('name',        WfDef.GetValue<string>('name', ''));
      Item.AddPair('steps',       TJSONNumber.Create(StepCount));
      Arr.AddElement(Item);
    end;
  finally
    Data.Free;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('ok',        TJSONTrue.Create);
  Result.AddPair('workflows', Arr);
end;

function TWorkflowTool.DoStartWorkflow(const P: TWorkflowParams): TJSONObject;
var
  Dir:        string;
  Data:       TJSONObject;
  Workflows:  TJSONObject;
  Runs:       TJSONObject;
  WfId:       string;
  RunId:      string;
  WfVal:      TJSONValue;
  WfDef:      TJSONObject;
  StepsArr:   TJSONArray;
  FirstStepId: string;
  RunObj:     TJSONObject;
  StepResults: TJSONObject;
begin
  WfId := Trim(P.WorkflowId);
  if WfId = '' then
    raise Exception.Create('"WorkflowId" is required for start_workflow');

  Dir  := ResolveStoragePath(P.StoragePath);
  Data := LoadData(Dir);
  try
    Workflows := GetOrCreateSection(Data, 'workflows');
    WfVal     := Workflows.GetValue(WfId);
    if (WfVal = nil) or not (WfVal is TJSONObject) then
      raise Exception.CreateFmt('Workflow "%s" not found', [WfId]);

    WfDef    := WfVal as TJSONObject;
    StepsArr := WfDef.GetValue('steps') as TJSONArray;
    if (StepsArr = nil) or (StepsArr.Count = 0) then
      raise Exception.CreateFmt('Workflow "%s" has no steps defined', [WfId]);

    FirstStepId := '';
    if StepsArr.Items[0] is TJSONObject then
      FirstStepId := (StepsArr.Items[0] as TJSONObject).GetValue<string>('id', '');

    RunId := Trim(P.RunId);
    if RunId = '' then
      RunId := GenerateRunId;

    StepResults := TJSONObject.Create;
    RunObj := TJSONObject.Create;
    RunObj.AddPair('run_id',       RunId);
    RunObj.AddPair('workflow_id',  WfId);
    RunObj.AddPair('status',       'running');
    RunObj.AddPair('started',      NowISO);
    RunObj.AddPair('ended',        TJSONNull.Create);
    RunObj.AddPair('input',        P.WorkflowInput);
    RunObj.AddPair('current_step', FirstStepId);
    RunObj.AddPair('step_results', StepResults);

    Runs := GetOrCreateSection(Data, 'runs');
    if Runs.GetValue(RunId) <> nil then
      Runs.RemovePair(RunId).Free;
    Runs.AddPair(RunId, RunObj);

    SaveData(Dir, Data);
  finally
    Data.Free;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('ok',          TJSONTrue.Create);
  Result.AddPair('run_id',      RunId);
  Result.AddPair('workflow_id', WfId);
  Result.AddPair('status',      'running');
end;

function TWorkflowTool.DoCompleteStep(const P: TWorkflowParams): TJSONObject;
var
  Dir:         string;
  Data:        TJSONObject;
  Workflows:   TJSONObject;
  Runs:        TJSONObject;
  RunId:       string;
  StepId:      string;
  RunVal:      TJSONValue;
  RunObj:      TJSONObject;
  WfId:        string;
  WfVal:       TJSONValue;
  WfDef:       TJSONObject;
  StepsArr:    TJSONArray;
  StepResults: TJSONObject;
  StepResVal:  TJSONValue;
  StepEntry:   TJSONObject;
  StepSt:      string;
  NextStepId:  string;
  Found:       Boolean;
  I:           Integer;
  CurStepObj:  TJSONObject;
  CurStepId:   string;
begin
  RunId  := Trim(P.RunId);
  StepId := Trim(P.StepId);
  if RunId = '' then
    raise Exception.Create('"RunId" is required for complete_step');
  if StepId = '' then
    raise Exception.Create('"StepId" is required for complete_step');

  StepSt := LowerCase(Trim(P.StepStatus));
  if StepSt = '' then
    StepSt := 'completed';
  if (StepSt <> 'completed') and (StepSt <> 'skipped') and (StepSt <> 'failed') then
    StepSt := 'completed';

  Dir  := ResolveStoragePath(P.StoragePath);
  Data := LoadData(Dir);
  try
    Runs   := GetOrCreateSection(Data, 'runs');
    RunVal := Runs.GetValue(RunId);
    if (RunVal = nil) or not (RunVal is TJSONObject) then
      raise Exception.CreateFmt('Run "%s" not found', [RunId]);

    RunObj := RunVal as TJSONObject;

    if RunObj.GetValue<string>('status', '') <> 'running' then
      raise Exception.CreateFmt('Run "%s" is not in running state', [RunId]);

    WfId := RunObj.GetValue<string>('workflow_id', '');

    Workflows := GetOrCreateSection(Data, 'workflows');
    WfVal     := Workflows.GetValue(WfId);
    if (WfVal = nil) or not (WfVal is TJSONObject) then
      raise Exception.CreateFmt('Workflow "%s" not found for run', [WfId]);

    WfDef    := WfVal as TJSONObject;
    StepsArr := WfDef.GetValue('steps') as TJSONArray;
    if StepsArr = nil then
      StepsArr := TJSONArray.Create;

    StepResVal  := RunObj.GetValue('step_results');
    if (StepResVal <> nil) and (StepResVal is TJSONObject) then
      StepResults := StepResVal as TJSONObject
    else
    begin
      StepResults := TJSONObject.Create;
      if StepResVal <> nil then
        RunObj.RemovePair('step_results').Free;
      RunObj.AddPair('step_results', StepResults);
    end;

    StepEntry := TJSONObject.Create;
    StepEntry.AddPair('status',    StepSt);
    StepEntry.AddPair('output',    P.StepOutput);
    StepEntry.AddPair('completed', NowISO);

    if StepResults.GetValue(StepId) <> nil then
      StepResults.RemovePair(StepId).Free;
    StepResults.AddPair(StepId, StepEntry);

    NextStepId := '';
    Found      := False;
    for I := 0 to StepsArr.Count - 1 do
    begin
      if not (StepsArr.Items[I] is TJSONObject) then
        Continue;
      CurStepObj := StepsArr.Items[I] as TJSONObject;
      CurStepId  := CurStepObj.GetValue<string>('id', '');
      if Found then
      begin
        NextStepId := CurStepId;
        Break;
      end;
      if CurStepId = StepId then
        Found := True;
    end;

    if RunObj.GetValue('current_step') <> nil then
      RunObj.RemovePair('current_step').Free;

    if NextStepId = '' then
    begin
      RunObj.AddPair('current_step', TJSONNull.Create);
      if RunObj.GetValue('status') <> nil then
        RunObj.RemovePair('status').Free;
      RunObj.AddPair('status', 'completed');
      if RunObj.GetValue('ended') <> nil then
        RunObj.RemovePair('ended').Free;
      RunObj.AddPair('ended', NowISO);
    end
    else
      RunObj.AddPair('current_step', NextStepId);

    SaveData(Dir, Data);
  finally
    Data.Free;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('ok',        TJSONTrue.Create);
  Result.AddPair('run_id',    RunId);
  Result.AddPair('step_id',   StepId);
  if NextStepId = '' then
    Result.AddPair('next_step', TJSONNull.Create)
  else
    Result.AddPair('next_step', NextStepId);
end;

function TWorkflowTool.DoGetRun(const P: TWorkflowParams): TJSONObject;
var
  Dir:          string;
  Data:         TJSONObject;
  Runs:         TJSONObject;
  RunId:        string;
  RunVal:       TJSONValue;
  RunObj:       TJSONObject;
  StepResVal:   TJSONValue;
  StepResults:  TJSONObject;
  StepsArr:     TJSONArray;
  I:            Integer;
  StepItem:     TJSONObject;
  StepId:       string;
  StepResItem:  TJSONValue;
  StepSummary:  TJSONObject;
  ResultSteps:  TJSONArray;
  WfId:         string;
  CurStep:      string;
  RunStatus:    string;
  Workflows:    TJSONObject;
  WfVal:        TJSONValue;
  WfDef:        TJSONObject;
  CurStepVal:   TJSONValue;
begin
  RunId := Trim(P.RunId);
  if RunId = '' then
    raise Exception.Create('"RunId" is required for get_run');

  Dir  := ResolveStoragePath(P.StoragePath);
  Data := LoadData(Dir);
  try
    Runs   := GetOrCreateSection(Data, 'runs');
    RunVal := Runs.GetValue(RunId);
    if (RunVal = nil) or not (RunVal is TJSONObject) then
      raise Exception.CreateFmt('Run "%s" not found', [RunId]);

    RunObj    := RunVal as TJSONObject;
    WfId      := RunObj.GetValue<string>('workflow_id', '');
    RunStatus := RunObj.GetValue<string>('status', '');

    CurStepVal := RunObj.GetValue('current_step');
    if (CurStepVal <> nil) and not (CurStepVal is TJSONNull) then
      CurStep := CurStepVal.Value
    else
      CurStep := '';

    StepResVal := RunObj.GetValue('step_results');
    if (StepResVal <> nil) and (StepResVal is TJSONObject) then
      StepResults := StepResVal as TJSONObject
    else
      StepResults := nil;

    Workflows := GetOrCreateSection(Data, 'workflows');
    WfVal     := Workflows.GetValue(WfId);
    StepsArr  := nil;
    if (WfVal <> nil) and (WfVal is TJSONObject) then
    begin
      WfDef    := WfVal as TJSONObject;
      StepsArr := WfDef.GetValue('steps') as TJSONArray;
    end;

    ResultSteps := TJSONArray.Create;
    if StepsArr <> nil then
    begin
      for I := 0 to StepsArr.Count - 1 do
      begin
        if not (StepsArr.Items[I] is TJSONObject) then
          Continue;
        StepItem   := StepsArr.Items[I] as TJSONObject;
        StepId     := StepItem.GetValue<string>('id', '');
        StepSummary := TJSONObject.Create;
        StepSummary.AddPair('id',   StepId);
        StepSummary.AddPair('name', StepItem.GetValue<string>('name', ''));
        if StepResults <> nil then
          StepResItem := StepResults.GetValue(StepId)
        else
          StepResItem := nil;
        if (StepResItem <> nil) and (StepResItem is TJSONObject) then
          StepSummary.AddPair('status', (StepResItem as TJSONObject).GetValue<string>('status', 'pending'))
        else
          StepSummary.AddPair('status', 'pending');
        ResultSteps.AddElement(StepSummary);
      end;
    end;
  finally
    Data.Free;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('ok',           TJSONTrue.Create);
  Result.AddPair('run_id',       RunId);
  Result.AddPair('workflow_id',  WfId);
  Result.AddPair('status',       RunStatus);
  if CurStep = '' then
    Result.AddPair('current_step', TJSONNull.Create)
  else
    Result.AddPair('current_step', CurStep);
  Result.AddPair('steps',        ResultSteps);
end;

function TWorkflowTool.DoListRuns(const P: TWorkflowParams): TJSONObject;
var
  Dir:      string;
  Data:     TJSONObject;
  Runs:     TJSONObject;
  Pair:     TJSONPair;
  Arr:      TJSONArray;
  Item:     TJSONObject;
  RunObj:   TJSONObject;
  FilterId: string;
  WfId:     string;
begin
  FilterId := Trim(P.WorkflowId);
  Dir      := ResolveStoragePath(P.StoragePath);
  Data     := LoadData(Dir);
  try
    Runs := GetOrCreateSection(Data, 'runs');
    Arr  := TJSONArray.Create;
    for Pair in Runs do
    begin
      if not (Pair.JsonValue is TJSONObject) then
        Continue;
      RunObj := Pair.JsonValue as TJSONObject;
      WfId   := RunObj.GetValue<string>('workflow_id', '');
      if (FilterId <> '') and (WfId <> FilterId) then
        Continue;
      Item := TJSONObject.Create;
      Item.AddPair('run_id',      RunObj.GetValue<string>('run_id',     Pair.JsonString.Value));
      Item.AddPair('workflow_id', WfId);
      Item.AddPair('status',      RunObj.GetValue<string>('status',  ''));
      Item.AddPair('started',     RunObj.GetValue<string>('started', ''));
      Arr.AddElement(Item);
    end;
  finally
    Data.Free;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('ok',   TJSONTrue.Create);
  Result.AddPair('runs', Arr);
end;

function TWorkflowTool.DoCancelRun(const P: TWorkflowParams): TJSONObject;
var
  Dir:    string;
  Data:   TJSONObject;
  Runs:   TJSONObject;
  RunId:  string;
  RunVal: TJSONValue;
  RunObj: TJSONObject;
begin
  RunId := Trim(P.RunId);
  if RunId = '' then
    raise Exception.Create('"RunId" is required for cancel_run');

  Dir  := ResolveStoragePath(P.StoragePath);
  Data := LoadData(Dir);
  try
    Runs   := GetOrCreateSection(Data, 'runs');
    RunVal := Runs.GetValue(RunId);
    if (RunVal = nil) or not (RunVal is TJSONObject) then
      raise Exception.CreateFmt('Run "%s" not found', [RunId]);

    RunObj := RunVal as TJSONObject;
    if RunObj.GetValue('status') <> nil then
      RunObj.RemovePair('status').Free;
    RunObj.AddPair('status', 'cancelled');
    if RunObj.GetValue('ended') <> nil then
      RunObj.RemovePair('ended').Free;
    RunObj.AddPair('ended', NowISO);

    SaveData(Dir, Data);
  finally
    Data.Free;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('ok',        TJSONTrue.Create);
  Result.AddPair('cancelled', RunId);
end;

function TWorkflowTool.ExecuteWithParams(const AParams: TWorkflowParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op: string;
  R:  TJSONObject;
begin
  try
    Op := LowerCase(Trim(AParams.Operation));
    if Op = '' then
      raise Exception.Create('"Operation" is required');

    if      Op = 'create_workflow'  then R := DoCreateWorkflow(AParams)
    else if Op = 'get_workflow'     then R := DoGetWorkflow(AParams)
    else if Op = 'delete_workflow'  then R := DoDeleteWorkflow(AParams)
    else if Op = 'list_workflows'   then R := DoListWorkflows(AParams)
    else if Op = 'start_workflow'   then R := DoStartWorkflow(AParams)
    else if Op = 'complete_step'    then R := DoCompleteStep(AParams)
    else if Op = 'get_run'          then R := DoGetRun(AParams)
    else if Op = 'list_runs'        then R := DoListRuns(AParams)
    else if Op = 'cancel_run'       then R := DoCancelRun(AParams)
    else raise Exception.CreateFmt('Unknown operation "%s"', [Op]);

    Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
    R.Free;
  except
    on E: Exception do
      Result := TAiMCPResponseBuilder.New
        .AddText('{"ok":false,"error":"' +
          E.Message.Replace('\', '\\').Replace('"', '\"')
                   .Replace(#10, '\n').Replace(#13, '') + '"}')
        .Build;
  end;
end;

constructor TWorkflowTool.Create;
begin
  inherited;
  FName        := 'mcp-workflow';
  FDescription :=
    'Workflow/task pipeline engine with persistent JSON storage. ' +
    'Operations: ' +
    'create_workflow (define a workflow with ordered steps; params: WorkflowName, Steps JSON array, WorkflowId?), ' +
    'get_workflow (retrieve workflow definition; params: WorkflowId), ' +
    'delete_workflow (remove a workflow; params: WorkflowId), ' +
    'list_workflows (list all defined workflows), ' +
    'start_workflow (create and start a run; params: WorkflowId, RunId?, WorkflowInput?), ' +
    'complete_step (mark step done; params: RunId, StepId, StepOutput?, StepStatus?[completed|skipped|failed]), ' +
    'get_run (get run state; params: RunId), ' +
    'list_runs (list runs; params: WorkflowId? for filter), ' +
    'cancel_run (cancel a running workflow; params: RunId). ' +
    'Storage file: mcp_workflows.json in Documents folder by default.';
end;

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-workflow',
    function: IAiMCPTool
    begin
      Result := TWorkflowTool.Create;
    end);
  WriteLn(ErrOutput, '[MCPService]   + mcp-workflow');
end;

end.
