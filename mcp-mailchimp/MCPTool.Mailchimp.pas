unit MCPTool.Mailchimp;

{
  MCPTool.Mailchimp  ·  mcp-mailchimp  (port 8634)
  Mailchimp Marketing API v3.

  Operations:
    list_audiences  - list all audiences/lists
    get_audience    - get audience details
    list_members    - list members in an audience
    get_member      - get a specific member
    add_member      - add/subscribe a member
    update_member   - update member status or fields
    archive_member  - archive (unsubscribe) a member
    add_tag         - add tags to a member
    list_campaigns  - list campaigns
    get_campaign    - get campaign details
    create_campaign - create a regular campaign
    send_campaign   - send a campaign
    list_templates  - list templates
    get_report      - get campaign report
    list_reports    - list campaign reports
}

interface

uses
  uMakerAi.MCPServer.Core,
  System.JSON;

type
  TMailchimpParams = class
  private
    FOperation  : string;
    FApiKey     : string;
    FListId     : string;
    FEmail      : string;
    FFirstName  : string;
    FLastName   : string;
    FStatus     : string;
    FTags       : string;
    FMergeFields: string;
    FCampaignId : string;
    FName       : string;
    FSubject    : string;
    FFromName   : string;
    FFromEmail  : string;
    FHtml       : string;
    FTemplateId : string;
    FCount      : Integer;
    FOffset     : Integer;
  public
    constructor Create;

    [AiMCPSchemaDescription('Operation: list_audiences, get_audience, list_members, get_member, add_member, update_member, archive_member, add_tag, list_campaigns, get_campaign, create_campaign, send_campaign, list_templates, get_report, list_reports')]
    property Operation  : string  read FOperation   write FOperation;

    [AiMCPSchemaDescription('Mailchimp API key (format: key-serverprefix e.g. abc123-us1)')]
    property ApiKey     : string  read FApiKey      write FApiKey;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Audience/List ID')]
    property ListId     : string  read FListId      write FListId;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Subscriber email address')]
    property Email      : string  read FEmail       write FEmail;

    [AiMCPOptional]
    [AiMCPSchemaDescription('First name (FNAME merge field)')]
    property FirstName  : string  read FFirstName   write FFirstName;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Last name (LNAME merge field)')]
    property LastName   : string  read FLastName    write FLastName;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Member status: subscribed, unsubscribed, cleaned, pending (default: subscribed)')]
    property Status     : string  read FStatus      write FStatus;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Comma-separated tags to add to a member')]
    property Tags       : string  read FTags        write FTags;

    [AiMCPOptional]
    [AiMCPSchemaDescription('JSON object of merge fields e.g. {"FNAME":"John","LNAME":"Doe"}')]
    property MergeFields: string  read FMergeFields write FMergeFields;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Campaign ID')]
    property CampaignId : string  read FCampaignId  write FCampaignId;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Campaign name')]
    property Name       : string  read FName        write FName;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Email subject line')]
    property Subject    : string  read FSubject     write FSubject;

    [AiMCPOptional]
    [AiMCPSchemaDescription('From name')]
    property FromName   : string  read FFromName    write FFromName;

    [AiMCPOptional]
    [AiMCPSchemaDescription('From email address')]
    property FromEmail  : string  read FFromEmail   write FFromEmail;

    [AiMCPOptional]
    [AiMCPSchemaDescription('HTML content for campaign')]
    property Html       : string  read FHtml        write FHtml;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Template ID')]
    property TemplateId : string  read FTemplateId  write FTemplateId;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Number of items to return (default 10)')]
    property Count      : Integer read FCount       write FCount;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Pagination offset (default 0)')]
    property Offset     : Integer read FOffset      write FOffset;
  end;

  TMailchimpTool = class(TAiMCPToolBase<TMailchimpParams>)
  private
    function GetServer(const ApiKey: string): string;
    function BaseURL(const ApiKey: string): string;
    function AuthHeader(const ApiKey: string): string;
    function MD5Lower(const Email: string): string;
    function ApiGet(const URL, Auth: string): TJSONObject;
    function ApiPost(const URL, Auth, Body: string): TJSONObject;
    function ApiPatch(const URL, Auth, Body: string): TJSONObject;
    function ApiDelete(const URL, Auth: string): TJSONObject;

    function DoListAudiences(const P: TMailchimpParams): TJSONObject;
    function DoGetAudience(const P: TMailchimpParams): TJSONObject;
    function DoListMembers(const P: TMailchimpParams): TJSONObject;
    function DoGetMember(const P: TMailchimpParams): TJSONObject;
    function DoAddMember(const P: TMailchimpParams): TJSONObject;
    function DoUpdateMember(const P: TMailchimpParams): TJSONObject;
    function DoArchiveMember(const P: TMailchimpParams): TJSONObject;
    function DoAddTag(const P: TMailchimpParams): TJSONObject;
    function DoListCampaigns(const P: TMailchimpParams): TJSONObject;
    function DoGetCampaign(const P: TMailchimpParams): TJSONObject;
    function DoCreateCampaign(const P: TMailchimpParams): TJSONObject;
    function DoSendCampaign(const P: TMailchimpParams): TJSONObject;
    function DoListTemplates(const P: TMailchimpParams): TJSONObject;
    function DoGetReport(const P: TMailchimpParams): TJSONObject;
    function DoListReports(const P: TMailchimpParams): TJSONObject;
  protected
    function ExecuteWithParams(const AParams: TMailchimpParams;
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
  System.NetEncoding,
  System.Hash;

{ TMailchimpParams }

constructor TMailchimpParams.Create;
begin
  inherited;
  FCount  := 10;
  FOffset := 0;
  FStatus := 'subscribed';
end;

{ TMailchimpTool }

constructor TMailchimpTool.Create;
begin
  inherited;
  FName        := 'mcp-mailchimp';
  FDescription :=
    'Mailchimp Marketing API v3 — audiences, members, campaigns, templates, reports. ' +
    'Operations: list_audiences, get_audience (listId), list_members (listId, status?, count?, offset?), ' +
    'get_member (listId, email), add_member (listId, email, firstName?, lastName?, status?), ' +
    'update_member (listId, email, status?), archive_member (listId, email), ' +
    'add_tag (listId, email, tags), list_campaigns (count?, offset?), get_campaign (campaignId), ' +
    'create_campaign (listId, subject, fromName, fromEmail, html?), send_campaign (campaignId), ' +
    'list_templates, get_report (campaignId), list_reports. ' +
    'Auth: apiKey (format: key-serverprefix).';
end;

function TMailchimpTool.GetServer(const ApiKey: string): string;
var
  P: Integer;
begin
  P := LastDelimiter('-', ApiKey);
  if P > 0 then
    Result := Copy(ApiKey, P + 1, MaxInt)
  else
    Result := 'us1';
end;

function TMailchimpTool.BaseURL(const ApiKey: string): string;
begin
  Result := 'https://' + GetServer(ApiKey) + '.api.mailchimp.com/3.0';
end;

function TMailchimpTool.AuthHeader(const ApiKey: string): string;
var
  Bytes: TBytes;
begin
  Bytes  := TEncoding.UTF8.GetBytes('anystring:' + Trim(ApiKey));
  Result := 'Basic ' + TNetEncoding.Base64.EncodeBytesToString(Bytes);
end;

function TMailchimpTool.MD5Lower(const Email: string): string;
begin
  Result := THashMD5.GetHashString(LowerCase(Trim(Email)));
end;

function TMailchimpTool.ApiGet(const URL, Auth: string): TJSONObject;
var
  HTTP: THTTPClient;
  Resp: IHTTPResponse;
begin
  HTTP := THTTPClient.Create;
  try
    Resp := HTTP.Get(URL, nil,
      [TNameValuePair.Create('Authorization', Auth)]);
    Result := TJSONObject.ParseJSONValue(Resp.ContentAsString()) as TJSONObject;
    if Result = nil then Result := TJSONObject.Create;
  finally
    HTTP.Free;
  end;
end;

function TMailchimpTool.ApiPost(const URL, Auth, Body: string): TJSONObject;
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
       TNameValuePair.Create('Content-Type',  'application/json')]);
    Result := TJSONObject.ParseJSONValue(Resp.ContentAsString()) as TJSONObject;
    if Result = nil then Result := TJSONObject.Create;
  finally
    Strm.Free;
    HTTP.Free;
  end;
