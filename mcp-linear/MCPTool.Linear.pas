unit MCPTool.Linear;

{
  MCPTool.Linear  ·  mcp-linear

  Linear issue tracker via GraphQL API (api.linear.app/graphql).
  Requires Personal API key or OAuth token.

  Operations:
    list_teams    - list all teams in the workspace
    list_issues   - list issues (optionally filtered by team, state, assignee, priority)
    get_issue     - get a single issue by ID
    create_issue  - create a new issue
    update_issue  - update an issue (title, description, state, priority, assignee)
    list_projects - list projects (optionally filtered by team)
    get_project   - get a single project by ID
    list_cycles   - list cycles (sprints) for a team
    list_states   - list workflow states for a team
    search        - search issues by text
}

interface

uses
  uMakerAi.MCPServer.Core,
  System.SysUtils,
  System.JSON,
  System.Classes,
  System.Net.HttpClient,
  System.Net.URLClient,
  System.NetEncoding;

type

  TLinearParams = class
  private
    FOperation:   string;
    FToken:       string;
    FTeamId:      string;
    FIssueId:     string;
    FProjectId:   string;
    FStateId:     string;
    FAssigneeId:  string;
    FTitle:       string;
    FDescription: string;
    FPriority:    Integer;
    FQuery:       string;
    FFirst:       Integer;
  public
    constructor Create;

    [AiMCPSchemaDescription('Operation: list_teams, list_issues, get_issue, create_issue, update_issue, list_projects, get_project, list_cycles, list_states, search')]
    property Operation:   string  read FOperation   write FOperation;

    [AiMCPSchemaDescription('Linear Personal API key or OAuth token')]
    property Token:       string  read FToken       write FToken;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Team ID (for list_issues, create_issue, list_cycles, list_states, list_projects)')]
    property TeamId:      string  read FTeamId      write FTeamId;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Issue ID (for get_issue, update_issue)')]
    property IssueId:     string  read FIssueId     write FIssueId;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Project ID (for get_project)')]
    property ProjectId:   string  read FProjectId   write FProjectId;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Workflow state ID (for create_issue, update_issue, or filter in list_issues)')]
    property StateId:     string  read FStateId     write FStateId;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Assignee user ID (for create_issue, update_issue, or filter in list_issues)')]
    property AssigneeId:  string  read FAssigneeId  write FAssigneeId;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Issue title (for create_issue, update_issue)')]
    property Title:       string  read FTitle       write FTitle;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Issue description in markdown (for create_issue, update_issue)')]
    property Description: string  read FDescription write FDescription;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Priority: 0=No priority, 1=Urgent, 2=High, 3=Medium, 4=Low')]
    property Priority:    Integer read FPriority    write FPriority;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Search text (for search, list_issues)')]
    property Query:       string  read FQuery       write FQuery;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Max results to return (default: 25)')]
    property First:       Integer read FFirst       write FFirst;
  end;

  TLinearTool = class(TAiMCPToolBase<TLinearParams>)
  private
    function GraphQL(const Token, Query, Variables: string): TJSONObject;
    function EscapeGql(const S: string): string;
    function DoListTeams(const P: TLinearParams): TJSONObject;
    function DoListIssues(const P: TLinearParams): TJSONObject;
    function DoGetIssue(const P: TLinearParams): TJSONObject;
    function DoCreateIssue(const P: TLinearParams): TJSONObject;
    function DoUpdateIssue(const P: TLinearParams): TJSONObject;
    function DoListProjects(const P: TLinearParams): TJSONObject;
    function DoGetProject(const P: TLinearParams): TJSONObject;
    function DoListCycles(const P: TLinearParams): TJSONObject;
    function DoListStates(const P: TLinearParams): TJSONObject;
    function DoSearch(const P: TLinearParams): TJSONObject;
  protected
    function ExecuteWithParams(const AParams: TLinearParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

procedure RegisterTools(AServer: TAiMCPServer);

implementation

const
  LINEAR_API = 'https://api.linear.app/graphql';

{ TLinearParams }

constructor TLinearParams.Create;
begin
  inherited;
  FFirst    := 25;
  FPriority := -1;
end;

{ TLinearTool }

function TLinearTool.EscapeGql(const S: string): string;
begin
  Result := S.Replace('\', '\\')
              .Replace('"', '\"')
              .Replace(#10, '\n')
              .Replace(#13, '');
end;

function TLinearTool.GraphQL(const Token, Query, Variables: string): TJSONObject;
var
  HTTP:    THTTPClient;
  Resp:    IHTTPResponse;
  Stream:  TStringStream;
  ReqBody: TJSONObject;
  RespStr: string;
  Parsed:  TJSONValue;
begin
  ReqBody := TJSONObject.Create;
  ReqBody.AddPair('query', Query);
  if Trim(Variables) <> '' then
  begin
    var VarsVal := TJSONObject.ParseJSONValue(Variables);
    if VarsVal <> nil then
      ReqBody.AddPair('variables', VarsVal);
  end;

  HTTP   := THTTPClient.Create;
  Stream := TStringStream.Create(ReqBody.ToJSON, TEncoding.UTF8);
  ReqBody.Free;
  try
    HTTP.ConnectionTimeout := 15000;
    HTTP.ResponseTimeout   := 30000;
    Resp := HTTP.Post(LINEAR_API, Stream, nil, [
      TNameValuePair.Create('Authorization', 'Bearer ' + Token),
      TNameValuePair.Create('Content-Type',  'application/json')
    ]);
    RespStr := Resp.ContentAsString;
    if Resp.StatusCode >= 400 then
      raise Exception.CreateFmt('Linear API HTTP %d: %s',
        [Resp.StatusCode, RespStr.Substring(0, 300)]);
  finally
    Stream.Free;
    HTTP.Free;
  end;

  Parsed := TJSONObject.ParseJSONValue(RespStr);
  if Parsed is TJSONObject then
    Result := Parsed as TJSONObject
  else
  begin
    Parsed.Free;
    raise Exception.Create('Invalid response from Linear API');
  end;

  // Check for GraphQL errors
  var ErrArr: TJSONArray := nil;
  if Result.TryGetValue<TJSONArray>('errors', ErrArr) and (ErrArr <> nil) and (ErrArr.Count > 0) then
  begin
    var ErrMsg := (ErrArr.Items[0] as TJSONObject).GetValue<string>('message', 'Unknown error');
    Result.Free;
    raise Exception.Create('Linear GraphQL: ' + ErrMsg);
  end;
end;

function TLinearTool.DoListTeams(const P: TLinearParams): TJSONObject;
const
  GQL =
    'query { ' +
    '  teams { ' +
    '    nodes { id name key description } ' +
    '  } ' +
    '}';
var
  Resp:  TJSONObject;
  Nodes: TJSONArray;
begin
  Resp := GraphQL(P.Token, GQL, '');
  try
    Nodes := nil;
    var Data: TJSONObject := nil;
    if Resp.TryGetValue<TJSONObject>('data', Data) then
    begin
      var Teams: TJSONObject := nil;
      if Data.TryGetValue<TJSONObject>('teams', Teams) then
        Teams.TryGetValue<TJSONArray>('nodes', Nodes);
    end;

    Result := TJSONObject.Create;
    if Nodes <> nil then
    begin
      Result.AddPair('teams', Nodes.Clone as TJSONArray);
      Result.AddPair('count', TJSONNumber.Create(Nodes.Count));
    end
    else
    begin
      Result.AddPair('teams', TJSONArray.Create);
      Result.AddPair('count', TJSONNumber.Create(0));
    end;
    Result.AddPair('ok', TJSONTrue.Create);
  finally
    Resp.Free;
  end;
end;

function TLinearTool.DoListIssues(const P: TLinearParams): TJSONObject;
var
  FilterParts: TStringList;
  Filter:      string;
  First:       Integer;
  GQL:         string;
  Resp:        TJSONObject;
  Nodes:       TJSONArray;
begin
  First := P.First; if First <= 0 then First := 25;

  FilterParts := TStringList.Create;
  try
    if P.TeamId     <> '' then FilterParts.Add(Format('team: { id: { eq: "%s" } }',     [EscapeGql(P.TeamId)]));
    if P.AssigneeId <> '' then FilterParts.Add(Format('assignee: { id: { eq: "%s" } }', [EscapeGql(P.AssigneeId)]));
    if P.StateId    <> '' then FilterParts.Add(Format('state: { id: { eq: "%s" } }',    [EscapeGql(P.StateId)]));
    if P.Query      <> '' then FilterParts.Add(Format('title: { containsIgnoreCase: "%s" }', [EscapeGql(P.Query)]));

    if FilterParts.Count > 0 then
      Filter := 'filter: { ' + String.Join(', ', FilterParts.ToStringArray) + ' }'
    else
      Filter := '';
  finally
    FilterParts.Free;
  end;

  if Filter <> '' then
    GQL := Format(
      'query { ' +
      '  issues(first: %d, %s) { ' +
      '    nodes { id title description priority url ' +
      '      state { id name type } ' +
      '      team { id name key } ' +
      '      assignee { id name email } ' +
      '      createdAt updatedAt completedAt ' +
      '    } ' +
      '  } ' +
      '}',
      [First, Filter])
  else
    GQL := Format(
      'query { ' +
      '  issues(first: %d) { ' +
      '    nodes { id title description priority url ' +
      '      state { id name type } ' +
      '      team { id name key } ' +
      '      assignee { id name email } ' +
      '      createdAt updatedAt completedAt ' +
      '    } ' +
      '  } ' +
      '}',
      [First]);

  Resp := GraphQL(P.Token, GQL, '');
  try
    Nodes := nil;
    var Data: TJSONObject := nil;
    if Resp.TryGetValue<TJSONObject>('data', Data) then
    begin
      var Issues: TJSONObject := nil;
      if Data.TryGetValue<TJSONObject>('issues', Issues) then
        Issues.TryGetValue<TJSONArray>('nodes', Nodes);
    end;

    Result := TJSONObject.Create;
    if Nodes <> nil then
    begin
      Result.AddPair('issues', Nodes.Clone as TJSONArray);
      Result.AddPair('count',  TJSONNumber.Create(Nodes.Count));
    end
    else
    begin
      Result.AddPair('issues', TJSONArray.Create);
      Result.AddPair('count',  TJSONNumber.Create(0));
    end;
    Result.AddPair('ok', TJSONTrue.Create);
  finally
    Resp.Free;
  end;
end;

function TLinearTool.DoGetIssue(const P: TLinearParams): TJSONObject;
var
  GQL:  string;
  Resp: TJSONObject;
begin
  if P.IssueId = '' then raise Exception.Create('"issueId" required');
  GQL := Format(
    'query { ' +
    '  issue(id: "%s") { ' +
    '    id title description priority url ' +
    '    state { id name type } ' +
    '    team { id name key } ' +
    '    assignee { id name email } ' +
    '    comments(first: 10) { nodes { id body user { name } createdAt } } ' +
    '    createdAt updatedAt completedAt ' +
    '  } ' +
    '}',
    [EscapeGql(P.IssueId)]
  );

  Resp := GraphQL(P.Token, GQL, '');
  try
    Result := TJSONObject.Create;
    var Data: TJSONObject := nil;
    if Resp.TryGetValue<TJSONObject>('data', Data) then
    begin
      var Issue := Data.GetValue('issue');
      if Issue <> nil then
        Result.AddPair('issue', Issue.Clone as TJSONValue)
      else
        Result.AddPair('issue', TJSONNull.Create);
    end
    else
      Result.AddPair('issue', TJSONNull.Create);
    Result.AddPair('ok', TJSONTrue.Create);
  finally
    Resp.Free;
  end;
end;

function TLinearTool.DoCreateIssue(const P: TLinearParams): TJSONObject;
var
  InputParts: TStringList;
  Input:      string;
  GQL:        string;
  Resp:       TJSONObject;
begin
  if P.TeamId = '' then raise Exception.Create('"teamId" required');
  if P.Title  = '' then raise Exception.Create('"title" required');

  InputParts := TStringList.Create;
  try
    InputParts.Add(Format('teamId: "%s"', [EscapeGql(P.TeamId)]));
    InputParts.Add(Format('title: "%s"',  [EscapeGql(P.Title)]));
    if P.Description <> '' then
      InputParts.Add(Format('description: "%s"', [EscapeGql(P.Description)]));
    if P.StateId    <> '' then
      InputParts.Add(Format('stateId: "%s"', [EscapeGql(P.StateId)]));
    if P.AssigneeId <> '' then
      InputParts.Add(Format('assigneeId: "%s"', [EscapeGql(P.AssigneeId)]));
    if P.Priority >= 0 then
      InputParts.Add(Format('priority: %d', [P.Priority]));
    Input := String.Join(', ', InputParts.ToStringArray);
  finally
    InputParts.Free;
  end;

  GQL := Format(
    'mutation { ' +
    '  issueCreate(input: { %s }) { ' +
    '    success ' +
    '    issue { id title url state { name } team { name } createdAt } ' +
    '  } ' +
    '}',
    [Input]
  );

  Resp := GraphQL(P.Token, GQL, '');
  try
    Result := TJSONObject.Create;
    var Data: TJSONObject := nil;
    if Resp.TryGetValue<TJSONObject>('data', Data) then
    begin
      var Payload: TJSONObject := nil;
      if Data.TryGetValue<TJSONObject>('issueCreate', Payload) then
      begin
        Result.AddPair('success', TJSONBool.Create(Payload.GetValue<Boolean>('success', False)));
        var Issue := Payload.GetValue('issue');
        if Issue <> nil then
          Result.AddPair('issue', Issue.Clone as TJSONValue);
      end;
    end;
    Result.AddPair('ok', TJSONTrue.Create);
  finally
    Resp.Free;
  end;
end;

function TLinearTool.DoUpdateIssue(const P: TLinearParams): TJSONObject;
var
  InputParts: TStringList;
  Input:      string;
  GQL:        string;
  Resp:       TJSONObject;
begin
  if P.IssueId = '' then raise Exception.Create('"issueId" required');

  InputParts := TStringList.Create;
  try
    if P.Title       <> '' then InputParts.Add(Format('title: "%s"',       [EscapeGql(P.Title)]));
    if P.Description <> '' then InputParts.Add(Format('description: "%s"', [EscapeGql(P.Description)]));
    if P.StateId     <> '' then InputParts.Add(Format('stateId: "%s"',     [EscapeGql(P.StateId)]));
    if P.AssigneeId  <> '' then InputParts.Add(Format('assigneeId: "%s"',  [EscapeGql(P.AssigneeId)]));
    if P.Priority    >= 0  then InputParts.Add(Format('priority: %d',      [P.Priority]));
    if InputParts.Count = 0 then
      raise Exception.Create('At least one field to update is required');
    Input := String.Join(', ', InputParts.ToStringArray);
  finally
    InputParts.Free;
  end;

  GQL := Format(
    'mutation { ' +
    '  issueUpdate(id: "%s", input: { %s }) { ' +
    '    success ' +
    '    issue { id title url state { name } updatedAt } ' +
    '  } ' +
    '}',
    [EscapeGql(P.IssueId), Input]
  );

  Resp := GraphQL(P.Token, GQL, '');
  try
    Result := TJSONObject.Create;
    var Data: TJSONObject := nil;
    if Resp.TryGetValue<TJSONObject>('data', Data) then
    begin
      var Payload: TJSONObject := nil;
      if Data.TryGetValue<TJSONObject>('issueUpdate', Payload) then
      begin
        Result.AddPair('success', TJSONBool.Create(Payload.GetValue<Boolean>('success', False)));
        var Issue := Payload.GetValue('issue');
        if Issue <> nil then
          Result.AddPair('issue', Issue.Clone as TJSONValue);
      end;
    end;
    Result.AddPair('ok', TJSONTrue.Create);
  finally
    Resp.Free;
  end;
end;

function TLinearTool.DoListProjects(const P: TLinearParams): TJSONObject;
var
  Filter: string;
  First:  Integer;
  GQL:    string;
  Resp:   TJSONObject;
  Nodes:  TJSONArray;
begin
  First := P.First; if First <= 0 then First := 25;
  if P.TeamId <> '' then
    Filter := Format(', filter: { teams: { id: { eq: "%s" } } }', [EscapeGql(P.TeamId)])
  else
    Filter := '';

  GQL := Format(
    'query { ' +
    '  projects(first: %d%s) { ' +
    '    nodes { id name description state ' +
    '      startDate targetDate ' +
    '      teams { nodes { id name } } ' +
    '    } ' +
    '  } ' +
    '}',
    [First, Filter]
  );

  Resp := GraphQL(P.Token, GQL, '');
  try
    Nodes := nil;
    var Data: TJSONObject := nil;
    if Resp.TryGetValue<TJSONObject>('data', Data) then
    begin
      var Projects: TJSONObject := nil;
      if Data.TryGetValue<TJSONObject>('projects', Projects) then
        Projects.TryGetValue<TJSONArray>('nodes', Nodes);
    end;

    Result := TJSONObject.Create;
    if Nodes <> nil then
    begin
      Result.AddPair('projects', Nodes.Clone as TJSONArray);
      Result.AddPair('count',    TJSONNumber.Create(Nodes.Count));
    end
    else
    begin
      Result.AddPair('projects', TJSONArray.Create);
      Result.AddPair('count',    TJSONNumber.Create(0));
    end;
    Result.AddPair('ok', TJSONTrue.Create);
  finally
    Resp.Free;
  end;
end;

function TLinearTool.DoGetProject(const P: TLinearParams): TJSONObject;
var
  GQL:  string;
  Resp: TJSONObject;
begin
  if P.ProjectId = '' then raise Exception.Create('"projectId" required');
  GQL := Format(
    'query { ' +
    '  project(id: "%s") { ' +
    '    id name description state ' +
    '    startDate targetDate ' +
    '    teams { nodes { id name } } ' +
    '    members { nodes { id name email } } ' +
    '  } ' +
    '}',
    [EscapeGql(P.ProjectId)]
  );

  Resp := GraphQL(P.Token, GQL, '');
  try
    Result := TJSONObject.Create;
    var Data: TJSONObject := nil;
    if Resp.TryGetValue<TJSONObject>('data', Data) then
    begin
      var Project := Data.GetValue('project');
      if Project <> nil then
        Result.AddPair('project', Project.Clone as TJSONValue)
      else
        Result.AddPair('project', TJSONNull.Create);
    end
    else
      Result.AddPair('project', TJSONNull.Create);
    Result.AddPair('ok', TJSONTrue.Create);
  finally
    Resp.Free;
  end;
end;

function TLinearTool.DoListCycles(const P: TLinearParams): TJSONObject;
var
  GQL:   string;
  Resp:  TJSONObject;
  Nodes: TJSONArray;
begin
  if P.TeamId = '' then raise Exception.Create('"teamId" required for list_cycles');
  GQL := Format(
    'query { ' +
    '  team(id: "%s") { ' +
    '    cycles { ' +
    '      nodes { id number name startsAt endsAt completedAt progress } ' +
    '    } ' +
    '  } ' +
    '}',
    [EscapeGql(P.TeamId)]
  );

  Resp := GraphQL(P.Token, GQL, '');
  try
    Nodes := nil;
    var Data: TJSONObject := nil;
    if Resp.TryGetValue<TJSONObject>('data', Data) then
    begin
      var Team: TJSONObject := nil;
      if Data.TryGetValue<TJSONObject>('team', Team) then
      begin
        var Cycles: TJSONObject := nil;
        if Team.TryGetValue<TJSONObject>('cycles', Cycles) then
          Cycles.TryGetValue<TJSONArray>('nodes', Nodes);
      end;
    end;

    Result := TJSONObject.Create;
    if Nodes <> nil then
    begin
      Result.AddPair('cycles', Nodes.Clone as TJSONArray);
      Result.AddPair('count',  TJSONNumber.Create(Nodes.Count));
    end
    else
    begin
      Result.AddPair('cycles', TJSONArray.Create);
      Result.AddPair('count',  TJSONNumber.Create(0));
    end;
    Result.AddPair('ok', TJSONTrue.Create);
  finally
    Resp.Free;
  end;
end;

function TLinearTool.DoListStates(const P: TLinearParams): TJSONObject;
var
  GQL:   string;
  Resp:  TJSONObject;
  Nodes: TJSONArray;
begin
  if P.TeamId = '' then raise Exception.Create('"teamId" required for list_states');
  GQL := Format(
    'query { ' +
    '  team(id: "%s") { ' +
    '    states { ' +
    '      nodes { id name type color position } ' +
    '    } ' +
    '  } ' +
    '}',
    [EscapeGql(P.TeamId)]
  );

  Resp := GraphQL(P.Token, GQL, '');
  try
    Nodes := nil;
    var Data: TJSONObject := nil;
    if Resp.TryGetValue<TJSONObject>('data', Data) then
    begin
      var Team: TJSONObject := nil;
      if Data.TryGetValue<TJSONObject>('team', Team) then
      begin
        var States: TJSONObject := nil;
        if Team.TryGetValue<TJSONObject>('states', States) then
          States.TryGetValue<TJSONArray>('nodes', Nodes);
      end;
    end;

    Result := TJSONObject.Create;
    if Nodes <> nil then
    begin
      Result.AddPair('states', Nodes.Clone as TJSONArray);
      Result.AddPair('count',  TJSONNumber.Create(Nodes.Count));
    end
    else
    begin
      Result.AddPair('states', TJSONArray.Create);
      Result.AddPair('count',  TJSONNumber.Create(0));
    end;
    Result.AddPair('ok', TJSONTrue.Create);
  finally
    Resp.Free;
  end;
end;

function TLinearTool.DoSearch(const P: TLinearParams): TJSONObject;
var
  First: Integer;
  GQL:   string;
  Resp:  TJSONObject;
  Nodes: TJSONArray;
begin
  if P.Query = '' then raise Exception.Create('"query" required for search');
  First := P.First; if First <= 0 then First := 25;

  GQL := Format(
    'query { ' +
    '  issueSearch(query: "%s", first: %d) { ' +
    '    nodes { id title description priority url ' +
    '      state { name } team { name key } assignee { name } ' +
    '      createdAt updatedAt ' +
    '    } ' +
    '  } ' +
    '}',
    [EscapeGql(P.Query), First]
  );

  Resp := GraphQL(P.Token, GQL, '');
  try
    Nodes := nil;
    var Data: TJSONObject := nil;
    if Resp.TryGetValue<TJSONObject>('data', Data) then
    begin
      var IssueSearch: TJSONObject := nil;
      if Data.TryGetValue<TJSONObject>('issueSearch', IssueSearch) then
        IssueSearch.TryGetValue<TJSONArray>('nodes', Nodes);
    end;

    Result := TJSONObject.Create;
    if Nodes <> nil then
    begin
      Result.AddPair('results', Nodes.Clone as TJSONArray);
      Result.AddPair('count',   TJSONNumber.Create(Nodes.Count));
    end
    else
    begin
      Result.AddPair('results', TJSONArray.Create);
      Result.AddPair('count',   TJSONNumber.Create(0));
    end;
    Result.AddPair('ok', TJSONTrue.Create);
  finally
    Resp.Free;
  end;
end;

function TLinearTool.ExecuteWithParams(const AParams: TLinearParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op: string;
  R:  TJSONObject;
begin
  try
    if Trim(AParams.Token) = '' then
      raise Exception.Create('"token" (API key) is required');

    Op := LowerCase(Trim(AParams.Operation));
    if Op = '' then raise Exception.Create('"operation" is required');

    if      Op = 'list_teams'    then R := DoListTeams(AParams)
    else if Op = 'list_issues'   then R := DoListIssues(AParams)
    else if Op = 'get_issue'     then R := DoGetIssue(AParams)
    else if Op = 'create_issue'  then R := DoCreateIssue(AParams)
    else if Op = 'update_issue'  then R := DoUpdateIssue(AParams)
    else if Op = 'list_projects' then R := DoListProjects(AParams)
    else if Op = 'get_project'   then R := DoGetProject(AParams)
    else if Op = 'list_cycles'   then R := DoListCycles(AParams)
    else if Op = 'list_states'   then R := DoListStates(AParams)
    else if Op = 'search'        then R := DoSearch(AParams)
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

constructor TLinearTool.Create;
begin
  inherited;
  FName        := 'mcp-linear';
  FDescription :=
    'Linear issue tracker via GraphQL API. Requires Personal API key. ' +
    'Operations: ' +
    'list_teams (no required params), ' +
    'list_issues (params: teamId?, stateId?, assigneeId?, query?, first?), ' +
    'get_issue (params: issueId), ' +
    'create_issue (params: teamId, title, description?, stateId?, assigneeId?, priority?), ' +
    'update_issue (params: issueId, title?, description?, stateId?, assigneeId?, priority?), ' +
    'list_projects (params: teamId?, first?), ' +
    'get_project (params: projectId), ' +
    'list_cycles (params: teamId), ' +
    'list_states (params: teamId), ' +
    'search (params: query, first?). ' +
    'priority: 0=No priority, 1=Urgent, 2=High, 3=Medium, 4=Low.';
end;

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-linear',
    function: IAiMCPTool
    begin
      Result := TLinearTool.Create;
    end);
  WriteLn(ErrOutput, '[MCPService]   + mcp-linear');
end;

end.
