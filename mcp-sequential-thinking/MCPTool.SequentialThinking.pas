unit MCPTool.SequentialThinking;

(*
  MCPTool.SequentialThinking  ·  mcp-sequential-thinking

  Manages sequential reasoning sessions — multi-step thought chains stored
  as JSON on disk.

  Operations:
    create_session  - create a new thinking session
    add_thought     - add a thought step to a session
    get_session     - retrieve all thoughts in a session
    list_sessions   - list all active sessions
    conclude        - mark a session as concluded with a final answer
    delete_session  - remove a session
    clear_all       - remove all sessions
    revise_thought  - update a specific thought step

  Storage: {StoragePath}/mcp_thinking_sessions.json

  Port: 8649
*)

interface

uses
  uMakerAi.MCPServer.Core,
  System.JSON;

type

  TSequentialThinkingParams = class
  private
    FOperation:   string;
    FStoragePath: string;
    FSessionId:   string;
    FProblem:     string;
    FThought:     string;
    FStepType:    string;
    FStepNumber:  Integer;
    FConclusion:  string;
  public
    [AiMCPSchemaDescription('Operation: create_session, add_thought, get_session, list_sessions, conclude, delete_session, clear_all, revise_thought')]
    property Operation:   string  read FOperation   write FOperation;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Directory where session file is stored. Defaults to system temp directory.')]
    property StoragePath: string  read FStoragePath write FStoragePath;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Session identifier. Auto-generated if not provided for create_session.')]
    property SessionId:   string  read FSessionId   write FSessionId;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Problem statement for create_session.')]
    property Problem:     string  read FProblem     write FProblem;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Thought content for add_thought or revise_thought.')]
    property Thought:     string  read FThought     write FThought;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Thought type for add_thought: analysis, hypothesis, conclusion, revision, question. Default: analysis.')]
    property StepType:    string  read FStepType    write FStepType;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Step number to revise (1-based) for revise_thought.')]
    property StepNumber:  Integer read FStepNumber  write FStepNumber;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Final conclusion text for the conclude operation.')]
    property Conclusion:  string  read FConclusion  write FConclusion;
  end;

  TSequentialThinkingTool = class(TAiMCPToolBase<TSequentialThinkingParams>)
  private
    function ResolveFilePath(const AStoragePath: string): string;
    function LoadRoot(const AFilePath: string): TJSONObject;
    procedure SaveRoot(const AFilePath: string; const ARoot: TJSONObject);
    function DoCreateSession(const P: TSequentialThinkingParams): TJSONObject;
    function DoAddThought(const P: TSequentialThinkingParams): TJSONObject;
    function DoGetSession(const P: TSequentialThinkingParams): TJSONObject;
    function DoListSessions(const P: TSequentialThinkingParams): TJSONObject;
    function DoConclude(const P: TSequentialThinkingParams): TJSONObject;
    function DoDeleteSession(const P: TSequentialThinkingParams): TJSONObject;
    function DoClearAll(const P: TSequentialThinkingParams): TJSONObject;
    function DoReviseThought(const P: TSequentialThinkingParams): TJSONObject;
  protected
    function ExecuteWithParams(const AParams: TSequentialThinkingParams;
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

{ TSequentialThinkingTool }

constructor TSequentialThinkingTool.Create;
begin
  inherited;
  FName        := 'mcp-sequential-thinking';
  FDescription :=
    'Manages sequential reasoning sessions with multi-step thought chains stored as JSON. ' +
    'Operations: ' +
    'create_session (create a new session; params: problem, session_id?), ' +
    'add_thought (add a step; params: session_id, thought, step_type?), ' +
    'get_session (retrieve all steps; param: session_id), ' +
    'list_sessions (list all sessions), ' +
    'conclude (mark session done; params: session_id, conclusion), ' +
    'delete_session (remove a session; param: session_id), ' +
    'clear_all (remove all sessions), ' +
    'revise_thought (update a step; params: session_id, step_number, thought). ' +
    'Optional param storage_path sets the directory for the session file.';
end;

function TSequentialThinkingTool.ResolveFilePath(const AStoragePath: string): string;
var
  Dir: string;
begin
  if AStoragePath <> '' then
    Dir := AStoragePath
  else
    Dir := TPath.GetTempPath;
  Result := TPath.Combine(Dir, 'mcp_thinking_sessions.json');
end;

function TSequentialThinkingTool.LoadRoot(const AFilePath: string): TJSONObject;
var
  Raw:    string;
  Parsed: TJSONValue;
begin
  if TFile.Exists(AFilePath) then
  begin
    Raw    := TFile.ReadAllText(AFilePath, TEncoding.UTF8);
    Parsed := TJSONObject.ParseJSONValue(Raw);
    if Parsed is TJSONObject then
      Result := Parsed as TJSONObject
    else
    begin
      if Assigned(Parsed) then Parsed.Free;
      Result := TJSONObject.Create;
      Result.AddPair('sessions', TJSONObject.Create);
    end;
  end
  else
  begin
    Result := TJSONObject.Create;
    Result.AddPair('sessions', TJSONObject.Create);
  end;
end;

procedure TSequentialThinkingTool.SaveRoot(const AFilePath: string; const ARoot: TJSONObject);
var
  Dir: string;
begin
  Dir := TPath.GetDirectoryName(AFilePath);
  if (Dir <> '') and not TDirectory.Exists(Dir) then
    TDirectory.CreateDirectory(Dir);
  TFile.WriteAllText(AFilePath, ARoot.ToJSON, TEncoding.UTF8);
end;

function TSequentialThinkingTool.DoCreateSession(const P: TSequentialThinkingParams): TJSONObject;
var
  FilePath:   string;
  Root:       TJSONObject;
  Sessions:   TJSONObject;
  SessionRec: TJSONObject;
  SessId:     string;
  Steps:      TJSONArray;
  Suffix:     string;
begin
  if P.Problem = '' then
    raise Exception.Create('"problem" is required for create_session');

  FilePath := ResolveFilePath(P.StoragePath);
  Root     := LoadRoot(FilePath);
  try
    Sessions := Root.GetValue('sessions') as TJSONObject;
    if not Assigned(Sessions) then
    begin
      Sessions := TJSONObject.Create;
      Root.AddPair('sessions', Sessions);
    end;

    if P.SessionId <> '' then
      SessId := P.SessionId
    else
    begin
      Suffix := IntToStr(Random(9000) + 1000);
      SessId := FormatDateTime('yyyymmddhhnnsszzz', Now) + Suffix;
    end;

    Steps      := TJSONArray.Create;
    SessionRec := TJSONObject.Create;
    SessionRec.AddPair('problem',    P.Problem);
    SessionRec.AddPair('created',    FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', Now));
    SessionRec.AddPair('concluded',  TJSONFalse.Create);
    SessionRec.AddPair('conclusion', '');
    SessionRec.AddPair('steps',      Steps);

    Sessions.AddPair(SessId, SessionRec);
    SaveRoot(FilePath, Root);

    Result := TJSONObject.Create;
    Result.AddPair('ok',         TJSONTrue.Create);
    Result.AddPair('session_id', SessId);
    Result.AddPair('problem',    P.Problem);
  finally
    Root.Free;
  end;
end;

function TSequentialThinkingTool.DoAddThought(const P: TSequentialThinkingParams): TJSONObject;
var
  FilePath:  string;
  Root:      TJSONObject;
  Sessions:  TJSONObject;
  SessObj:   TJSONObject;
  StepsArr:  TJSONArray;
  StepRec:   TJSONObject;
  StepCount: Integer;
  SType:     string;
begin
  if P.SessionId = '' then raise Exception.Create('"session_id" is required for add_thought');
  if P.Thought   = '' then raise Exception.Create('"thought" is required for add_thought');

  FilePath := ResolveFilePath(P.StoragePath);
  Root     := LoadRoot(FilePath);
  try
    Sessions := Root.GetValue('sessions') as TJSONObject;
    if not Assigned(Sessions) then
      raise Exception.CreateFmt('Session "%s" not found', [P.SessionId]);

    SessObj := Sessions.GetValue(P.SessionId) as TJSONObject;
    if not Assigned(SessObj) then
      raise Exception.CreateFmt('Session "%s" not found', [P.SessionId]);

    StepsArr := SessObj.GetValue('steps') as TJSONArray;
    if not Assigned(StepsArr) then
      raise Exception.Create('Session data is corrupt: missing steps array');

    StepCount := StepsArr.Count + 1;

    if P.StepType <> '' then
      SType := LowerCase(Trim(P.StepType))
    else
      SType := 'analysis';

    StepRec := TJSONObject.Create;
    StepRec.AddPair('step',      TJSONNumber.Create(StepCount));
    StepRec.AddPair('type',      SType);
    StepRec.AddPair('thought',   P.Thought);
    StepRec.AddPair('timestamp', FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', Now));

    StepsArr.AddElement(StepRec);
    SaveRoot(FilePath, Root);

    Result := TJSONObject.Create;
    Result.AddPair('ok',         TJSONTrue.Create);
    Result.AddPair('session_id', P.SessionId);
    Result.AddPair('step',       TJSONNumber.Create(StepCount));
    Result.AddPair('thought',    P.Thought);
  finally
    Root.Free;
  end;
end;

function TSequentialThinkingTool.DoGetSession(const P: TSequentialThinkingParams): TJSONObject;
var
  FilePath: string;
  Root:     TJSONObject;
  Sessions: TJSONObject;
  SessObj:  TJSONObject;
  StepsArr: TJSONArray;
  Problem:  string;
begin
  if P.SessionId = '' then raise Exception.Create('"session_id" is required for get_session');

  FilePath := ResolveFilePath(P.StoragePath);
  Root     := LoadRoot(FilePath);
  try
    Sessions := Root.GetValue('sessions') as TJSONObject;
    if not Assigned(Sessions) then
      raise Exception.CreateFmt('Session "%s" not found', [P.SessionId]);

    SessObj := Sessions.GetValue(P.SessionId) as TJSONObject;
    if not Assigned(SessObj) then
      raise Exception.CreateFmt('Session "%s" not found', [P.SessionId]);

    Problem  := SessObj.GetValue<string>('problem', '');
    StepsArr := SessObj.GetValue('steps') as TJSONArray;

    Result := TJSONObject.Create;
    Result.AddPair('ok',         TJSONTrue.Create);
    Result.AddPair('session_id', P.SessionId);
    Result.AddPair('problem',    Problem);
    if Assigned(StepsArr) then
      Result.AddPair('steps', StepsArr.Clone as TJSONArray)
    else
      Result.AddPair('steps', TJSONArray.Create);
  finally
    Root.Free;
  end;
end;

function TSequentialThinkingTool.DoListSessions(const P: TSequentialThinkingParams): TJSONObject;
var
  FilePath:  string;
  Root:      TJSONObject;
  Sessions:  TJSONObject;
  Arr:       TJSONArray;
  i:         Integer;
  Pair:      TJSONPair;
  SessObj:   TJSONObject;
  StepsArr:  TJSONArray;
  Entry:     TJSONObject;
  StepCount: Integer;
  Created:   string;
  Problem:   string;
begin
  FilePath := ResolveFilePath(P.StoragePath);
  Root     := LoadRoot(FilePath);
  try
    Sessions := Root.GetValue('sessions') as TJSONObject;
    Arr      := TJSONArray.Create;

    if Assigned(Sessions) then
    begin
      for i := 0 to Sessions.Count - 1 do
      begin
        Pair    := Sessions.Pairs[i];
        SessObj := Pair.JsonValue as TJSONObject;
        if not Assigned(SessObj) then Continue;

        Problem  := SessObj.GetValue<string>('problem', '');
        Created  := SessObj.GetValue<string>('created', '');
        StepsArr := SessObj.GetValue('steps') as TJSONArray;

        if Assigned(StepsArr) then
          StepCount := StepsArr.Count
        else
          StepCount := 0;

        Entry := TJSONObject.Create;
        Entry.AddPair('session_id', Pair.JsonString.Value);
        Entry.AddPair('problem',    Problem);
        Entry.AddPair('steps',      TJSONNumber.Create(StepCount));
        Entry.AddPair('created',    Created);
        Arr.AddElement(Entry);
      end;
    end;

    Result := TJSONObject.Create;
    Result.AddPair('ok',       TJSONTrue.Create);
    Result.AddPair('sessions', Arr);
  finally
    Root.Free;
  end;
end;

function TSequentialThinkingTool.DoConclude(const P: TSequentialThinkingParams): TJSONObject;
var
  FilePath:   string;
  Root:       TJSONObject;
  Sessions:   TJSONObject;
  SessObj:    TJSONObject;
  StepsArr:   TJSONArray;
  TotalSteps: Integer;
begin
  if P.SessionId  = '' then raise Exception.Create('"session_id" is required for conclude');
  if P.Conclusion = '' then raise Exception.Create('"conclusion" is required for conclude');

  FilePath := ResolveFilePath(P.StoragePath);
  Root     := LoadRoot(FilePath);
  try
    Sessions := Root.GetValue('sessions') as TJSONObject;
    if not Assigned(Sessions) then
      raise Exception.CreateFmt('Session "%s" not found', [P.SessionId]);

    SessObj := Sessions.GetValue(P.SessionId) as TJSONObject;
    if not Assigned(SessObj) then
      raise Exception.CreateFmt('Session "%s" not found', [P.SessionId]);

    SessObj.RemovePair('concluded').Free;
    SessObj.RemovePair('conclusion').Free;
    SessObj.AddPair('concluded',  TJSONTrue.Create);
    SessObj.AddPair('conclusion', P.Conclusion);

    StepsArr := SessObj.GetValue('steps') as TJSONArray;
    if Assigned(StepsArr) then
      TotalSteps := StepsArr.Count
    else
      TotalSteps := 0;

    SaveRoot(FilePath, Root);

    Result := TJSONObject.Create;
    Result.AddPair('ok',          TJSONTrue.Create);
    Result.AddPair('session_id',  P.SessionId);
    Result.AddPair('conclusion',  P.Conclusion);
    Result.AddPair('total_steps', TJSONNumber.Create(TotalSteps));
  finally
    Root.Free;
  end;
end;

function TSequentialThinkingTool.DoDeleteSession(const P: TSequentialThinkingParams): TJSONObject;
var
  FilePath: string;
  Root:     TJSONObject;
  Sessions: TJSONObject;
  Removed:  TJSONPair;
begin
  if P.SessionId = '' then raise Exception.Create('"session_id" is required for delete_session');

  FilePath := ResolveFilePath(P.StoragePath);
  Root     := LoadRoot(FilePath);
  try
    Sessions := Root.GetValue('sessions') as TJSONObject;
    if not Assigned(Sessions) then
      raise Exception.CreateFmt('Session "%s" not found', [P.SessionId]);

    Removed := Sessions.RemovePair(P.SessionId);
    if not Assigned(Removed) then
      raise Exception.CreateFmt('Session "%s" not found', [P.SessionId]);
    Removed.Free;

    SaveRoot(FilePath, Root);

    Result := TJSONObject.Create;
    Result.AddPair('ok',      TJSONTrue.Create);
    Result.AddPair('deleted', P.SessionId);
  finally
    Root.Free;
  end;
end;

function TSequentialThinkingTool.DoClearAll(const P: TSequentialThinkingParams): TJSONObject;
var
  FilePath: string;
  Root:     TJSONObject;
  Sessions: TJSONObject;
  Cleared:  Integer;
begin
  FilePath := ResolveFilePath(P.StoragePath);
  Root     := LoadRoot(FilePath);
  try
    Sessions := Root.GetValue('sessions') as TJSONObject;
    if Assigned(Sessions) then
      Cleared := Sessions.Count
    else
      Cleared := 0;

    Root.RemovePair('sessions').Free;
    Root.AddPair('sessions', TJSONObject.Create);

    SaveRoot(FilePath, Root);

    Result := TJSONObject.Create;
    Result.AddPair('ok',      TJSONTrue.Create);
    Result.AddPair('cleared', TJSONNumber.Create(Cleared));
  finally
    Root.Free;
  end;
end;

function TSequentialThinkingTool.DoReviseThought(const P: TSequentialThinkingParams): TJSONObject;
var
  FilePath: string;
  Root:     TJSONObject;
  Sessions: TJSONObject;
  SessObj:  TJSONObject;
  StepsArr: TJSONArray;
  StepObj:  TJSONObject;
  i:        Integer;
  StepNum:  Integer;
  Found:    Boolean;
begin
  if P.SessionId  = '' then raise Exception.Create('"session_id" is required for revise_thought');
  if P.Thought    = '' then raise Exception.Create('"thought" is required for revise_thought');
  if P.StepNumber < 1  then raise Exception.Create('"step_number" must be >= 1 for revise_thought');

  FilePath := ResolveFilePath(P.StoragePath);
  Root     := LoadRoot(FilePath);
  try
    Sessions := Root.GetValue('sessions') as TJSONObject;
    if not Assigned(Sessions) then
      raise Exception.CreateFmt('Session "%s" not found', [P.SessionId]);

    SessObj := Sessions.GetValue(P.SessionId) as TJSONObject;
    if not Assigned(SessObj) then
      raise Exception.CreateFmt('Session "%s" not found', [P.SessionId]);

    StepsArr := SessObj.GetValue('steps') as TJSONArray;
    if not Assigned(StepsArr) then
      raise Exception.Create('Session data is corrupt: missing steps array');

    StepNum := P.StepNumber;
    Found   := False;

    for i := 0 to StepsArr.Count - 1 do
    begin
      StepObj := StepsArr.Items[i] as TJSONObject;
      if not Assigned(StepObj) then Continue;

      if StepObj.GetValue<Integer>('step', 0) = StepNum then
      begin
        StepObj.RemovePair('thought').Free;
        StepObj.AddPair('thought', P.Thought);
        StepObj.RemovePair('timestamp').Free;
        StepObj.AddPair('timestamp', FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', Now));
        Found := True;
        Break;
      end;
    end;

    if not Found then
      raise Exception.CreateFmt('Step %d not found in session "%s"', [StepNum, P.SessionId]);

    SaveRoot(FilePath, Root);

    Result := TJSONObject.Create;
    Result.AddPair('ok',           TJSONTrue.Create);
    Result.AddPair('revised_step', TJSONNumber.Create(StepNum));
  finally
    Root.Free;
  end;
end;

function TSequentialThinkingTool.ExecuteWithParams(
  const AParams: TSequentialThinkingParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op: string;
  R:  TJSONObject;
begin
  try
    Op := LowerCase(Trim(AParams.Operation));
    if Op = '' then raise Exception.Create('"operation" is required');

    if      Op = 'create_session' then R := DoCreateSession(AParams)
    else if Op = 'add_thought'    then R := DoAddThought(AParams)
    else if Op = 'get_session'    then R := DoGetSession(AParams)
    else if Op = 'list_sessions'  then R := DoListSessions(AParams)
    else if Op = 'conclude'       then R := DoConclude(AParams)
    else if Op = 'delete_session' then R := DoDeleteSession(AParams)
    else if Op = 'clear_all'      then R := DoClearAll(AParams)
    else if Op = 'revise_thought' then R := DoReviseThought(AParams)
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

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-sequential-thinking',
    function: IAiMCPTool
    begin
      Result := TSequentialThinkingTool.Create;
    end);
  WriteLn(ErrOutput, '[MCPService]   + mcp-sequential-thinking');
end;

end.