end;

function TMailchimpTool.ApiPatch(const URL, Auth, Body: string): TJSONObject;
var
  HTTP: THTTPClient;
  Resp: IHTTPResponse;
  Strm: TStringStream;
begin
  HTTP := THTTPClient.Create;
  Strm := TStringStream.Create(Body, TEncoding.UTF8);
  try
    Resp := HTTP.Patch(URL, Strm, nil,
      [TNameValuePair.Create('Authorization', Auth),
       TNameValuePair.Create('Content-Type',  'application/json')]);
    Result := TJSONObject.ParseJSONValue(Resp.ContentAsString()) as TJSONObject;
    if Result = nil then Result := TJSONObject.Create;
  finally
    Strm.Free;
    HTTP.Free;
  end;
end;

function TMailchimpTool.ApiDelete(const URL, Auth: string): TJSONObject;
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

function TMailchimpTool.DoListAudiences(const P: TMailchimpParams): TJSONObject;
var
  Cnt, Off: Integer;
begin
  Cnt := P.Count;  if Cnt <= 0 then Cnt := 10;
  Off := P.Offset; if Off < 0 then Off := 0;
  Result := ApiGet(
    Format('%s/lists?count=%d&offset=%d', [BaseURL(P.ApiKey), Cnt, Off]),
    AuthHeader(P.ApiKey));
