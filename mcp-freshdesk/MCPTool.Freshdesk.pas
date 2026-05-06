unit MCPTool.Freshdesk;

{
  MCPTool.Freshdesk  ·  mcp-freshdesk  (port 8633)
  Freshdesk REST API v2.

  Operations:
    list_tickets   - list tickets
    get_ticket     - get ticket by id
    create_ticket  - create a ticket
    update_ticket  - update a ticket
    delete_ticket  - delete a ticket
    list_contacts  - list contacts
    get_contact    - get contact by id
    create_contact - create a contact
    list_agents    - list agents
    get_agent      - get agent by id
    list_groups    - list groups
    add_note       - add a note to a ticket
    list_replies   - list replies for a ticket
}

interface

uses
  uMakerAi.MCPServer.Core,
  System.JSON;

type
  TFreshdeskParams = class
  private
    FOperation  : string;
    FApiKey     : string;
    FDomain     : string;
    FTicketId   : string;
    FContactId  : string;
    FAgentId    : string;
    FSubject    : string;
    FDescription: string;
    FEmail      : string;
    FPriority   : Integer;
    FStatus     : Integer;
    FType_      : string;
    FBody       : string;
    FIsPublic   : Boolean;
    FPage       : Integer;
  public
    constructor Create;

    [AiMCPSchemaDescription('Operation: list_tickets, get_ticket, create_ticket, update_ticket, delete_ticket, list_contacts, get_contact, create_contact, list_agents, get_agent, list_groups, add_note, list_replies')]
    property Operation  : string  read FOperation   write FOperation;

    [AiMCPSchemaDescription('Freshdesk API key')]
    property ApiKey     : string  read FApiKey      write FApiKey;

    [AiMCPSchemaDescription('Freshdesk subdomain (e.g. mycompany for mycompany.freshdesk.com)')]
    property Domain     : string  read FDomain      write FDomain;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Ticket ID')]
    property TicketId   : string  read FTicketId    write FTicketId;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Contact ID')]
    property ContactId  : string  read FContactId   write FContactId;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Agent ID')]
    property AgentId    : string  read FAgentId     write FAgentId;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Ticket subject')]
    property Subject    : string  read FSubject     write FSubject;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Ticket description / note body')]
    property Description: string  read FDescription write FDescription;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Requester email')]
    property Email      : string  read FEmail       write FEmail;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Ticket priority: 1=Low, 2=Medium, 3=High, 4=Urgent (default 1)')]
    property Priority   : Integer read FPriority    write FPriority;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Ticket status: 2=Open, 3=Pending, 4=Resolved, 5=Closed (default 2)')]
    property Status     : Integer read FStatus      write FStatus;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Ticket type e.g. Question, Incident, Problem, Feature Request')]
    property Type_      : string  read FType_       write FType_;

    [AiMCPOptional]
    [AiMCPSchemaDescription('JSON body for create/update (overrides individual fields if provided)')]
    property Body       : string  read FBody        write FBody;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Whether note is public (default: false = private note)')]
    property IsPublic   : Boolean read FIsPublic    write FIsPublic;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Page number for list operations (default 1)')]
    property Page       : Integer read FPage        write FPage;
  end;

  TFreshdeskTool = class(TAiMCPToolBase<TFreshdeskParams>)
  private
    function BaseURL(const Domain: string): string;
    function AuthHeader(const ApiKey: string): string;
    function ApiGet(const URL, Auth: string): TJSONObject;
    function ApiPost(const URL, Auth, Body: string): TJSONObject;
    function ApiPut(const URL, Auth, Body: string): TJSONObject;
    function ApiDelete(const URL, Auth: string): TJSONObject;

    function DoListTickets(const P: TFreshdeskParams): TJSONObject;
    function DoGetTicket(const P: TFreshdeskParams): TJSONObject;
    function DoCreateTicket(const P: TFreshdeskParams): TJSONObject;
    function DoUpdateTicket(const P: TFreshdeskParams): TJSONObject;
    function DoDeleteTicket(const P: TFreshdeskParams): TJSONObject;
    function DoListContacts(const P: TFreshdeskParams): TJSONObject;
    function DoGetContact(const P: TFreshdeskParams): TJSONObject;
    function DoCreateContact(const P: TFreshdeskParams): TJSONObject;
    function DoListAgents(const P: TFreshdeskParams): TJSONObject;
    function DoGetAgent(const P: TFreshdeskParams): TJSONObject;
    function DoListGroups(const P: TFreshdeskParams): TJSONObject;
    function DoAddNote(const P: TFreshdeskParams): TJSONObject;
    function DoListReplies(const P: TFreshdeskParams): TJSONObject;
  protected
    function ExecuteWithParams(const AParams: TFreshdeskParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

procedure RegisterTools(AServer: TAiMCPServer);

implementation

uses
  System.SysUtils,
  System.Classes,
  System.Net.HttpClient,
  System.Net.URLClient,
  System.NetEncoding;

{ TFreshdeskParams }

constructor TFreshdeskParams.Create;
begin
  inherited;
  FPriority := 1;
  FStatus   := 2;
  FPage     := 1;
  FIsPublic := False;
end;

{ TFreshdeskTool }

constructor TFreshdeskTool.Create;
begin
  inherited;
  FName        := 'mcp-freshdesk';
  FDescription :=
    'Freshdesk REST API v2 — tickets, contacts, agents, groups. ' +
    'Operations: list_tickets (page?), get_ticket (ticketId), ' +
    'create_ticket (subject, email, description, priority?, status?, type?), ' +
    'update_ticket (ticketId, body), delete_ticket (ticketId), ' +
    'list_contacts, get_contact (contactId), create_contact (email, subject), ' +
    'list_agents, get_agent (agentId), list_groups, ' +
    'add_note (ticketId, description, isPublic?), list_replies (ticketId). ' +
    'Auth: apiKey, domain (subdomain only).';
end;

function TFreshdeskTool.BaseURL(const Domain: string): string;
begin
  Result := 'https://' + Trim(Domain) + '.freshdesk.com/api/v2';
end;

function TFreshdeskTool.AuthHeader(const ApiKey: string): string;
var
  Encoded: string;
  Bytes: TBytes;
begin
  Bytes   := TEncoding.UTF8.GetBytes(Trim(ApiKey) + ':X');
  Encoded := TNetEncoding.Base64.EncodeBytesToString(Bytes);
  Result  := 'Basic ' + Encoded;
end;

function TFreshdeskTool.ApiGet(const URL, Auth: string): TJSONObject;
var
  HTTP: THTTPClient;
  Resp: IHTTPResponse;
  Raw: string;
  J: TJSONValue;
begin
  HTTP := THTTPClient.Create;
  try
    Resp := HTTP.Get(URL, nil,
      [TNameValuePair.Create('Authorization', Auth),
       TNameValuePair.Create('Accept', 'application/json')]);
    Raw := Resp.ContentAsString();
    J := TJSONObject.ParseJSONValue(Raw);
    if J is TJSONObject then
      Result := J as TJSONObject
    else
    begin
      Result := TJSONObject.Create;
      if J <> nil then
      begin
        Result.AddPair('data', J);
      end;
    end;
    if Result = nil then Result := TJSONObject.Create;
  finally
    HTTP.Free;
  end;
end;

function TFreshdeskTool.ApiPost(const URL, Auth, Body: string): TJSONObject;
var
  HTTP: THTTPClient;
  Resp: IHTTPResponse;
  Strm: TStringStream;
begin
  HTTP := THTTPClient.Create;
  Strm := TStringStream.Create(Body, TEncoding.UTF8);
  try
    Resp := HTTP.Post(URL, Strm, nil,
      [TNameValuePair.Create('Authorization', Auth),
       TNameValuePair.Create('Content-Type',  'application/json'),
       TNameValuePair.Create('Accept',         'application/json')]);
    Result := TJSONObject.ParseJSONValue(Resp.ContentAsString()) as TJSONObject;
    if Result = nil then Result := TJSONObject.Create;
  finally
    Strm.Free;
    HTTP.Free;
  end;
end;

function TFreshdeskTool.ApiPut(const URL, Auth, Body: string): TJSONObject;
var
  HTTP: THTTPClient;
  Resp: IHTTPResponse;
  Strm: TStringStream;
begin
  HTTP := THTTPClient.Create;
  Strm := TStringStream.Create(Body, TEncoding.UTF8);
  try
    Resp := HTTP.Put(URL, Strm, nil,
      [TNameValuePair.Create('Authorization', Auth),
       TNameValuePair.Create('Content-Type',  'application/json'),
       TNameValuePair.Create('Accept',         'application/json')]);
    Result := TJSONObject.ParseJSONValue(Resp.ContentAsString()) as TJSONObject;
    if Result = nil then Result := TJSONObject.Create;
  finally
    Strm.Free;
    HTTP.Free;
  end;
end;

function TFreshdeskTool.ApiDelete(const URL, Auth: string): TJSONObject;
var
  HTTP: THTTPClient;
  Resp: IHTTPResponse;
begin
  HTTP := THTTPClient.Create;
  try
    Resp := HTTP.Delete(URL, nil,
      [TNameValuePair.Create('Authorization', Auth)]);
    Result := TJSONObject.Create;
    Result.AddPair('status', IntToStr(Resp.StatusCode));
    Result.AddPair('ok', TJSONBool.Create(Resp.StatusCode < 300));
  finally
    HTTP.Free;
  end;
end;

function TFreshdeskTool.DoListTickets(const P: TFreshdeskParams): TJSONObject;
var
  Auth: string;
  Pg: Integer;
begin
  Auth := AuthHeader(P.ApiKey);
  Pg   := P.Page; if Pg < 1 then Pg := 1;
  Result := ApiGet(
    Format('%s/tickets?page=%d', [BaseURL(P.Domain), Pg]),
    Auth);
end;

function TFreshdeskTool.DoGetTicket(const P: TFreshdeskParams): TJSONObject;
begin
  if Trim(P.TicketId) = '' then raise Exception.Create('"ticketId" required');
  Result := ApiGet(
    BaseURL(P.Domain) + '/tickets/' + Trim(P.TicketId),
    AuthHeader(P.ApiKey));
end;

function TFreshdeskTool.DoCreateTicket(const P: TFreshdeskParams): TJSONObject;
var
  Auth, Body: string;
  Pri, Stat: Integer;
begin
  if Trim(P.Email)       = '' then raise Exception.Create('"email" required for create_ticket');
  if Trim(P.Subject)     = '' then raise Exception.Create('"subject" required for create_ticket');
  if Trim(P.Description) = '' then raise Exception.Create('"description" required for create_ticket');
  Auth := AuthHeader(P.ApiKey);
  Pri  := P.Priority; if Pri < 1 then Pri := 1;
  Stat := P.Status;   if Stat < 2 then Stat := 2;

  if Trim(P.Body) <> '' then
    Body := Trim(P.Body)
  else
  begin
    var TypePart := '';
    if Trim(P.Type_) <> '' then
      TypePart := ',"type":"' + Trim(P.Type_).Replace('"','\"') + '"';
    Body := Format(
      '{"subject":"%s","description":"%s","email":"%s","priority":%d,"status":%d%s}',
      [Trim(P.Subject).Replace('"','\"'),
       Trim(P.Description).Replace('"','\"').Replace(#10,'\n').Replace(#13,''),
       Trim(P.Email).Replace('"','\"'),
       Pri, Stat, TypePart]);
  end;
  Result := ApiPost(BaseURL(P.Domain) + '/tickets', Auth, Body);
end;

function TFreshdeskTool.DoUpdateTicket(const P: TFreshdeskParams): TJSONObject;
var
  Auth: string;
begin
  if Trim(P.TicketId) = '' then raise Exception.Create('"ticketId" required');
  if Trim(P.Body)     = '' then raise Exception.Create('"body" (JSON) required for update_ticket');
  Auth := AuthHeader(P.ApiKey);
  Result := ApiPut(BaseURL(P.Domain) + '/tickets/' + Trim(P.TicketId), Auth, Trim(P.Body));
end;

function TFreshdeskTool.DoDeleteTicket(const P: TFreshdeskParams): TJSONObject;
begin
  if Trim(P.TicketId) = '' then raise Exception.Create('"ticketId" required');
  Result := ApiDelete(
    BaseURL(P.Domain) + '/tickets/' + Trim(P.TicketId),
    AuthHeader(P.ApiKey));
end;

function TFreshdeskTool.DoListContacts(const P: TFreshdeskParams): TJSONObject;
var
  Pg: Integer;
begin
  Pg := P.Page; if Pg < 1 then Pg := 1;
  Result := ApiGet(
    Format('%s/contacts?page=%d', [BaseURL(P.Domain), Pg]),
    AuthHeader(P.ApiKey));
end;

function TFreshdeskTool.DoGetContact(const P: TFreshdeskParams): TJSONObject;
begin
  if Trim(P.ContactId) = '' then raise Exception.Create('"contactId" required');
  Result := ApiGet(
    BaseURL(P.Domain) + '/contacts/' + Trim(P.ContactId),
    AuthHeader(P.ApiKey));
end;

function TFreshdeskTool.DoCreateContact(const P: TFreshdeskParams): TJSONObject;
var
  Auth, Body, NamePart: string;
begin
  if Trim(P.Email) = '' then raise Exception.Create('"email" required for create_contact');
  Auth := AuthHeader(P.ApiKey);
  NamePart := '';
  if Trim(P.Subject) <> '' then
    NamePart := ',"name":"' + Trim(P.Subject).Replace('"','\"') + '"';
  Body := '{"email":"' + Trim(P.Email).Replace('"','\"') + '"' + NamePart + '}';
  Result := ApiPost(BaseURL(P.Domain) + '/contacts', Auth, Body);
end;

function TFreshdeskTool.DoListAgents(const P: TFreshdeskParams): TJSONObject;
begin
  Result := ApiGet(BaseURL(P.Domain) + '/agents', AuthHeader(P.ApiKey));
end;

function TFreshdeskTool.DoGetAgent(const P: TFreshdeskParams): TJSONObject;
begin
  if Trim(P.AgentId) = '' then raise Exception.Create('"agentId" required');
  Result := ApiGet(
    BaseURL(P.Domain) + '/agents/' + Trim(P.AgentId),
    AuthHeader(P.ApiKey));
end;

function TFreshdeskTool.DoListGroups(const P: TFreshdeskParams): TJSONObject;
begin
  Result := ApiGet(BaseURL(P.Domain) + '/groups', AuthHeader(P.ApiKey));
end;

function TFreshdeskTool.DoAddNote(const P: TFreshdeskParams): TJSONObject;
var
  Auth, Body, Priv: string;
begin
  if Trim(P.TicketId)   = '' then raise Exception.Create('"ticketId" required for add_note');
  if Trim(P.Description) = '' then raise Exception.Create('"description" required for add_note');
  Auth := AuthHeader(P.ApiKey);
  if P.IsPublic then Priv := 'false' else Priv := 'true';
  Body := Format('{"body":"%s","private":%s}',
    [Trim(P.Description).Replace('\','\\').Replace('"','\"').Replace(#10,'\n').Replace(#13,''),
     Priv]);
  Result := ApiPost(
    BaseURL(P.Domain) + '/tickets/' + Trim(P.TicketId) + '/notes',
    Auth, Body);
end;

function TFreshdeskTool.DoListReplies(const P: TFreshdeskParams): TJSONObject;
begin
  if Trim(P.TicketId) = '' then raise Exception.Create('"ticketId" required for list_replies');
  Result := ApiGet(
    BaseURL(P.Domain) + '/tickets/' + Trim(P.TicketId) + '/reply',
    AuthHeader(P.ApiKey));
end;

function TFreshdeskTool.ExecuteWithParams(const AParams: TFreshdeskParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op: string;
  R:  TJSONObject;
begin
  try
    Op := LowerCase(Trim(AParams.Operation));
    if Op = '' then raise Exception.Create('"operation" is required');
    if Trim(AParams.ApiKey) = '' then raise Exception.Create('"apiKey" required');
    if Trim(AParams.Domain) = '' then raise Exception.Create('"domain" required');

    if      Op = 'list_tickets'   then R := DoListTickets(AParams)
    else if Op = 'get_ticket'     then R := DoGetTicket(AParams)
    else if Op = 'create_ticket'  then R := DoCreateTicket(AParams)
    else if Op = 'update_ticket'  then R := DoUpdateTicket(AParams)
    else if Op = 'delete_ticket'  then R := DoDeleteTicket(AParams)
    else if Op = 'list_contacts'  then R := DoListContacts(AParams)
    else if Op = 'get_contact'    then R := DoGetContact(AParams)
    else if Op = 'create_contact' then R := DoCreateContact(AParams)
    else if Op = 'list_agents'    then R := DoListAgents(AParams)
    else if Op = 'get_agent'      then R := DoGetAgent(AParams)
    else if Op = 'list_groups'    then R := DoListGroups(AParams)
    else if Op = 'add_note'       then R := DoAddNote(AParams)
    else if Op = 'list_replies'   then R := DoListReplies(AParams)
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
  AServer.RegisterTool('mcp-freshdesk',
    function: IAiMCPTool
    begin
      Result := TFreshdeskTool.Create;
    end);
  WriteLn(ErrOutput, '[MCPService]   + mcp-freshdesk');
end;

end.
