unit MCPTool.Zendesk;

{
  MCPTool.Zendesk  ·  mcp-zendesk  (port 8630)
  Zendesk REST API v2 — tickets, users, organizations, search.

  Operations:
    list_tickets   - list tickets
    get_ticket     - get ticket details
    create_ticket  - create a new ticket
    update_ticket  - update ticket fields
    delete_ticket  - delete a ticket
    list_users     - list users
    get_user       - get user details
    create_user    - create a user
    list_orgs      - list organizations
    get_org        - get organization details
    search         - full-text search across Zendesk
    list_comments  - list ticket comments
    add_comment    - add comment to ticket
}

interface

uses
  uMakerAi.MCPServer.Core,
  System.JSON;

type
  TZendeskParams = class
  private
    FOperation:  string;
    FSubdomain:  string;
    FEmail:      string;
    FApiToken:   string;
    FTicketId:   string;
    FUserId:     string;
    FOrgId:      string;
    FSubject:    string;
    FBody:       string;
    FPriority:   string;
    FStatus:     string;
    FType_:      string;
    FAssigneeId: string;
    FRequesterId:string;
    FTags:       string;
    FQuery:      string;
    FPageSize:   Integer;
    FPage:       Integer;
    FPublic_:    Boolean;
  public
    constructor Create;

    [AiMCPSchemaDescription('Operation: list_tickets, get_ticket, create_ticket, update_ticket, delete_ticket, list_users, get_user, create_user, list_orgs, get_org, search, list_comments, add_comment')]
    property Operation:   string  read FOperation   write FOperation;

    [AiMCPSchemaDescription('Zendesk subdomain (e.g. "mycompany" from mycompany.zendesk.com)')]
    property Subdomain:   string  read FSubdomain   write FSubdomain;

    [AiMCPSchemaDescription('Agent email address')]
    property Email:       string  read FEmail       write FEmail;

    [AiMCPSchemaDescription('Zendesk API token (Admin > Apps & Integrations > APIs > Zendesk API)')]
    property ApiToken:    string  read FApiToken    write FApiToken;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Ticket ID for get/update/delete/add_comment operations')]
    property TicketId:    string  read FTicketId    write FTicketId;

    [AiMCPOptional]
    [AiMCPSchemaDescription('User ID for get_user')]
    property UserId:      string  read FUserId      write FUserId;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Organization ID for get_org')]
    property OrgId:       string  read FOrgId       write FOrgId;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Ticket subject')]
    property Subject:     string  read FSubject     write FSubject;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Ticket body / comment text')]
    property Body:        string  read FBody        write FBody;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Priority: urgent, high, normal, low')]
    property Priority:    string  read FPriority    write FPriority;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Status: new, open, pending, hold, solved, closed')]
    property Status:      string  read FStatus      write FStatus;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Ticket type: problem, incident, question, task')]
    property TicketType:  string  read FType_       write FType_;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Assignee user ID')]
    property AssigneeId:  string  read FAssigneeId  write FAssigneeId;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Requester user ID (for create_ticket)')]
    property RequesterId: string  read FRequesterId write FRequesterId;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Comma-separated tags')]
    property Tags:        string  read FTags        write FTags;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Search query string (for search operation)')]
    property Query:       string  read FQuery       write FQuery;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Page size (default: 25)')]
    property PageSize:    Integer read FPageSize    write FPageSize;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Page number (default: 1)')]
    property Page:        Integer read FPage        write FPage;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Public comment (true) or internal note (false). Default: true')]
    property IsPublic:    Boolean read FPublic_     write FPublic_;
  end;

  TZendeskTool = class(TAiMCPToolBase<TZendeskParams>)
  private
    function BaseURL(const Subdomain: string): string;
    function AuthHeader(const Email, ApiToken: string): string;
    function ApiGet(const URL, Auth: string): string;
    function ApiPost(const URL, Auth, Body: string): string;
    function ApiPut(const URL, Auth, Body: string): string;
    function ApiDelete(const URL, Auth: string): string;
    function Wrap(const Raw: string): TJSONObject;
    function TagsToArray(const Tags: string): string;
    function DoListTickets(const P: TZendeskParams): TJSONObject;
    function DoGetTicket(const P: TZendeskParams): TJSONObject;
    function DoCreateTicket(const P: TZendeskParams): TJSONObject;
    function DoUpdateTicket(const P: TZendeskParams): TJSONObject;
    function DoDeleteTicket(const P: TZendeskParams): TJSONObject;
    function DoListUsers(const P: TZendeskParams): TJSONObject;
    function DoGetUser(const P: TZendeskParams): TJSONObject;
    function DoCreateUser(const P: TZendeskParams): TJSONObject;
    function DoListOrgs(const P: TZendeskParams): TJSONObject;
    function DoGetOrg(const P: TZendeskParams): TJSONObject;
    function DoSearch(const P: TZendeskParams): TJSONObject;
    function DoListComments(const P: TZendeskParams): TJSONObject;
    function DoAddComment(const P: TZendeskParams): TJSONObject;
  protected
    function ExecuteWithParams(const AParams: TZendeskParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

procedure RegisterTools(AServer: TAiMCPServer);

implementation

uses
  System.SysUtils,
  System.Classes,
  System.NetEncoding,
  System.Net.HttpClient,
  System.Net.URLClient;

{ TZendeskParams }

constructor TZendeskParams.Create;
begin
  inherited;
  FPageSize := 25;
  FPage     := 1;
  FPublic_  := True;
  FPriority := 'normal';
end;

{ TZendeskTool }

function TZendeskTool.BaseURL(const Subdomain: string): string;
begin
  Result := 'https://' + Subdomain + '.zendesk.com/api/v2';
end;

function TZendeskTool.AuthHeader(const Email, ApiToken: string): string;
begin
  Result := 'Basic ' + TNetEncoding.Base64.Encode(Email + '/token:' + ApiToken);
end;

function TZendeskTool.ApiGet(const URL, Auth: string): string;
var
  HTTP: THTTPClient;
  Resp: IHTTPResponse;
begin
  HTTP := THTTPClient.Create;
  try
    Resp   := HTTP.Get(URL, nil,
      [TNameValuePair.Create('Authorization', Auth),
       TNameValuePair.Create('Accept', 'application/json')]);
    Result := Resp.ContentAsString(TEncoding.UTF8);
  finally
    HTTP.Free;
  end;
end;

function TZendeskTool.ApiPost(const URL, Auth, Body: string): string;
var
  HTTP:   THTTPClient;
  Stream: TStringStream;
  Resp:   IHTTPResponse;
begin
  HTTP   := THTTPClient.Create;
  Stream := TStringStream.Create(Body, TEncoding.UTF8);
  try
    Resp   := HTTP.Post(URL, Stream, nil,
      [TNameValuePair.Create('Authorization', Auth),
       TNameValuePair.Create('Content-Type', 'application/json')]);
    Result := Resp.ContentAsString(TEncoding.UTF8);
  finally
    Stream.Free;
    HTTP.Free;
  end;
end;

function TZendeskTool.ApiPut(const URL, Auth, Body: string): string;
var
  HTTP:   THTTPClient;
  Stream: TStringStream;
  Resp:   IHTTPResponse;
begin
  HTTP   := THTTPClient.Create;
  Stream := TStringStream.Create(Body, TEncoding.UTF8);
  try
    Resp   := HTTP.Put(URL, Stream, nil,
      [TNameValuePair.Create('Authorization', Auth),
       TNameValuePair.Create('Content-Type', 'application/json')]);
    Result := Resp.ContentAsString(TEncoding.UTF8);
  finally
    Stream.Free;
    HTTP.Free;
  end;
end;

function TZendeskTool.ApiDelete(const URL, Auth: string): string;
var
  HTTP: THTTPClient;
  Resp: IHTTPResponse;
begin
  HTTP := THTTPClient.Create;
  try
    Resp   := HTTP.Delete(URL, nil,
      [TNameValuePair.Create('Authorization', Auth)]);
    Result := Resp.ContentAsString(TEncoding.UTF8);
  finally
    HTTP.Free;
  end;
end;

function TZendeskTool.Wrap(const Raw: string): TJSONObject;
var
  J: TJSONValue;
begin
  J := TJSONObject.ParseJSONValue(Raw);
  if Assigned(J) then
  begin
    if J is TJSONObject then
      Result := J as TJSONObject
    else
    begin
      Result := TJSONObject.Create;
      Result.AddPair('data', J);
    end;
  end
  else
  begin
    Result := TJSONObject.Create;
    if Raw <> '' then Result.AddPair('raw', TJSONString.Create(Raw));
  end;
  Result.AddPair('ok', TJSONTrue.Create);
end;

function TZendeskTool.TagsToArray(const Tags: string): string;
var
  Parts: TArray<string>;
  i: Integer;
begin
  if Trim(Tags) = '' then begin Result := '[]'; Exit; end;
  Parts  := Tags.Split([',']);
  Result := '[';
  for i := 0 to High(Parts) do
  begin
    if i > 0 then Result := Result + ',';
    Result := Result + '"' + Trim(Parts[i]).Replace('"','\"') + '"';
  end;
  Result := Result + ']';
end;

function TZendeskTool.DoListTickets(const P: TZendeskParams): TJSONObject;
var
  Auth, URL: string;
  PS, Pg: Integer;
begin
  Auth := AuthHeader(P.Email, P.ApiToken);
  PS   := P.PageSize; if PS <= 0 then PS := 25;
  Pg   := P.Page;     if Pg <= 0 then Pg := 1;
  URL  := Format('%s/tickets.json?per_page=%d&page=%d', [BaseURL(P.Subdomain), PS, Pg]);
  if Trim(P.Status) <> '' then URL := URL + '&status=' + Trim(P.Status);
  Result := Wrap(ApiGet(URL, Auth));
end;

function TZendeskTool.DoGetTicket(const P: TZendeskParams): TJSONObject;
begin
  if Trim(P.TicketId) = '' then raise Exception.Create('"ticketId" required');
  Result := Wrap(ApiGet(BaseURL(P.Subdomain) + '/tickets/' + Trim(P.TicketId) + '.json',
    AuthHeader(P.Email, P.ApiToken)));
end;

function TZendeskTool.DoCreateTicket(const P: TZendeskParams): TJSONObject;
var
  Auth, Body, Subject, BodyText, Priority, Status, Tags: string;
begin
  Auth     := AuthHeader(P.Email, P.ApiToken);
  Subject  := Trim(P.Subject);  if Subject = '' then Subject := 'New Ticket';
  BodyText := Trim(P.Body);
  Priority := Trim(P.Priority); if Priority = '' then Priority := 'normal';
  Status   := Trim(P.Status);   if Status   = '' then Status   := 'new';
  Tags     := TagsToArray(P.Tags);

  Body := Format('{"ticket":{"subject":"%s","comment":{"body":"%s"},"priority":"%s","status":"%s","tags":%s',
    [Subject.Replace('"','\"'),
     BodyText.Replace('\','\\').Replace('"','\"').Replace(#10,'\n').Replace(#13,''),
     Priority, Status, Tags]);
  if Trim(P.RequesterId) <> '' then Body := Body + Format(',"requester_id":%s', [Trim(P.RequesterId)]);
  if Trim(P.AssigneeId)  <> '' then Body := Body + Format(',"assignee_id":%s',  [Trim(P.AssigneeId)]);
  if Trim(P.TicketType)  <> '' then Body := Body + Format(',"type":"%s"', [Trim(P.TicketType)]);
  Body := Body + '}}';

  Result := Wrap(ApiPost(BaseURL(P.Subdomain) + '/tickets.json', Auth, Body));
end;

function TZendeskTool.DoUpdateTicket(const P: TZendeskParams): TJSONObject;
var
  Auth, Body, Parts: string;
begin
  if Trim(P.TicketId) = '' then raise Exception.Create('"ticketId" required for update_ticket');
  Auth  := AuthHeader(P.Email, P.ApiToken);
  Parts := '';
  if Trim(P.Subject)   <> '' then Parts := Parts + Format('"subject":"%s",', [Trim(P.Subject).Replace('"','\"')]);
  if Trim(P.Status)    <> '' then Parts := Parts + Format('"status":"%s",',   [Trim(P.Status)]);
  if Trim(P.Priority)  <> '' then Parts := Parts + Format('"priority":"%s",', [Trim(P.Priority)]);
  if Trim(P.AssigneeId)<> '' then Parts := Parts + Format('"assignee_id":%s,', [Trim(P.AssigneeId)]);
  if Trim(P.Tags)      <> '' then Parts := Parts + Format('"tags":%s,', [TagsToArray(P.Tags)]);
  if Parts <> '' then Parts := Copy(Parts, 1, Length(Parts) - 1);
  Body := '{"ticket":{' + Parts + '}}';
  Result := Wrap(ApiPut(BaseURL(P.Subdomain) + '/tickets/' + Trim(P.TicketId) + '.json', Auth, Body));
end;

function TZendeskTool.DoDeleteTicket(const P: TZendeskParams): TJSONObject;
begin
  if Trim(P.TicketId) = '' then raise Exception.Create('"ticketId" required for delete_ticket');
  ApiDelete(BaseURL(P.Subdomain) + '/tickets/' + Trim(P.TicketId) + '.json',
    AuthHeader(P.Email, P.ApiToken));
  Result := TJSONObject.Create;
  Result.AddPair('ok', TJSONTrue.Create);
  Result.AddPair('deleted', TJSONString.Create(Trim(P.TicketId)));
end;

function TZendeskTool.DoListUsers(const P: TZendeskParams): TJSONObject;
var
  Auth, URL: string;
  PS, Pg: Integer;
begin
  Auth := AuthHeader(P.Email, P.ApiToken);
  PS   := P.PageSize; if PS <= 0 then PS := 25;
  Pg   := P.Page;     if Pg <= 0 then Pg := 1;
  URL  := Format('%s/users.json?per_page=%d&page=%d', [BaseURL(P.Subdomain), PS, Pg]);
  Result := Wrap(ApiGet(URL, Auth));
end;

function TZendeskTool.DoGetUser(const P: TZendeskParams): TJSONObject;
begin
  if Trim(P.UserId) = '' then raise Exception.Create('"userId" required for get_user');
  Result := Wrap(ApiGet(BaseURL(P.Subdomain) + '/users/' + Trim(P.UserId) + '.json',
    AuthHeader(P.Email, P.ApiToken)));
end;

function TZendeskTool.DoCreateUser(const P: TZendeskParams): TJSONObject;
var
  Auth, Body, Name, Email_: string;
begin
  Auth   := AuthHeader(P.Email, P.ApiToken);
  Name   := Trim(P.Subject); if Name = '' then raise Exception.Create('"subject" (name) required for create_user');
  Email_ := Trim(P.Body);
  var EmailPart := '';
  if Email_ <> '' then EmailPart := ',"email":"' + Email_.Replace('"','\"') + '"';
  Body   := Format('{"user":{"name":"%s"%s}}',
    [Name.Replace('"','\"'), EmailPart]);
  Result := Wrap(ApiPost(BaseURL(P.Subdomain) + '/users.json', Auth, Body));
end;

function TZendeskTool.DoListOrgs(const P: TZendeskParams): TJSONObject;
var
  Auth, URL: string;
  PS, Pg: Integer;
begin
  Auth := AuthHeader(P.Email, P.ApiToken);
  PS   := P.PageSize; if PS <= 0 then PS := 25;
  Pg   := P.Page;     if Pg <= 0 then Pg := 1;
  URL  := Format('%s/organizations.json?per_page=%d&page=%d', [BaseURL(P.Subdomain), PS, Pg]);
  Result := Wrap(ApiGet(URL, Auth));
end;

function TZendeskTool.DoGetOrg(const P: TZendeskParams): TJSONObject;
begin
  if Trim(P.OrgId) = '' then raise Exception.Create('"orgId" required for get_org');
  Result := Wrap(ApiGet(BaseURL(P.Subdomain) + '/organizations/' + Trim(P.OrgId) + '.json',
    AuthHeader(P.Email, P.ApiToken)));
end;

function TZendeskTool.DoSearch(const P: TZendeskParams): TJSONObject;
var
  Q, URL: string;
  PS: Integer;
begin
  Q := Trim(P.Query);
  if Q = '' then raise Exception.Create('"query" required for search');
  PS  := P.PageSize; if PS <= 0 then PS := 25;
  URL := Format('%s/search.json?query=%s&per_page=%d&page=%d',
    [BaseURL(P.Subdomain), Q.Replace(' ', '+'), PS, P.Page]);
  Result := Wrap(ApiGet(URL, AuthHeader(P.Email, P.ApiToken)));
end;

function TZendeskTool.DoListComments(const P: TZendeskParams): TJSONObject;
begin
  if Trim(P.TicketId) = '' then raise Exception.Create('"ticketId" required for list_comments');
  Result := Wrap(ApiGet(
    BaseURL(P.Subdomain) + '/tickets/' + Trim(P.TicketId) + '/comments.json',
    AuthHeader(P.Email, P.ApiToken)));
end;

function TZendeskTool.DoAddComment(const P: TZendeskParams): TJSONObject;
var
  Auth, Body, Pub: string;
begin
  if Trim(P.TicketId) = '' then raise Exception.Create('"ticketId" required for add_comment');
  if Trim(P.Body)     = '' then raise Exception.Create('"body" required for add_comment');
  Auth := AuthHeader(P.Email, P.ApiToken);
  if P.IsPublic then Pub := 'true' else Pub := 'false';
  Body := Format('{"ticket":{"comment":{"body":"%s","public":%s}}}',
    [Trim(P.Body).Replace('\','\\').Replace('"','\"').Replace(#10,'\n').Replace(#13,''), Pub]);
  Result := Wrap(ApiPut(BaseURL(P.Subdomain) + '/tickets/' + Trim(P.TicketId) + '.json', Auth, Body));
end;

function TZendeskTool.ExecuteWithParams(const AParams: TZendeskParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op: string;
  R:  TJSONObject;
begin
  try
    if Trim(AParams.Subdomain) = '' then raise Exception.Create('"subdomain" required');
    if Trim(AParams.Email)     = '' then raise Exception.Create('"email" required');
    if Trim(AParams.ApiToken)  = '' then raise Exception.Create('"apiToken" required');
    Op := LowerCase(Trim(AParams.Operation));
    if Op = '' then raise Exception.Create('"operation" is required');

    if      Op = 'list_tickets'  then R := DoListTickets(AParams)
    else if Op = 'get_ticket'    then R := DoGetTicket(AParams)
    else if Op = 'create_ticket' then R := DoCreateTicket(AParams)
    else if Op = 'update_ticket' then R := DoUpdateTicket(AParams)
    else if Op = 'delete_ticket' then R := DoDeleteTicket(AParams)
    else if Op = 'list_users'    then R := DoListUsers(AParams)
    else if Op = 'get_user'      then R := DoGetUser(AParams)
    else if Op = 'create_user'   then R := DoCreateUser(AParams)
    else if Op = 'list_orgs'     then R := DoListOrgs(AParams)
    else if Op = 'get_org'       then R := DoGetOrg(AParams)
    else if Op = 'search'        then R := DoSearch(AParams)
    else if Op = 'list_comments' then R := DoListComments(AParams)
    else if Op = 'add_comment'   then R := DoAddComment(AParams)
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

constructor TZendeskTool.Create;
begin
  inherited;
  FName        := 'mcp-zendesk';
  FDescription :=
    'Zendesk REST API v2 — tickets, users, organizations, comments and search. ' +
    'Requires subdomain, email and API token. ' +
    'Operations: list_tickets (params: status?, pageSize?, page?), ' +
    'get_ticket (params: ticketId), ' +
    'create_ticket (params: subject, body, priority?, status?, tags?, requesterId?, assigneeId?, ticketType?), ' +
    'update_ticket (params: ticketId, subject?, status?, priority?, assigneeId?, tags?), ' +
    'delete_ticket (params: ticketId), ' +
    'list_users (params: pageSize?, page?), ' +
    'get_user (params: userId), ' +
    'create_user (params: subject=name, body=email), ' +
    'list_orgs (params: pageSize?, page?), ' +
    'get_org (params: orgId), ' +
    'search (params: query, pageSize?, page?), ' +
    'list_comments (params: ticketId), ' +
    'add_comment (params: ticketId, body, isPublic?).';
end;

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-zendesk',
    function: IAiMCPTool
    begin
      Result := TZendeskTool.Create;
    end);
  WriteLn(ErrOutput, '[MCPService]   + mcp-zendesk');
end;

end.