end;

function TMailchimpTool.DoGetAudience(const P: TMailchimpParams): TJSONObject;
begin
  if Trim(P.ListId) = '' then raise Exception.Create('"listId" required');
  Result := ApiGet(
    BaseURL(P.ApiKey) + '/lists/' + Trim(P.ListId),
    AuthHeader(P.ApiKey));
end;

function TMailchimpTool.DoListMembers(const P: TMailchimpParams): TJSONObject;
var
  Cnt, Off: Integer;
  URL: string;
begin
  if Trim(P.ListId) = '' then raise Exception.Create('"listId" required');
  Cnt := P.Count;  if Cnt <= 0 then Cnt := 10;
  Off := P.Offset; if Off < 0 then Off := 0;
  URL := Format('%s/lists/%s/members?count=%d&offset=%d',
    [BaseURL(P.ApiKey), Trim(P.ListId), Cnt, Off]);
  if Trim(P.Status) <> '' then URL := URL + '&status=' + Trim(P.Status);
  Result := ApiGet(URL, AuthHeader(P.ApiKey));
end;

function TMailchimpTool.DoGetMember(const P: TMailchimpParams): TJSONObject;
begin
  if Trim(P.ListId) = '' then raise Exception.Create('"listId" required');
  if Trim(P.Email)  = '' then raise Exception.Create('"email" required');
  Result := ApiGet(
    Format('%s/lists/%s/members/%s', [BaseURL(P.ApiKey), Trim(P.ListId), MD5Lower(P.Email)]),
    AuthHeader(P.ApiKey));
end;

function TMailchimpTool.DoAddMember(const P: TMailchimpParams): TJSONObject;
var
  Body, St, MergePart: string;
begin
  if Trim(P.ListId) = '' then raise Exception.Create('"listId" required');
  if Trim(P.Email)  = '' then raise Exception.Create('"email" required');
  St := Trim(P.Status); if St = '' then St := 'subscribed';

  if Trim(P.MergeFields) <> '' then
    Body := Format('{"email_address":"%s","status":"%s","merge_fields":%s}',
      [Trim(P.Email).Replace('"','\"'), St, Trim(P.MergeFields)])
  else
  begin
    MergePart := '';
    if Trim(P.FirstName) <> '' then
      MergePart := MergePart + '"FNAME":"' + Trim(P.FirstName).Replace('"','\"') + '",';
    if Trim(P.LastName) <> '' then
      MergePart := MergePart + '"LNAME":"' + Trim(P.LastName).Replace('"','\"') + '",';
    if MergePart <> '' then
    begin
      MergePart := Copy(MergePart, 1, Length(MergePart) - 1);
      Body := Format('{"email_address":"%s","status":"%s","merge_fields":{%s}}',
        [Trim(P.Email).Replace('"','\"'), St, MergePart]);
    end
    else
      Body := Format('{"email_address":"%s","status":"%s"}',
        [Trim(P.Email).Replace('"','\"'), St]);
  end;

  Result := ApiPost(
    Format('%s/lists/%s/members', [BaseURL(P.ApiKey), Trim(P.ListId)]),
    AuthHeader(P.ApiKey), Body);
end;

function TMailchimpTool.DoUpdateMember(const P: TMailchimpParams): TJSONObject;
var
  Body, Parts, St: string;
