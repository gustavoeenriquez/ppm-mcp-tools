unit MCPTool.Zoom;

{
  MCPTool.Zoom  ·  mcp-zoom  (port 8629)
  Zoom REST API v2 — meetings, webinars, recordings, users.

  Operations:
    list_meetings    - list upcoming meetings for a user
    get_meeting      - get meeting details
    create_meeting   - create a new meeting
    update_meeting   - update meeting settings
    delete_meeting   - delete a meeting
    list_webinars    - list webinars for a user
    get_webinar      - get webinar details
    list_recordings  - list cloud recordings for a user
    get_user         - get user info
    list_users       - list account users
}

interface

uses
  uMakerAi.MCPServer.Core,
  System.JSON;

type
  TZoomParams = class
  private
    FOperation:  string;
    FClientId:   string;
    FSecret:     string;
    FAccountId:  string;
    FUserId:     string;
    FMeetingId:  string;
    FWebinarId:  string;
    FTopic:      string;
    FStartTime:  string;
    FDuration:   Integer;
    FTimezone:   string;
    FAgenda:     string;
    FPassword:   string;
    FType_:      Integer;
    FPageSize:   Integer;
    FNextToken:  string;
    FFrom:       string;
    FTo_:        string;
  public
    constructor Create;

    [AiMCPSchemaDescription('Operation: list_meetings, get_meeting, create_meeting, update_meeting, delete_meeting, list_webinars, get_webinar, list_recordings, get_user, list_users')]
    property Operation:  string  read FOperation  write FOperation;

    [AiMCPSchemaDescription('Zoom OAuth2 Client ID (from marketplace.zoom.us)')]
    property ClientId:   string  read FClientId   write FClientId;

    [AiMCPSchemaDescription('Zoom OAuth2 Client Secret')]
    property Secret:     string  read FSecret     write FSecret;

    [AiMCPSchemaDescription('Zoom Account ID (for Server-to-Server OAuth)')]
    property AccountId:  string  read FAccountId  write FAccountId;

    [AiMCPOptional]
    [AiMCPSchemaDescription('User ID or email (default: me)')]
    property UserId:     string  read FUserId     write FUserId;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Meeting ID for get/update/delete_meeting')]
    property MeetingId:  string  read FMeetingId  write FMeetingId;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Webinar ID for get_webinar')]
    property WebinarId:  string  read FWebinarId  write FWebinarId;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Meeting/webinar topic')]
    property Topic:      string  read FTopic      write FTopic;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Start time in ISO 8601 format: 2024-01-15T10:00:00Z')]
    property StartTime:  string  read FStartTime  write FStartTime;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Duration in minutes (default: 60)')]
    property Duration:   Integer read FDuration   write FDuration;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Timezone (e.g. America/New_York, UTC)')]
    property Timezone:   string  read FTimezone   write FTimezone;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Meeting agenda/description')]
    property Agenda:     string  read FAgenda     write FAgenda;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Meeting password')]
    property Password:   string  read FPassword   write FPassword;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Meeting type: 1=instant, 2=scheduled, 3=recurring no fixed time, 8=recurring fixed time (default: 2)')]
    property MeetType:   Integer read FType_      write FType_;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Page size for list operations (default: 30)')]
    property PageSize:   Integer read FPageSize   write FPageSize;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Next page token for pagination')]
    property NextToken:  string  read FNextToken  write FNextToken;

    [AiMCPOptional]
    [AiMCPSchemaDescription('From date for recordings (YYYY-MM-DD)')]
    property From:       string  read FFrom       write FFrom;

    [AiMCPOptional]
    [AiMCPSchemaDescription('To date for recordings (YYYY-MM-DD)')]
    property To_:        string  read FTo_        write FTo_;
  end;

  TZoomTool = class(TAiMCPToolBase<TZoomParams>)
  private
    function GetToken(const ClientId, Secret, AccountId: string): string;
    function ApiGet(const URL, Token: string): string;
    function ApiPost(const URL, Token, Body: string): string;
    function ApiPatch(const URL, Token, Body: string): string;
    function ApiDelete(const URL, Token: string): string;
    function Wrap(const Raw: string): TJSONObject;
    function DoListMeetings(const P: TZoomParams): TJSONObject;
    function DoGetMeeting(const P: TZoomParams): TJSONObject;
    function DoCreateMeeting(const P: TZoomParams): TJSONObject;
    function DoUpdateMeeting(const P: TZoomParams): TJSONObject;
    function DoDeleteMeeting(const P: TZoomParams): TJSONObject;
    function DoListWebinars(const P: TZoomParams): TJSONObject;
    function DoGetWebinar(const P: TZoomParams): TJSONObject;
    function DoListRecordings(const P: TZoomParams): TJSONObject;
    function DoGetUser(const P: TZoomParams): TJSONObject;
    function DoListUsers(const P: TZoomParams): TJSONObject;
  protected
    function ExecuteWithParams(const AParams: TZoomParams;
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

const
  BASE = 'https://api.zoom.us/v2';
  TOKEN_URL = 'https://zoom.us/oauth/token';

{ TZoomParams }

constructor TZoomParams.Create;
begin
  inherited;
  FUserId   := 'me';
  FDuration := 60;
  FType_    := 2;
  FPageSize := 30;
  FTimezone := 'UTC';
end;

{ TZoomTool }

function TZoomTool.GetToken(const ClientId, Secret, AccountId: string): string;
var
  HTTP:   THTTPClient;
  Stream: TStringStream;
  Resp:   IHTTPResponse;
  Creds:  string;
  J:      TJSONValue;
begin
  Creds  := TNetEncoding.Base64.Encode(ClientId + ':' + Secret);
  HTTP   := THTTPClient.Create;
  Stream := TStringStream.Create(
    'grant_type=account_credentials&account_id=' + AccountId, TEncoding.UTF8);
  try
    Resp := HTTP.Post(TOKEN_URL, Stream, nil,
      [TNameValuePair.Create('Authorization', 'Basic ' + Creds),
       TNameValuePair.Create('Content-Type', 'application/x-www-form-urlencoded')]);
    J := TJSONObject.ParseJSONValue(Resp.ContentAsString(TEncoding.UTF8));
    try
      if Assigned(J) then
        Result := (J as TJSONObject).GetValue<string>('access_token', '')
      else
        Result := '';
    finally
      J.Free;
    end;
  finally
    Stream.Free;
    HTTP.Free;
  end;
end;

function TZoomTool.ApiGet(const URL, Token: string): string;
var
  HTTP: THTTPClient;
  Resp: IHTTPResponse;
begin
  HTTP := THTTPClient.Create;
  try
    Resp   := HTTP.Get(URL, nil,
      [TNameValuePair.Create('Authorization', 'Bearer ' + Token),
       TNameValuePair.Create('Accept', 'application/json')]);
    Result := Resp.ContentAsString(TEncoding.UTF8);
  finally
    HTTP.Free;
  end;
end;

function TZoomTool.ApiPost(const URL, Token, Body: string): string;
var
  HTTP:   THTTPClient;
  Stream: TStringStream;
  Resp:   IHTTPResponse;
begin
  HTTP   := THTTPClient.Create;
  Stream := TStringStream.Create(Body, TEncoding.UTF8);
  try
    Resp   := HTTP.Post(URL, Stream, nil,
      [TNameValuePair.Create('Authorization', 'Bearer ' + Token),
       TNameValuePair.Create('Content-Type', 'application/json')]);
    Result := Resp.ContentAsString(TEncoding.UTF8);
  finally
    Stream.Free;
    HTTP.Free;
  end;
end;

function TZoomTool.ApiPatch(const URL, Token, Body: string): string;
var
  HTTP:   THTTPClient;
  Stream: TStringStream;
  Resp:   IHTTPResponse;
begin
  HTTP   := THTTPClient.Create;
  Stream := TStringStream.Create(Body, TEncoding.UTF8);
  try
    Resp   := HTTP.Patch(URL, Stream, nil,
      [TNameValuePair.Create('Authorization', 'Bearer ' + Token),
       TNameValuePair.Create('Content-Type', 'application/json')]);
    Result := Resp.ContentAsString(TEncoding.UTF8);
  finally
    Stream.Free;
    HTTP.Free;
  end;
end;

function TZoomTool.ApiDelete(const URL, Token: string): string;
var
  HTTP: THTTPClient;
  Resp: IHTTPResponse;
begin
  HTTP := THTTPClient.Create;
  try
    Resp   := HTTP.Delete(URL, nil,
      [TNameValuePair.Create('Authorization', 'Bearer ' + Token)]);
    Result := Resp.ContentAsString(TEncoding.UTF8);
  finally
    HTTP.Free;
  end;
end;

function TZoomTool.Wrap(const Raw: string): TJSONObject;
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

function TZoomTool.DoListMeetings(const P: TZoomParams): TJSONObject;
var
  Token, UserId, URL: string;
  PS: Integer;
begin
  Token  := GetToken(P.ClientId, P.Secret, P.AccountId);
  UserId := Trim(P.UserId); if UserId = '' then UserId := 'me';
  PS     := P.PageSize; if PS <= 0 then PS := 30;
  URL    := Format('%s/users/%s/meetings?type=upcoming&page_size=%d', [BASE, UserId, PS]);
  if Trim(P.NextToken) <> '' then URL := URL + '&next_page_token=' + Trim(P.NextToken);
  Result := Wrap(ApiGet(URL, Token));
end;

function TZoomTool.DoGetMeeting(const P: TZoomParams): TJSONObject;
var
  Token: string;
begin
  if Trim(P.MeetingId) = '' then raise Exception.Create('"meetingId" required for get_meeting');
  Token  := GetToken(P.ClientId, P.Secret, P.AccountId);
  Result := Wrap(ApiGet(BASE + '/meetings/' + Trim(P.MeetingId), Token));
end;

function TZoomTool.DoCreateMeeting(const P: TZoomParams): TJSONObject;
var
  Token, UserId, Body, Topic, ST, TZ, Agenda, Pwd: string;
  Dur, MType: Integer;
begin
  Token  := GetToken(P.ClientId, P.Secret, P.AccountId);
  UserId := Trim(P.UserId); if UserId = '' then UserId := 'me';
  Topic  := Trim(P.Topic);  if Topic = '' then Topic := 'New Meeting';
  ST     := Trim(P.StartTime);
  TZ     := Trim(P.Timezone); if TZ = '' then TZ := 'UTC';
  Dur    := P.Duration; if Dur <= 0 then Dur := 60;
  MType  := P.MeetType; if MType <= 0 then MType := 2;
  Agenda := Trim(P.Agenda);
  Pwd    := Trim(P.Password);

  Body := Format('{"topic":"%s","type":%d,"duration":%d,"timezone":"%s"',
    [Topic.Replace('"','\"'), MType, Dur, TZ]);
  if ST     <> '' then Body := Body + Format(',"start_time":"%s"', [ST]);
  if Agenda <> '' then Body := Body + Format(',"agenda":"%s"', [Agenda.Replace('"','\"')]);
  if Pwd    <> '' then Body := Body + Format(',"password":"%s"', [Pwd]);
  Body := Body + '}';

  Result := Wrap(ApiPost(Format('%s/users/%s/meetings', [BASE, UserId]), Token, Body));
end;

function TZoomTool.DoUpdateMeeting(const P: TZoomParams): TJSONObject;
var
  Token, Body, Topic, ST, Agenda: string;
  Dur: Integer;
begin
  if Trim(P.MeetingId) = '' then raise Exception.Create('"meetingId" required for update_meeting');
  Token  := GetToken(P.ClientId, P.Secret, P.AccountId);
  Topic  := Trim(P.Topic);
  ST     := Trim(P.StartTime);
  Dur    := P.Duration;
  Agenda := Trim(P.Agenda);

  Body := '{';
  if Topic  <> '' then Body := Body + Format('"topic":"%s",', [Topic.Replace('"','\"')]);
  if ST     <> '' then Body := Body + Format('"start_time":"%s",', [ST]);
  if Dur     > 0  then Body := Body + Format('"duration":%d,', [Dur]);
  if Agenda <> '' then Body := Body + Format('"agenda":"%s",', [Agenda.Replace('"','\"')]);
  if Body[Length(Body)] = ',' then
    Body[Length(Body)] := '}' else Body := Body + '}';

  ApiPatch(BASE + '/meetings/' + Trim(P.MeetingId), Token, Body);
  Result := TJSONObject.Create;
  Result.AddPair('ok', TJSONTrue.Create);
  Result.AddPair('updated', TJSONString.Create(Trim(P.MeetingId)));
end;

function TZoomTool.DoDeleteMeeting(const P: TZoomParams): TJSONObject;
var
  Token: string;
begin
  if Trim(P.MeetingId) = '' then raise Exception.Create('"meetingId" required for delete_meeting');
  Token := GetToken(P.ClientId, P.Secret, P.AccountId);
  ApiDelete(BASE + '/meetings/' + Trim(P.MeetingId), Token);
  Result := TJSONObject.Create;
  Result.AddPair('ok', TJSONTrue.Create);
  Result.AddPair('deleted', TJSONString.Create(Trim(P.MeetingId)));
end;

function TZoomTool.DoListWebinars(const P: TZoomParams): TJSONObject;
var
  Token, UserId, URL: string;
  PS: Integer;
begin
  Token  := GetToken(P.ClientId, P.Secret, P.AccountId);
  UserId := Trim(P.UserId); if UserId = '' then UserId := 'me';
  PS     := P.PageSize; if PS <= 0 then PS := 30;
  URL    := Format('%s/users/%s/webinars?page_size=%d', [BASE, UserId, PS]);
  Result := Wrap(ApiGet(URL, Token));
end;

function TZoomTool.DoGetWebinar(const P: TZoomParams): TJSONObject;
var
  Token: string;
begin
  if Trim(P.WebinarId) = '' then raise Exception.Create('"webinarId" required for get_webinar');
  Token  := GetToken(P.ClientId, P.Secret, P.AccountId);
  Result := Wrap(ApiGet(BASE + '/webinars/' + Trim(P.WebinarId), Token));
end;

function TZoomTool.DoListRecordings(const P: TZoomParams): TJSONObject;
var
  Token, UserId, URL, From, To_: string;
  PS: Integer;
begin
  Token  := GetToken(P.ClientId, P.Secret, P.AccountId);
  UserId := Trim(P.UserId); if UserId = '' then UserId := 'me';
  PS     := P.PageSize; if PS <= 0 then PS := 30;
  From   := Trim(P.From);
  To_    := Trim(P.To_);
  URL    := Format('%s/users/%s/recordings?page_size=%d', [BASE, UserId, PS]);
  if From <> '' then URL := URL + '&from=' + From;
  if To_  <> '' then URL := URL + '&to='   + To_;
  Result := Wrap(ApiGet(URL, Token));
end;

function TZoomTool.DoGetUser(const P: TZoomParams): TJSONObject;
var
  Token, UserId: string;
begin
  Token  := GetToken(P.ClientId, P.Secret, P.AccountId);
  UserId := Trim(P.UserId); if UserId = '' then UserId := 'me';
  Result := Wrap(ApiGet(BASE + '/users/' + UserId, Token));
end;

function TZoomTool.DoListUsers(const P: TZoomParams): TJSONObject;
var
  Token, URL: string;
  PS: Integer;
begin
  Token := GetToken(P.ClientId, P.Secret, P.AccountId);
  PS    := P.PageSize; if PS <= 0 then PS := 30;
  URL   := Format('%s/users?page_size=%d', [BASE, PS]);
  if Trim(P.NextToken) <> '' then URL := URL + '&next_page_token=' + Trim(P.NextToken);
  Result := Wrap(ApiGet(URL, Token));
end;

function TZoomTool.ExecuteWithParams(const AParams: TZoomParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op: string;
  R:  TJSONObject;
begin
  try
    if Trim(AParams.ClientId)  = '' then raise Exception.Create('"clientId" required');
    if Trim(AParams.Secret)    = '' then raise Exception.Create('"secret" required');
    if Trim(AParams.AccountId) = '' then raise Exception.Create('"accountId" required');
    Op := LowerCase(Trim(AParams.Operation));
    if Op = '' then raise Exception.Create('"operation" is required');

    if      Op = 'list_meetings'   then R := DoListMeetings(AParams)
    else if Op = 'get_meeting'     then R := DoGetMeeting(AParams)
    else if Op = 'create_meeting'  then R := DoCreateMeeting(AParams)
    else if Op = 'update_meeting'  then R := DoUpdateMeeting(AParams)
    else if Op = 'delete_meeting'  then R := DoDeleteMeeting(AParams)
    else if Op = 'list_webinars'   then R := DoListWebinars(AParams)
    else if Op = 'get_webinar'     then R := DoGetWebinar(AParams)
    else if Op = 'list_recordings' then R := DoListRecordings(AParams)
    else if Op = 'get_user'        then R := DoGetUser(AParams)
    else if Op = 'list_users'      then R := DoListUsers(AParams)
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

constructor TZoomTool.Create;
begin
  inherited;
  FName        := 'mcp-zoom';
  FDescription :=
    'Zoom REST API v2 — meetings, webinars, recordings and users. ' +
    'Requires Server-to-Server OAuth app (clientId, secret, accountId from marketplace.zoom.us). ' +
    'Operations: list_meetings (params: userId?) → upcoming meetings, ' +
    'get_meeting (params: meetingId), ' +
    'create_meeting (params: topic?, startTime?, duration?, timezone?, agenda?, password?, meetType?), ' +
    'update_meeting (params: meetingId, topic?, startTime?, duration?, agenda?), ' +
    'delete_meeting (params: meetingId), ' +
    'list_webinars (params: userId?), ' +
    'get_webinar (params: webinarId), ' +
    'list_recordings (params: userId?, from?, to?, pageSize?), ' +
    'get_user (params: userId?), ' +
    'list_users (params: pageSize?, nextToken?).';
end;

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-zoom',
    function: IAiMCPTool
    begin
      Result := TZoomTool.Create;
    end);
  WriteLn(ErrOutput, '[MCPService]   + mcp-zoom');
end;

end.
