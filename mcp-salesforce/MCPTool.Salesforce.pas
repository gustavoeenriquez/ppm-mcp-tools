unit MCPTool.Salesforce;

{
  MCPTool.Salesforce  ·  mcp-salesforce  (port 8631)
  Salesforce REST API v59.0 — query, CRUD, search, describe.

  Operations:
    query        - run SOQL query
    get_record   - get a single record by Id
    create       - create a record
    update       - update a record
    delete       - delete a record
    describe     - describe an sObject
    search       - SOSL search
    list_objects - list all sObjects
}

interface

uses
  uMakerAi.MCPServer.Core,
  System.JSON;

type
  TSalesforceParams = class
  private
    FOperation   : string;
    FUsername    : string;
    FPassword    : string;
    FClientId    : string;
    FClientSecret: string;
    FSandbox     : Boolean;
    FSObject     : string;
    FRecordId    : string;
    FSOQL        : string;
    FSOSL        : string;
    FBody        : string;
    FFields      : string;
  public
    constructor Create;

    [AiMCPSchemaDescription('Operation: query, get_record, create, update, delete, describe, search, list_objects')]
    property Operation   : string  read FOperation   write FOperation;

    [AiMCPSchemaDescription('Salesforce username')]
    property Username    : string  read FUsername    write FUsername;

    [AiMCPSchemaDescription('Salesforce password (append security token if required)')]
    property Password    : string  read FPassword    write FPassword;

    [AiMCPSchemaDescription('Connected App client_id (consumer key)')]
    property ClientId    : string  read FClientId    write FClientId;

    [AiMCPSchemaDescription('Connected App client_secret (consumer secret)')]
    property ClientSecret: string  read FClientSecret write FClientSecret;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Use sandbox login endpoint (default: false)')]
    property Sandbox     : Boolean read FSandbox     write FSandbox;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Salesforce sObject name e.g. Account, Contact, Lead')]
    property SObject_    : string  read FSObject     write FSObject;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Record Id (18-char Salesforce Id)')]
    property RecordId    : string  read FRecordId    write FRecordId;

    [AiMCPOptional]
    [AiMCPSchemaDescription('SOQL query e.g. SELECT Id, Name FROM Account LIMIT 10')]
    property SOQL        : string  read FSOQL        write FSOQL;

    [AiMCPOptional]
    [AiMCPSchemaDescription('SOSL search string e.g. FIND {Acme} IN ALL FIELDS RETURNING Account(Id,Name)')]
    property SOSL        : string  read FSOSL        write FSOSL;

    [AiMCPOptional]
    [AiMCPSchemaDescription('JSON object of field values for create/update e.g. {"Name":"Acme"}')]
    property Body        : string  read FBody        write FBody;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Comma-separated field names for get_record (default: all fields)')]
    property Fields      : string  read FFields      write FFields;
  end;

  TSalesforceTool = class(TAiMCPToolBase<TSalesforceParams>)
  private
    function Login(const P: TSalesforceParams;
      out AccessToken, InstanceURL: string): Boolean;
    function ApiGet(const URL, Token: string): TJSONObject;
    function ApiPost(const URL, Token, Body: string): TJSONObject;
    function ApiPatch(const URL, Token, Body: string): TJSONObject;
    function ApiDelete(const URL, Token: string): TJSONObject;

    function DoQuery(const P: TSalesforceParams): TJSONObject;
    function DoGetRecord(const P: TSalesforceParams): TJSONObject;
    function DoCreate(const P: TSalesforceParams): TJSONObject;
    function DoUpdate(const P: TSalesforceParams): TJSONObject;
    function DoDelete(const P: TSalesforceParams): TJSONObject;
    function DoDescribe(const P: TSalesforceParams): TJSONObject;
    function DoSearch(const P: TSalesforceParams): TJSONObject;
    function DoListObjects(const P: TSalesforceParams): TJSONObject;
  protected
    function ExecuteWithParams(const AParams: TSalesforceParams;
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

const
  API_VERSION = 'v59.0';

{ TSalesforceParams }

constructor TSalesforceParams.Create;
begin
  inherited;
  FSandbox := False;
end;

{ TSalesforceTool }

constructor TSalesforceTool.Create;
begin
  inherited;
  FName        := 'mcp-salesforce';
  FDescription :=
    'Salesforce REST API — SOQL queries, CRUD on any sObject, SOSL search, describe. ' +
    'Operations: query (params: soql), get_record (params: sobject, recordId, fields?), ' +
    'create (params: sobject, body), update (params: sobject, recordId, body), ' +
    'delete (params: sobject, recordId), describe (params: sobject), ' +
    'search (params: sosl), list_objects. ' +
    'Auth: username, password, clientId, clientSecret, sandbox?.';
end;

function TSalesforceTool.Login(const P: TSalesforceParams;
  out AccessToken, InstanceURL: string): Boolean;
var
  HTTP: THTTPClient;
  Resp: IHTTPResponse;
  Strm: TStringStream;
  J:    TJSONObject;
  LoginURL: string;
  Body: string;
begin
  Result := False;
  AccessToken := '';
  InstanceURL := '';

  if P.Sandbox then
    LoginURL := 'https://test.salesforce.com/services/oauth2/token'
  else
    LoginURL := 'https://login.salesforce.com/services/oauth2/token';

  Body := 'grant_type=password' +
    '&client_id='     + TNetEncoding.URL.Encode(Trim(P.ClientId)) +
    '&client_secret=' + TNetEncoding.URL.Encode(Trim(P.ClientSecret)) +
    '&username='      + TNetEncoding.URL.Encode(Trim(P.Username)) +
    '&password='      + TNetEncoding.URL.Encode(Trim(P.Password));

  HTTP := THTTPClient.Create;
  Strm := TStringStream.Create(Body, TEncoding.UTF8);
  try
    Resp := HTTP.Post(LoginURL, Strm, nil,
      [TNameValuePair.Create('Content-Type', 'application/x-www-form-urlencoded')]);
    J := TJSONObject.ParseJSONValue(Resp.ContentAsString()) as TJSONObject;
    if J <> nil then
    try
      var T := J.GetValue('access_token');
      var I := J.GetValue('instance_url');
      if (T <> nil) and (I <> nil) then
      begin
        AccessToken := T.Value;
        InstanceURL := I.Value;
        Result := True;
      end;
    finally
      J.Free;
    end;
  finally
    Strm.Free;
    HTTP.Free;
  end;
end;

function TSalesforceTool.ApiGet(const URL, Token: string): TJSONObject;
var
  HTTP: THTTPClient;
  Resp: IHTTPResponse;
begin
  HTTP := THTTPClient.Create;
  try
    Resp := HTTP.Get(URL, nil,
      [TNameValuePair.Create('Authorization', 'Bearer ' + Token),
       TNameValuePair.Create('Accept', 'application/json')]);
    Result := TJSONObject.ParseJSONValue(Resp.ContentAsString()) as TJSONObject;
    if Result = nil then Result := TJSONObject.Create;
  finally
    HTTP.Free;
  end;
end;

function TSalesforceTool.ApiPost(const URL, Token, Body: string): TJSONObject;
var
  HTTP: THTTPClient;
  Resp: IHTTPResponse;
  Strm: TStringStream;
begin
  HTTP := THTTPClient.Create;
  Strm := TStringStream.Create(Body, TEncoding.UTF8);
  try
    Resp := HTTP.Post(URL, Strm, nil,
      [TNameValuePair.Create('Authorization', 'Bearer ' + Token),
       TNameValuePair.Create('Content-Type',  'application/json'),
       TNameValuePair.Create('Accept',         'application/json')]);
    Result := TJSONObject.ParseJSONValue(Resp.ContentAsString()) as TJSONObject;
    if Result = nil then Result := TJSONObject.Create;
  finally
    Strm.Free;
    HTTP.Free;
  end;
end;

function TSalesforceTool.ApiPatch(const URL, Token, Body: string): TJSONObject;
var
  HTTP: THTTPClient;
  Resp: IHTTPResponse;
  Strm: TStringStream;
begin
  HTTP := THTTPClient.Create;
  Strm := TStringStream.Create(Body, TEncoding.UTF8);
  try
    Resp := HTTP.Patch(URL, Strm, nil,
      [TNameValuePair.Create('Authorization', 'Bearer ' + Token),
       TNameValuePair.Create('Content-Type',  'application/json'),
       TNameValuePair.Create('Accept',         'application/json')]);
    Result := TJSONObject.Create;
    Result.AddPair('status', IntToStr(Resp.StatusCode));
    Result.AddPair('ok', TJSONBool.Create(Resp.StatusCode < 300));
  finally
    Strm.Free;
    HTTP.Free;
  end;
end;

function TSalesforceTool.ApiDelete(const URL, Token: string): TJSONObject;
var
  HTTP: THTTPClient;
  Resp: IHTTPResponse;
begin
  HTTP := THTTPClient.Create;
  try
    Resp := HTTP.Delete(URL, nil,
      [TNameValuePair.Create('Authorization', 'Bearer ' + Token)]);
    Result := TJSONObject.Create;
    Result.AddPair('status', IntToStr(Resp.StatusCode));
    Result.AddPair('ok', TJSONBool.Create(Resp.StatusCode < 300));
  finally
    HTTP.Free;
  end;
end;

function TSalesforceTool.DoQuery(const P: TSalesforceParams): TJSONObject;
var
  Token, InstURL: string;
begin
  if Trim(P.SOQL) = '' then raise Exception.Create('"soql" required for query');
  if not Login(P, Token, InstURL) then raise Exception.Create('Salesforce login failed');
  Result := ApiGet(
    InstURL + '/services/data/' + API_VERSION + '/query?q=' +
    TNetEncoding.URL.Encode(Trim(P.SOQL)),
    Token);
end;

function TSalesforceTool.DoGetRecord(const P: TSalesforceParams): TJSONObject;
var
  Token, InstURL, URL: string;
begin
  if Trim(P.SObject_)  = '' then raise Exception.Create('"sobject" required');
  if Trim(P.RecordId) = '' then raise Exception.Create('"recordId" required');
  if not Login(P, Token, InstURL) then raise Exception.Create('Salesforce login failed');
  URL := InstURL + '/services/data/' + API_VERSION + '/sobjects/' +
    Trim(P.SObject_) + '/' + Trim(P.RecordId);
  if Trim(P.Fields) <> '' then
    URL := URL + '?fields=' + Trim(P.Fields);
  Result := ApiGet(URL, Token);
end;

function TSalesforceTool.DoCreate(const P: TSalesforceParams): TJSONObject;
var
  Token, InstURL: string;
begin
  if Trim(P.SObject_) = '' then raise Exception.Create('"sobject" required');
  if Trim(P.Body)    = '' then raise Exception.Create('"body" (JSON) required');
  if not Login(P, Token, InstURL) then raise Exception.Create('Salesforce login failed');
  Result := ApiPost(
    InstURL + '/services/data/' + API_VERSION + '/sobjects/' + Trim(P.SObject_),
    Token, Trim(P.Body));
end;

function TSalesforceTool.DoUpdate(const P: TSalesforceParams): TJSONObject;
var
  Token, InstURL: string;
begin
  if Trim(P.SObject_)  = '' then raise Exception.Create('"sobject" required');
  if Trim(P.RecordId) = '' then raise Exception.Create('"recordId" required');
  if Trim(P.Body)     = '' then raise Exception.Create('"body" (JSON) required');
  if not Login(P, Token, InstURL) then raise Exception.Create('Salesforce login failed');
  Result := ApiPatch(
    InstURL + '/services/data/' + API_VERSION + '/sobjects/' +
    Trim(P.SObject_) + '/' + Trim(P.RecordId),
    Token, Trim(P.Body));
end;

function TSalesforceTool.DoDelete(const P: TSalesforceParams): TJSONObject;
var
  Token, InstURL: string;
begin
  if Trim(P.SObject_)  = '' then raise Exception.Create('"sobject" required');
  if Trim(P.RecordId) = '' then raise Exception.Create('"recordId" required');
  if not Login(P, Token, InstURL) then raise Exception.Create('Salesforce login failed');
  Result := ApiDelete(
    InstURL + '/services/data/' + API_VERSION + '/sobjects/' +
    Trim(P.SObject_) + '/' + Trim(P.RecordId),
    Token);
end;

function TSalesforceTool.DoDescribe(const P: TSalesforceParams): TJSONObject;
var
  Token, InstURL: string;
begin
  if Trim(P.SObject_) = '' then raise Exception.Create('"sobject" required');
  if not Login(P, Token, InstURL) then raise Exception.Create('Salesforce login failed');
  Result := ApiGet(
    InstURL + '/services/data/' + API_VERSION + '/sobjects/' + Trim(P.SObject_) + '/describe',
    Token);
end;

function TSalesforceTool.DoSearch(const P: TSalesforceParams): TJSONObject;
var
  Token, InstURL: string;
begin
  if Trim(P.SOSL) = '' then raise Exception.Create('"sosl" required for search');
  if not Login(P, Token, InstURL) then raise Exception.Create('Salesforce login failed');
  Result := ApiGet(
    InstURL + '/services/data/' + API_VERSION + '/search?q=' +
    TNetEncoding.URL.Encode(Trim(P.SOSL)),
    Token);
end;

function TSalesforceTool.DoListObjects(const P: TSalesforceParams): TJSONObject;
var
  Token, InstURL: string;
begin
  if not Login(P, Token, InstURL) then raise Exception.Create('Salesforce login failed');
  Result := ApiGet(
    InstURL + '/services/data/' + API_VERSION + '/sobjects',
    Token);
end;

function TSalesforceTool.ExecuteWithParams(const AParams: TSalesforceParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op: string;
  R:  TJSONObject;
begin
  try
    Op := LowerCase(Trim(AParams.Operation));
    if Op = '' then raise Exception.Create('"operation" is required');
    if Trim(AParams.Username)     = '' then raise Exception.Create('"username" required');
    if Trim(AParams.Password)     = '' then raise Exception.Create('"password" required');
    if Trim(AParams.ClientId)     = '' then raise Exception.Create('"clientId" required');
    if Trim(AParams.ClientSecret) = '' then raise Exception.Create('"clientSecret" required');

    if      Op = 'query'        then R := DoQuery(AParams)
    else if Op = 'get_record'   then R := DoGetRecord(AParams)
    else if Op = 'create'       then R := DoCreate(AParams)
    else if Op = 'update'       then R := DoUpdate(AParams)
    else if Op = 'delete'       then R := DoDelete(AParams)
    else if Op = 'describe'     then R := DoDescribe(AParams)
    else if Op = 'search'       then R := DoSearch(AParams)
    else if Op = 'list_objects' then R := DoListObjects(AParams)
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
  AServer.RegisterTool('mcp-salesforce',
    function: IAiMCPTool
    begin
      Result := TSalesforceTool.Create;
    end);
  WriteLn(ErrOutput, '[MCPService]   + mcp-salesforce');
end;

end.