begin
  if Trim(P.ListId) = '' then raise Exception.Create('"listId" required');
  if Trim(P.Email)  = '' then raise Exception.Create('"email" required');
  Parts := '';
  St := Trim(P.Status);
  if St <> '' then Parts := Parts + '"status":"' + St + '",';
  if Trim(P.FirstName) <> '' then
    Parts := Parts + '"merge_fields":{"FNAME":"' + Trim(P.FirstName).Replace('"','\"') + '"},';
  if Parts = '' then raise Exception.Create('Nothing to update — provide status or firstName');
  Parts := Copy(Parts, 1, Length(Parts) - 1);
  Body  := '{' + Parts + '}';
  Result := ApiPatch(
    Format('%s/lists/%s/members/%s', [BaseURL(P.ApiKey), Trim(P.ListId), MD5Lower(P.Email)]),
    AuthHeader(P.ApiKey), Body);
end;

function TMailchimpTool.DoArchiveMember(const P: TMailchimpParams): TJSONObject;
begin
  if Trim(P.ListId) = '' then raise Exception.Create('"listId" required');
  if Trim(P.Email)  = '' then raise Exception.Create('"email" required');
  Result := ApiDelete(
    Format('%s/lists/%s/members/%s', [BaseURL(P.ApiKey), Trim(P.ListId), MD5Lower(P.Email)]),
    AuthHeader(P.ApiKey));
end;

function TMailchimpTool.DoAddTag(const P: TMailchimpParams): TJSONObject;
var
  TagArr, Tag, Body: string;
  Tags_: TArray<string>;
  I: Integer;
begin
  if Trim(P.ListId) = '' then raise Exception.Create('"listId" required');
  if Trim(P.Email)  = '' then raise Exception.Create('"email" required');
  if Trim(P.Tags)   = '' then raise Exception.Create('"tags" required');
  Tags_ := Trim(P.Tags).Split([',']);
  TagArr := '';
  for I := 0 to High(Tags_) do
  begin
    Tag := Trim(Tags_[I]);
    if Tag <> '' then
      TagArr := TagArr + '{"name":"' + Tag.Replace('"','\"') + '","status":"active"},';
  end;
  if TagArr <> '' then TagArr := Copy(TagArr, 1, Length(TagArr) - 1);
  Body := '{"tags":[' + TagArr + ']}';
  Result := ApiPost(
    Format('%s/lists/%s/members/%s/tags', [BaseURL(P.ApiKey), Trim(P.ListId), MD5Lower(P.Email)]),
    AuthHeader(P.ApiKey), Body);
end;

function TMailchimpTool.DoListCampaigns(const P: TMailchimpParams): TJSONObject;
var
  Cnt, Off: Integer;
begin
  Cnt := P.Count;  if Cnt <= 0 then Cnt := 10;
  Off := P.Offset; if Off < 0 then Off := 0;
  Result := ApiGet(
    Format('%s/campaigns?count=%d&offset=%d', [BaseURL(P.ApiKey), Cnt, Off]),
    AuthHeader(P.ApiKey));
end;

function TMailchimpTool.DoGetCampaign(const P: TMailchimpParams): TJSONObject;
begin
  if Trim(P.CampaignId) = '' then raise Exception.Create('"campaignId" required');
  Result := ApiGet(
    BaseURL(P.ApiKey) + '/campaigns/' + Trim(P.CampaignId),
    AuthHeader(P.ApiKey));
end;

function TMailchimpTool.DoCreateCampaign(const P: TMailchimpParams): TJSONObject;
var
  BodyStr, CampaignId_: string;
  RespCampaign, ContentResp: TJSONObject;
  IdVal: TJSONValue;
