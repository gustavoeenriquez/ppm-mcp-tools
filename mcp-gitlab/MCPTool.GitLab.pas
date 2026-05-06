unit MCPTool.GitLab;

{
  MCPTool.GitLab  ·  mcp-gitlab

  GitLab REST API v4 — repos, issues, merge requests, branches, files.
  Auth: Personal Access Token (PRIVATE-TOKEN header).

  Operations:
    list_projects    - list projects the user is a member of
    get_project      - get project details by id or namespace/project
    list_issues      - list issues in a project
    get_issue        - get a single issue by iid
    create_issue     - create a new issue
    update_issue     - update issue (title, description, state, labels, assignee)
    list_mrs         - list merge requests in a project
    get_mr           - get a single merge request by iid
    create_mr        - create a new merge request
    list_branches    - list branches in a project
    list_commits     - list commits in a project/branch
    get_file         - get file content from repository
    create_file      - create a new file in the repository
    update_file      - update an existing file in the repository
    search           - search across GitLab (projects, issues, merge_requests, blobs)
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

  TGitLabParams = class
  private
    FOperation:     string;
    FToken:         string;
    FBaseUrl:       string;
    FProjectId:     string;
    FIssueIid:      Integer;
    FMrIid:         Integer;
    FTitle:         string;
    FDescription:   string;
    FSourceBranch:  string;
    FTargetBranch:  string;
    FFilePath:      string;
    FContent:       string;
    FCommitMessage: string;
    FQuery:         string;
    FScope:         string;
    FState:         string;
    FLabels:        string;
    FAssigneeId:    Integer;
    FLimit:         Integer;
    FPage:          Integer;
  public
    constructor Create;

    [AiMCPSchemaDescription('Operation: list_projects, get_project, list_issues, get_issue, create_issue, update_issue, list_mrs, get_mr, create_mr, list_branches, list_commits, get_file, create_file, update_file, search')]
    property Operation:     string  read FOperation     write FOperation;

    [AiMCPSchemaDescription('GitLab Personal Access Token')]
    property Token:         string  read FToken         write FToken;

    [AiMCPOptional]
    [AiMCPSchemaDescription('GitLab base URL (default: https://gitlab.com/api/v4)')]
    property BaseUrl:       string  read FBaseUrl       write FBaseUrl;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Project ID or namespace/project (e.g. "mygroup/myproject" or "123")')]
    property ProjectId:     string  read FProjectId     write FProjectId;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Issue internal ID (iid) within the project')]
    property IssueIid:      Integer read FIssueIid      write FIssueIid;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Merge request internal ID (iid) within the project')]
    property MrIid:         Integer read FMrIid         write FMrIid;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Title (for create/update issue, create MR)')]
    property Title:         string  read FTitle         write FTitle;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Description / body text')]
    property Description:   string  read FDescription   write FDescription;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Source branch (for create_mr)')]
    property SourceBranch:  string  read FSourceBranch  write FSourceBranch;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Target branch (for create_mr, get_file, create_file, update_file; default: main)')]
    property TargetBranch:  string  read FTargetBranch  write FTargetBranch;

    [AiMCPOptional]
    [AiMCPSchemaDescription('File path in the repository (for get_file, create_file, update_file)')]
    property FilePath:      string  read FFilePath      write FFilePath;

    [AiMCPOptional]
    [AiMCPSchemaDescription('File content (for create_file, update_file)')]
    property Content:       string  read FContent       write FContent;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Commit message (for create_file, update_file)')]
    property CommitMessage: string  read FCommitMessage write FCommitMessage;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Search query (for search, list_issues, list_mrs)')]
    property Query:         string  read FQuery         write FQuery;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Search scope: projects, issues, merge_requests, blobs (for search; default: projects)')]
    property Scope:         string  read FScope         write FScope;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Filter by state: opened, closed, merged (for list_issues, list_mrs)')]
    property State:         string  read FState         write FState;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Comma-separated labels (for create/update issue, list_issues)')]
    property Labels:        string  read FLabels        write FLabels;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Assignee user ID (for create/update issue)')]
    property AssigneeId:    Integer read FAssigneeId    write FAssigneeId;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Maximum results per page (default: 20)')]
    property Limit:         Integer read FLimit         write FLimit;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Page number (default: 1)')]
    property Page:          Integer read FPage          write FPage;
  end;

  TGitLabTool = class(TAiMCPToolBase<TGitLabParams>)
  private
    function ApiGet(const URL, Token: string): string;
    function ApiPost(const URL, Token, Body: string): string;
    function ApiPut(const URL, Token, Body: string): string;
    function GetBase(const P: TGitLabParams): string;
    function EncodeId(const Id: string): string;
    function PaginationSuffix(const P: TGitLabParams): string;
    function ParseArray(const RespStr: string): TJSONObject;
    function DoListProjects(const P: TGitLabParams): TJSONObject;
    function DoGetProject(const P: TGitLabParams): TJSONObject;
    function DoListIssues(const P: TGitLabParams): TJSONObject;
    function DoGetIssue(const P: TGitLabParams): TJSONObject;
    function DoCreateIssue(const P: TGitLabParams): TJSONObject;
    function DoUpdateIssue(const P: TGitLabParams): TJSONObject;
    function DoListMRs(const P: TGitLabParams): TJSONObject;
    function DoGetMR(const P: TGitLabParams): TJSONObject;
    function DoCreateMR(const P: TGitLabParams): TJSONObject;
    function DoListBranches(const P: TGitLabParams): TJSONObject;
    function DoListCommits(const P: TGitLabParams): TJSONObject;
    function DoGetFile(const P: TGitLabParams): TJSONObject;
    function DoCreateFile(const P: TGitLabParams): TJSONObject;
    function DoUpdateFile(const P: TGitLabParams): TJSONObject;
    function DoSearch(const P: TGitLabParams): TJSONObject;
  protected
    function ExecuteWithParams(const AParams: TGitLabParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

procedure RegisterTools(AServer: TAiMCPServer);

implementation

const
  DEFAULT_BASE = 'https://gitlab.com/api/v4';

{ TGitLabParams }

constructor TGitLabParams.Create;
begin
  inherited;
  FLimit        := 20;
  FPage         := 1;
  FTargetBranch := 'main';
  FScope        := 'projects';
end;

{ TGitLabTool }

function TGitLabTool.ApiGet(const URL, Token: string): string;
var
  HTTP: THTTPClient;
  Resp: IHTTPResponse;
begin
  HTTP := THTTPClient.Create;
  try
    HTTP.ConnectionTimeout := 15000;
    HTTP.ResponseTimeout   := 30000;
    Resp := HTTP.Get(URL, nil, [TNameValuePair.Create('PRIVATE-TOKEN', Token)]);
    Result := Resp.ContentAsString;
    if Resp.StatusCode >= 400 then
      raise Exception.CreateFmt('GitLab API HTTP %d: %s',
        [Resp.StatusCode, Result.Substring(0, 300)]);
  finally
    HTTP.Free;
  end;
end;

function TGitLabTool.ApiPost(const URL, Token, Body: string): string;
var
  HTTP:   THTTPClient;
  Resp:   IHTTPResponse;
  Stream: TStringStream;
begin
  HTTP   := THTTPClient.Create;
  Stream := TStringStream.Create(Body, TEncoding.UTF8);
  try
    HTTP.ConnectionTimeout := 15000;
    HTTP.ResponseTimeout   := 30000;
    Resp := HTTP.Post(URL, Stream, nil, [
      TNameValuePair.Create('PRIVATE-TOKEN',  Token),
      TNameValuePair.Create('Content-Type',   'application/json')
    ]);
    Result := Resp.ContentAsString;
    if Resp.StatusCode >= 400 then
      raise Exception.CreateFmt('GitLab API HTTP %d: %s',
        [Resp.StatusCode, Result.Substring(0, 300)]);
  finally
    Stream.Free;
    HTTP.Free;
  end;
end;

function TGitLabTool.ApiPut(const URL, Token, Body: string): string;
var
  HTTP:   THTTPClient;
  Resp:   IHTTPResponse;
  Stream: TStringStream;
begin
  HTTP   := THTTPClient.Create;
  Stream := TStringStream.Create(Body, TEncoding.UTF8);
  try
    HTTP.ConnectionTimeout := 15000;
    HTTP.ResponseTimeout   := 30000;
    Resp := HTTP.Put(URL, Stream, nil, [
      TNameValuePair.Create('PRIVATE-TOKEN', Token),
      TNameValuePair.Create('Content-Type',  'application/json')
    ]);
    Result := Resp.ContentAsString;
    if Resp.StatusCode >= 400 then
      raise Exception.CreateFmt('GitLab API HTTP %d: %s',
        [Resp.StatusCode, Result.Substring(0, 300)]);
  finally
    Stream.Free;
    HTTP.Free;
  end;
end;

function TGitLabTool.GetBase(const P: TGitLabParams): string;
begin
  Result := Trim(P.BaseUrl);
  if Result = '' then Result := DEFAULT_BASE;
  if Result.EndsWith('/') then
    Result := Result.Substring(0, Length(Result) - 1);
end;

function TGitLabTool.EncodeId(const Id: string): string;
begin
  Result := TNetEncoding.URL.EncodeQuery(Id);
end;

function TGitLabTool.PaginationSuffix(const P: TGitLabParams): string;
var
  Lim, Pg: Integer;
begin
  Lim := P.Limit; if Lim <= 0 then Lim := 20;
  Pg  := P.Page;  if Pg  <= 0 then Pg  := 1;
  Result := Format('per_page=%d&page=%d', [Lim, Pg]);
end;

function TGitLabTool.ParseArray(const RespStr: string): TJSONObject;
var
  Parsed: TJSONValue;
  Arr:    TJSONArray;
begin
  Result := TJSONObject.Create;
  Parsed := TJSONObject.ParseJSONValue(RespStr);
  try
    if Parsed is TJSONArray then
    begin
      Arr := Parsed as TJSONArray;
      Result.AddPair('items', Arr.Clone as TJSONArray);
      Result.AddPair('count', TJSONNumber.Create(Arr.Count));
    end
    else if Parsed is TJSONObject then
    begin
      // Single object or error
      var J := Parsed as TJSONObject;
      var Msg := J.GetValue<string>('message', '');
      if Msg <> '' then
        raise Exception.Create('GitLab: ' + Msg);
      Result.AddPair('items', TJSONArray.Create);
      Result.AddPair('count', TJSONNumber.Create(0));
    end
    else
    begin
      Result.AddPair('items', TJSONArray.Create);
      Result.AddPair('count', TJSONNumber.Create(0));
    end;
  finally
    Parsed.Free;
  end;
  Result.AddPair('ok', TJSONTrue.Create);
end;

function TGitLabTool.DoListProjects(const P: TGitLabParams): TJSONObject;
var
  Base, URL: string;
begin
  Base := GetBase(P);
  URL  := Format('%s/projects?membership=true&order_by=last_activity_at&%s',
    [Base, PaginationSuffix(P)]);
  if P.Query <> '' then
    URL := URL + '&search=' + TNetEncoding.URL.EncodeQuery(P.Query);
  Result := ParseArray(ApiGet(URL, P.Token));
end;

function TGitLabTool.DoGetProject(const P: TGitLabParams): TJSONObject;
var
  Base, URL, RespStr: string;
  Parsed:             TJSONValue;
begin
  if P.ProjectId = '' then raise Exception.Create('"projectId" required');
  Base    := GetBase(P);
  URL     := Format('%s/projects/%s', [Base, EncodeId(P.ProjectId)]);
  RespStr := ApiGet(URL, P.Token);
  Parsed  := TJSONObject.ParseJSONValue(RespStr);
  try
    Result := TJSONObject.Create;
    if Parsed is TJSONObject then
      Result.AddPair('project', Parsed.Clone as TJSONObject)
    else
      Result.AddPair('project', TJSONNull.Create);
    Result.AddPair('ok', TJSONTrue.Create);
  finally
    Parsed.Free;
  end;
end;

function TGitLabTool.DoListIssues(const P: TGitLabParams): TJSONObject;
var
  Base, URL: string;
begin
  if P.ProjectId = '' then raise Exception.Create('"projectId" required');
  Base := GetBase(P);
  URL  := Format('%s/projects/%s/issues?%s',
    [Base, EncodeId(P.ProjectId), PaginationSuffix(P)]);
  if P.State  <> '' then URL := URL + '&state='  + P.State;
  if P.Labels <> '' then URL := URL + '&labels=' + TNetEncoding.URL.EncodeQuery(P.Labels);
  if P.Query  <> '' then URL := URL + '&search=' + TNetEncoding.URL.EncodeQuery(P.Query);
  Result := ParseArray(ApiGet(URL, P.Token));
end;

function TGitLabTool.DoGetIssue(const P: TGitLabParams): TJSONObject;
var
  Base, URL, RespStr: string;
  Parsed:             TJSONValue;
begin
  if P.ProjectId = '' then raise Exception.Create('"projectId" required');
  if P.IssueIid  = 0  then raise Exception.Create('"issueIid" required');
  Base    := GetBase(P);
  URL     := Format('%s/projects/%s/issues/%d',
    [Base, EncodeId(P.ProjectId), P.IssueIid]);
  RespStr := ApiGet(URL, P.Token);
  Parsed  := TJSONObject.ParseJSONValue(RespStr);
  try
    Result := TJSONObject.Create;
    if Parsed is TJSONObject then
      Result.AddPair('issue', Parsed.Clone as TJSONObject)
    else
      Result.AddPair('issue', TJSONNull.Create);
    Result.AddPair('ok', TJSONTrue.Create);
  finally
    Parsed.Free;
  end;
end;

function TGitLabTool.DoCreateIssue(const P: TGitLabParams): TJSONObject;
var
  Base, URL, RespStr: string;
  Body, Parsed:       TJSONValue;
  BodyObj:            TJSONObject;
begin
  if P.ProjectId = '' then raise Exception.Create('"projectId" required');
  if P.Title     = '' then raise Exception.Create('"title" required');
  Base    := GetBase(P);
  URL     := Format('%s/projects/%s/issues', [Base, EncodeId(P.ProjectId)]);
  BodyObj := TJSONObject.Create;
  BodyObj.AddPair('title', P.Title);
  if P.Description <> '' then BodyObj.AddPair('description', P.Description);
  if P.Labels      <> '' then BodyObj.AddPair('labels',      P.Labels);
  if P.AssigneeId   > 0  then
    BodyObj.AddPair('assignee_ids', TJSONArray.Create.Add(P.AssigneeId));
  RespStr := ApiPost(URL, P.Token, BodyObj.ToJSON);
  BodyObj.Free;
  Parsed := TJSONObject.ParseJSONValue(RespStr);
  try
    Result := TJSONObject.Create;
    if Parsed is TJSONObject then
      Result.AddPair('issue', Parsed.Clone as TJSONObject)
    else
      Result.AddPair('issue', TJSONNull.Create);
    Result.AddPair('ok', TJSONTrue.Create);
  finally
    Parsed.Free;
  end;
end;

function TGitLabTool.DoUpdateIssue(const P: TGitLabParams): TJSONObject;
var
  Base, URL, RespStr: string;
  BodyObj:            TJSONObject;
  Parsed:             TJSONValue;
begin
  if P.ProjectId = '' then raise Exception.Create('"projectId" required');
  if P.IssueIid  = 0  then raise Exception.Create('"issueIid" required');
  Base    := GetBase(P);
  URL     := Format('%s/projects/%s/issues/%d',
    [Base, EncodeId(P.ProjectId), P.IssueIid]);
  BodyObj := TJSONObject.Create;
  if P.Title       <> '' then BodyObj.AddPair('title',       P.Title);
  if P.Description <> '' then BodyObj.AddPair('description', P.Description);
  if P.State <> '' then
  begin
    if SameText(P.State, 'closed') then
      BodyObj.AddPair('state_event', 'close')
    else
      BodyObj.AddPair('state_event', 'reopen');
  end;
  if P.Labels      <> '' then BodyObj.AddPair('labels',      P.Labels);
  if P.AssigneeId   > 0  then
    BodyObj.AddPair('assignee_ids', TJSONArray.Create.Add(P.AssigneeId));
  RespStr := ApiPut(URL, P.Token, BodyObj.ToJSON);
  BodyObj.Free;
  Parsed := TJSONObject.ParseJSONValue(RespStr);
  try
    Result := TJSONObject.Create;
    if Parsed is TJSONObject then
      Result.AddPair('issue', Parsed.Clone as TJSONObject)
    else
      Result.AddPair('issue', TJSONNull.Create);
    Result.AddPair('ok', TJSONTrue.Create);
  finally
    Parsed.Free;
  end;
end;

function TGitLabTool.DoListMRs(const P: TGitLabParams): TJSONObject;
var
  Base, URL: string;
begin
  if P.ProjectId = '' then raise Exception.Create('"projectId" required');
  Base := GetBase(P);
  URL  := Format('%s/projects/%s/merge_requests?%s',
    [Base, EncodeId(P.ProjectId), PaginationSuffix(P)]);
  if P.State <> '' then URL := URL + '&state=' + P.State;
  if P.Query <> '' then URL := URL + '&search=' + TNetEncoding.URL.EncodeQuery(P.Query);
  Result := ParseArray(ApiGet(URL, P.Token));
end;

function TGitLabTool.DoGetMR(const P: TGitLabParams): TJSONObject;
var
  Base, URL, RespStr: string;
  Parsed:             TJSONValue;
begin
  if P.ProjectId = '' then raise Exception.Create('"projectId" required');
  if P.MrIid     = 0  then raise Exception.Create('"mrIid" required');
  Base    := GetBase(P);
  URL     := Format('%s/projects/%s/merge_requests/%d',
    [Base, EncodeId(P.ProjectId), P.MrIid]);
  RespStr := ApiGet(URL, P.Token);
  Parsed  := TJSONObject.ParseJSONValue(RespStr);
  try
    Result := TJSONObject.Create;
    if Parsed is TJSONObject then
      Result.AddPair('merge_request', Parsed.Clone as TJSONObject)
    else
      Result.AddPair('merge_request', TJSONNull.Create);
    Result.AddPair('ok', TJSONTrue.Create);
  finally
    Parsed.Free;
  end;
end;

function TGitLabTool.DoCreateMR(const P: TGitLabParams): TJSONObject;
var
  Base, URL, Target, RespStr: string;
  BodyObj:                    TJSONObject;
  Parsed:                     TJSONValue;
begin
  if P.ProjectId    = '' then raise Exception.Create('"projectId" required');
  if P.Title        = '' then raise Exception.Create('"title" required');
  if P.SourceBranch = '' then raise Exception.Create('"sourceBranch" required');
  Base   := GetBase(P);
  URL    := Format('%s/projects/%s/merge_requests', [Base, EncodeId(P.ProjectId)]);
  Target := P.TargetBranch; if Target = '' then Target := 'main';
  BodyObj := TJSONObject.Create;
  BodyObj.AddPair('title',         P.Title);
  BodyObj.AddPair('source_branch', P.SourceBranch);
  BodyObj.AddPair('target_branch', Target);
  if P.Description <> '' then BodyObj.AddPair('description', P.Description);
  RespStr := ApiPost(URL, P.Token, BodyObj.ToJSON);
  BodyObj.Free;
  Parsed := TJSONObject.ParseJSONValue(RespStr);
  try
    Result := TJSONObject.Create;
    if Parsed is TJSONObject then
      Result.AddPair('merge_request', Parsed.Clone as TJSONObject)
    else
      Result.AddPair('merge_request', TJSONNull.Create);
    Result.AddPair('ok', TJSONTrue.Create);
  finally
    Parsed.Free;
  end;
end;

function TGitLabTool.DoListBranches(const P: TGitLabParams): TJSONObject;
var
  Base, URL: string;
begin
  if P.ProjectId = '' then raise Exception.Create('"projectId" required');
  Base := GetBase(P);
  URL  := Format('%s/projects/%s/repository/branches?%s',
    [Base, EncodeId(P.ProjectId), PaginationSuffix(P)]);
  if P.Query <> '' then
    URL := URL + '&search=' + TNetEncoding.URL.EncodeQuery(P.Query);
  Result := ParseArray(ApiGet(URL, P.Token));
end;

function TGitLabTool.DoListCommits(const P: TGitLabParams): TJSONObject;
var
  Base, URL: string;
begin
  if P.ProjectId = '' then raise Exception.Create('"projectId" required');
  Base := GetBase(P);
  URL  := Format('%s/projects/%s/repository/commits?%s',
    [Base, EncodeId(P.ProjectId), PaginationSuffix(P)]);
  if P.TargetBranch <> '' then
    URL := URL + '&ref_name=' + TNetEncoding.URL.EncodeQuery(P.TargetBranch);
  Result := ParseArray(ApiGet(URL, P.Token));
end;

function TGitLabTool.DoGetFile(const P: TGitLabParams): TJSONObject;
var
  Base, URL, Ref, RespStr: string;
  Parsed:                  TJSONValue;
  J:                       TJSONObject;
  ContentB64:              string;
  ContentStr:              string;
begin
  if P.ProjectId = '' then raise Exception.Create('"projectId" required');
  if P.FilePath  = '' then raise Exception.Create('"filePath" required');
  Base := GetBase(P);
  Ref  := P.TargetBranch; if Ref = '' then Ref := 'main';
  URL  := Format('%s/projects/%s/repository/files/%s?ref=%s',
    [Base, EncodeId(P.ProjectId),
     TNetEncoding.URL.EncodeQuery(P.FilePath),
     TNetEncoding.URL.EncodeQuery(Ref)]);
  RespStr := ApiGet(URL, P.Token);
  Parsed  := TJSONObject.ParseJSONValue(RespStr);
  try
    Result := TJSONObject.Create;
    if Parsed is TJSONObject then
    begin
      J          := Parsed as TJSONObject;
      ContentB64 := J.GetValue<string>('content', '');
      // Decode base64 content
      ContentStr := '';
      if ContentB64 <> '' then
      try
        var Bytes := TNetEncoding.Base64.DecodeStringToBytes(ContentB64);
        ContentStr := TEncoding.UTF8.GetString(Bytes);
      except
        ContentStr := ContentB64; // binary — return raw b64
      end;
      Result.AddPair('file_path',   J.GetValue<string>('file_path',   ''));
      Result.AddPair('file_name',   J.GetValue<string>('file_name',   ''));
      Result.AddPair('ref',         J.GetValue<string>('ref',         Ref));
      Result.AddPair('encoding',    J.GetValue<string>('encoding',    ''));
      Result.AddPair('size',        TJSONNumber.Create(J.GetValue<Integer>('size', 0)));
      Result.AddPair('content',     ContentStr);
      Result.AddPair('last_commit_id', J.GetValue<string>('last_commit_id', ''));
    end
    else
      Result.AddPair('content', TJSONNull.Create);
    Result.AddPair('ok', TJSONTrue.Create);
  finally
    Parsed.Free;
  end;
end;

function TGitLabTool.DoCreateFile(const P: TGitLabParams): TJSONObject;
var
  Base, URL, Branch, RespStr: string;
  BodyObj:                    TJSONObject;
  Parsed:                     TJSONValue;
  ContentB64:                 string;
begin
  if P.ProjectId     = '' then raise Exception.Create('"projectId" required');
  if P.FilePath      = '' then raise Exception.Create('"filePath" required');
  if P.CommitMessage = '' then raise Exception.Create('"commitMessage" required');
  Base   := GetBase(P);
  Branch := P.TargetBranch; if Branch = '' then Branch := 'main';
  URL    := Format('%s/projects/%s/repository/files/%s',
    [Base, EncodeId(P.ProjectId), TNetEncoding.URL.EncodeQuery(P.FilePath)]);
  ContentB64 := TNetEncoding.Base64.EncodeBytesToString(
    TEncoding.UTF8.GetBytes(P.Content));
  BodyObj := TJSONObject.Create;
  BodyObj.AddPair('branch',         Branch);
  BodyObj.AddPair('content',        ContentB64);
  BodyObj.AddPair('encoding',       'base64');
  BodyObj.AddPair('commit_message', P.CommitMessage);
  RespStr := ApiPost(URL, P.Token, BodyObj.ToJSON);
  BodyObj.Free;
  Parsed := TJSONObject.ParseJSONValue(RespStr);
  try
    Result := TJSONObject.Create;
    if Parsed is TJSONObject then
    begin
      var J := Parsed as TJSONObject;
      Result.AddPair('file_path', J.GetValue<string>('file_path', P.FilePath));
      Result.AddPair('branch',    J.GetValue<string>('branch',    Branch));
    end;
    Result.AddPair('ok', TJSONTrue.Create);
  finally
    Parsed.Free;
  end;
end;

function TGitLabTool.DoUpdateFile(const P: TGitLabParams): TJSONObject;
var
  Base, URL, Branch, RespStr: string;
  BodyObj:                    TJSONObject;
  Parsed:                     TJSONValue;
  ContentB64:                 string;
begin
  if P.ProjectId     = '' then raise Exception.Create('"projectId" required');
  if P.FilePath      = '' then raise Exception.Create('"filePath" required');
  if P.CommitMessage = '' then raise Exception.Create('"commitMessage" required');
  Base   := GetBase(P);
  Branch := P.TargetBranch; if Branch = '' then Branch := 'main';
  URL    := Format('%s/projects/%s/repository/files/%s',
    [Base, EncodeId(P.ProjectId), TNetEncoding.URL.EncodeQuery(P.FilePath)]);
  ContentB64 := TNetEncoding.Base64.EncodeBytesToString(
    TEncoding.UTF8.GetBytes(P.Content));
  BodyObj := TJSONObject.Create;
  BodyObj.AddPair('branch',         Branch);
  BodyObj.AddPair('content',        ContentB64);
  BodyObj.AddPair('encoding',       'base64');
  BodyObj.AddPair('commit_message', P.CommitMessage);

  // PUT via ApiPut
  RespStr := ApiPut(URL, P.Token, BodyObj.ToJSON);
  BodyObj.Free;
  Parsed := TJSONObject.ParseJSONValue(RespStr);
  try
    Result := TJSONObject.Create;
    if Parsed is TJSONObject then
    begin
      var J := Parsed as TJSONObject;
      Result.AddPair('file_path', J.GetValue<string>('file_path', P.FilePath));
      Result.AddPair('branch',    J.GetValue<string>('branch',    Branch));
    end;
    Result.AddPair('ok', TJSONTrue.Create);
  finally
    Parsed.Free;
  end;
end;

function TGitLabTool.DoSearch(const P: TGitLabParams): TJSONObject;
var
  Base, URL, Scope: string;
begin
  if P.Query = '' then raise Exception.Create('"query" required for search');
  Base  := GetBase(P);
  Scope := LowerCase(Trim(P.Scope));
  if Scope = '' then Scope := 'projects';

  if P.ProjectId <> '' then
    // Project-scoped search
    URL := Format('%s/projects/%s/search?scope=%s&search=%s&%s',
      [Base, EncodeId(P.ProjectId), Scope,
       TNetEncoding.URL.EncodeQuery(P.Query), PaginationSuffix(P)])
  else
    // Global search
    URL := Format('%s/search?scope=%s&search=%s&%s',
      [Base, Scope,
       TNetEncoding.URL.EncodeQuery(P.Query), PaginationSuffix(P)]);

  Result := ParseArray(ApiGet(URL, P.Token));
end;

function TGitLabTool.ExecuteWithParams(const AParams: TGitLabParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op: string;
  R:  TJSONObject;
begin
  try
    if Trim(AParams.Token) = '' then
      raise Exception.Create('"token" (Personal Access Token) is required');

    Op := LowerCase(Trim(AParams.Operation));
    if Op = '' then raise Exception.Create('"operation" is required');

    if      Op = 'list_projects'  then R := DoListProjects(AParams)
    else if Op = 'get_project'    then R := DoGetProject(AParams)
    else if Op = 'list_issues'    then R := DoListIssues(AParams)
    else if Op = 'get_issue'      then R := DoGetIssue(AParams)
    else if Op = 'create_issue'   then R := DoCreateIssue(AParams)
    else if Op = 'update_issue'   then R := DoUpdateIssue(AParams)
    else if Op = 'list_mrs'       then R := DoListMRs(AParams)
    else if Op = 'get_mr'         then R := DoGetMR(AParams)
    else if Op = 'create_mr'      then R := DoCreateMR(AParams)
    else if Op = 'list_branches'  then R := DoListBranches(AParams)
    else if Op = 'list_commits'   then R := DoListCommits(AParams)
    else if Op = 'get_file'       then R := DoGetFile(AParams)
    else if Op = 'create_file'    then R := DoCreateFile(AParams)
    else if Op = 'update_file'    then R := DoUpdateFile(AParams)
    else if Op = 'search'         then R := DoSearch(AParams)
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

constructor TGitLabTool.Create;
begin
  inherited;
  FName        := 'mcp-gitlab';
  FDescription :=
    'GitLab REST API v4 — projects, issues, merge requests, branches, commits and files. ' +
    'Requires Personal Access Token. Supports gitlab.com and self-hosted instances. ' +
    'Operations: ' +
    'list_projects (params: query?, limit?, page?), ' +
    'get_project (params: projectId), ' +
    'list_issues (params: projectId, state?, labels?, query?, limit?, page?), ' +
    'get_issue (params: projectId, issueIid), ' +
    'create_issue (params: projectId, title, description?, labels?, assigneeId?), ' +
    'update_issue (params: projectId, issueIid, title?, description?, state?, labels?, assigneeId?), ' +
    'list_mrs (params: projectId, state?, query?, limit?, page?), ' +
    'get_mr (params: projectId, mrIid), ' +
    'create_mr (params: projectId, title, sourceBranch, targetBranch?, description?), ' +
    'list_branches (params: projectId, query?, limit?, page?), ' +
    'list_commits (params: projectId, targetBranch?, limit?, page?), ' +
    'get_file (params: projectId, filePath, targetBranch?), ' +
    'create_file (params: projectId, filePath, content, commitMessage, targetBranch?), ' +
    'update_file (params: projectId, filePath, content, commitMessage, targetBranch?), ' +
    'search (params: query, scope?, projectId?, limit?, page?). ' +
    'scope values: projects, issues, merge_requests, blobs.';
end;

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-gitlab',
    function: IAiMCPTool
    begin
      Result := TGitLabTool.Create;
    end);
  WriteLn(ErrOutput, '[MCPService]   + mcp-gitlab');
end;

end.