begin
  if Trim(P.ListId)    = '' then raise Exception.Create('"listId" required');
  if Trim(P.Subject)   = '' then raise Exception.Create('"subject" required');
  if Trim(P.FromName)  = '' then raise Exception.Create('"fromName" required');
  if Trim(P.FromEmail) = '' then raise Exception.Create('"fromEmail" required');

  BodyStr := Format(
    '{"type":"regular","recipients":{"list_id":"%s"},' +
    '"settings":{"subject_line":"%s","from_name":"%s","reply_to":"%s"}}',
    [Trim(P.ListId),
     Trim(P.Subject).Replace('"','\"'),
     Trim(P.FromName).Replace('"','\"'),
     Trim(P.FromEmail).Replace('"','\"')]);

  RespCampaign := ApiPost(BaseURL(P.ApiKey) + '/campaigns', AuthHeader(P.ApiKey), BodyStr);
  CampaignId_ := '';
  if RespCampaign <> nil then
  begin
    IdVal := RespCampaign.GetValue('id');
    if IdVal <> nil then CampaignId_ := IdVal.Value;
  end;

  if (CampaignId_ <> '') and (Trim(P.Html) <> '') then
  begin
    var ContentStr := '{"html":"' +
      Trim(P.Html).Replace('\','\\').Replace('"','\"')
                  .Replace(#10,'\n').Replace(#13,'') + '"}';
    ContentResp := ApiPost(
      Format('%s/campaigns/%s/content', [BaseURL(P.ApiKey), CampaignId_]),
      AuthHeader(P.ApiKey), ContentStr);
    ContentResp.Free;
  end;

  Result := RespCampaign;
end;

function TMailchimpTool.DoSendCampaign(const P: TMailchimpParams): TJSONObject;
begin
  if Trim(P.CampaignId) = '' then raise Exception.Create('"campaignId" required');
  Result := ApiPost(
    Format('%s/campaigns/%s/actions/send', [BaseURL(P.ApiKey), Trim(P.CampaignId)]),
    AuthHeader(P.ApiKey), '{}');
end;

function TMailchimpTool.DoListTemplates(const P: TMailchimpParams): TJSONObject;
var
  Cnt, Off: Integer;
begin
  Cnt := P.Count;  if Cnt <= 0 then Cnt := 10;
  Off := P.Offset; if Off < 0 then Off := 0;
  Result := ApiGet(
    Format('%s/templates?count=%d&offset=%d', [BaseURL(P.ApiKey), Cnt, Off]),
    AuthHeader(P.ApiKey));
end;

function TMailchimpTool.DoGetReport(const P: TMailchimpParams): TJSONObject;
begin
  if Trim(P.CampaignId) = '' then raise Exception.Create('"campaignId" required');
  Result := ApiGet(
    BaseURL(P.ApiKey) + '/reports/' + Trim(P.CampaignId),
    AuthHeader(P.ApiKey));
end;

function TMailchimpTool.DoListReports(const P: TMailchimpParams): TJSONObject;
var
  Cnt, Off: Integer;
begin
  Cnt := P.Count;  if Cnt <= 0 then Cnt := 10;
  Off := P.Offset; if Off < 0 then Off := 0;
  Result := ApiGet(
    Format('%s/reports?count=%d&offset=%d', [BaseURL(P.ApiKey), Cnt, Off]),
    AuthHeader(P.ApiKey));
end;

function TMailchimpTool.ExecuteWithParams(const AParams: TMailchimpParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op: string;
  R:  TJSONObject;
begin
  try
    Op := LowerCase(Trim(AParams.Operation));
    if Op = '' then raise Exception.Create('"operation" is required');
    if Trim(AParams.ApiKey) = '' then raise Exception.Create('"apiKey" required');

    if      Op = 'list_audiences'  then R := DoListAudiences(AParams)
    else if Op = 'get_audience'    then R := DoGetAudience(AParams)
    else if Op = 'list_members'    then R := DoListMembers(AParams)
    else if Op = 'get_member'      then R := DoGetMember(AParams)
    else if Op = 'add_member'      then R := DoAddMember(AParams)
    else if Op = 'update_member'   then R := DoUpdateMember(AParams)
    else if Op = 'archive_member'  then R := DoArchiveMember(AParams)
    else if Op = 'add_tag'         then R := DoAddTag(AParams)
    else if Op = 'list_campaigns'  then R := DoListCampaigns(AParams)
    else if Op = 'get_campaign'    then R := DoGetCampaign(AParams)
    else if Op = 'create_campaign' then R := DoCreateCampaign(AParams)
    else if Op = 'send_campaign'   then R := DoSendCampaign(AParams)
    else if Op = 'list_templates'  then R := DoListTemplates(AParams)
    else if Op = 'get_report'      then R := DoGetReport(AParams)
    else if Op = 'list_reports'    then R := DoListReports(AParams)
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
  AServer.RegisterTool('mcp-mailchimp',
    function: IAiMCPTool
    begin
      Result := TMailchimpTool.Create;
    end);
  WriteLn(ErrOutput, '[MCPService]   + mcp-mailchimp');
end;

end.
