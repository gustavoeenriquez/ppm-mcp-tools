unit MCPTool.MQTT;

(*
  MCPTool.MQTT  ·  mcp-mqtt  (port 8652)
  MQTT broker management via HTTP REST API.

  Supports two broker types:
    emqx   (default) — EMQX HTTP API v5  (default base: http://localhost:18083)
    hivemq           — HiveMQ REST API    (default base: http://localhost:8888)

  EMQX Operations:
    publish             - POST  /api/v5/publish
    list_clients        - GET   /api/v5/clients
    get_client          - GET   /api/v5/clients/:clientId
    disconnect_client   - DELETE /api/v5/clients/:clientId
    list_subscriptions  - GET   /api/v5/subscriptions
    list_topics         - GET   /api/v5/topics
    get_topic           - GET   /api/v5/topics/:topic  (URL-encoded)
    list_rules          - GET   /api/v5/rules
    get_broker_info     - GET   /api/v5/broker
    list_nodes          - GET   /api/v5/nodes

  HiveMQ Operations:
    publish             - POST  /api/v1/mqtt/publish
    list_clients        - GET   /api/v1/mqtt/connections

  Auth priority: BearerToken > ApiKey+ApiSecret (Basic) > none
*)

interface

uses
  uMakerAi.MCPServer.Core,
  System.JSON;

type
  TMQTTParams = class
  private
    FOperation  : string;
    FBaseUrl    : string;
    FApiKey     : string;
    FApiSecret  : string;
    FBearerToken: string;
    FBrokerType : string;
    FTopicName  : string;
    FPayload    : string;
    FQos        : Integer;
    FRetain     : Boolean;
    FClientId   : string;
    FPageSize   : Integer;
  public
    constructor Create;

    [AiMCPSchemaDescription('Operation: publish, list_clients, get_client, disconnect_client, list_subscriptions, list_topics, get_topic, list_rules, get_broker_info, list_nodes')]
    property Operation  : string  read FOperation   write FOperation;

    [AiMCPSchemaDescription('Broker HTTP API base URL (e.g. http://localhost:18083 for EMQX, http://localhost:8888 for HiveMQ)')]
    property BaseUrl    : string  read FBaseUrl      write FBaseUrl;

    [AiMCPOptional]
    [AiMCPSchemaDescription('API key (used as username in Basic auth together with ApiSecret)')]
    property ApiKey     : string  read FApiKey       write FApiKey;

    [AiMCPOptional]
    [AiMCPSchemaDescription('API secret (used as password in Basic auth together with ApiKey)')]
    property ApiSecret  : string  read FApiSecret    write FApiSecret;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Bearer token for Authorization header (takes priority over ApiKey/ApiSecret)')]
    property BearerToken: string  read FBearerToken  write FBearerToken;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Broker type: emqx (default) or hivemq')]
    property BrokerType : string  read FBrokerType   write FBrokerType;

    [AiMCPOptional]
    [AiMCPSchemaDescription('MQTT topic name — required for publish and get_topic operations')]
    property TopicName  : string  read FTopicName    write FTopicName;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Message payload — required for publish operation')]
    property Payload    : string  read FPayload      write FPayload;

    [AiMCPOptional]
    [AiMCPSchemaDescription('QoS level: 0, 1 or 2 (default 0)')]
    property Qos        : Integer read FQos          write FQos;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Retain flag for publish (default false)')]
    property Retain     : Boolean read FRetain       write FRetain;

    [AiMCPOptional]
    [AiMCPSchemaDescription('MQTT client ID — required for get_client and disconnect_client operations')]
    property ClientId   : string  read FClientId     write FClientId;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Page size for list operations (default 100)')]
    property PageSize   : Integer read FPageSize     write FPageSize;
  end;

  TMQTTTool = class(TAiMCPToolBase<TMQTTParams>)
  private
    function BuildAuthHeader(const P: TMQTTParams): string;
    function ResolvedBrokerType(const P: TMQTTParams): string;
    function ApiGet(const URL, Auth: string): TJSONObject;
    function ApiPost(const URL, Auth, Body: string): TJSONObject;
    function ApiDelete(const URL, Auth: string): TJSONObject;
    function ParseResponse(const Raw: string; AStatusCode: Integer): TJSONObject;
    function DoPublish(const P: TMQTTParams): TJSONObject;
    function DoListClients(const P: TMQTTParams): TJSONObject;
    function DoGetClient(const P: TMQTTParams): TJSONObject;
    function DoDisconnectClient(const P: TMQTTParams): TJSONObject;
    function DoListSubscriptions(const P: TMQTTParams): TJSONObject;
    function DoListTopics(const P: TMQTTParams): TJSONObject;
    function DoGetTopic(const P: TMQTTParams): TJSONObject;
    function DoListRules(const P: TMQTTParams): TJSONObject;
    function DoGetBrokerInfo(const P: TMQTTParams): TJSONObject;
    function DoListNodes(const P: TMQTTParams): TJSONObject;
  protected
    function ExecuteWithParams(const AParams: TMQTTParams;
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

{ TMQTTParams }

constructor TMQTTParams.Create;
begin
  inherited;
  FBrokerType := 'emqx';
  FQos        := 0;
  FRetain     := False;
  FPageSize   := 100;
end;

{ TMQTTTool }

constructor TMQTTTool.Create;
begin
  inherited;
  FName        := 'mcp-mqtt';
  FDescription :=
    'MQTT broker management via HTTP REST API. Supports EMQX HTTP API v5 and HiveMQ REST API. ' +
    'Set brokerType to "emqx" (default, base http://localhost:18083) or "hivemq" (base http://localhost:8888). ' +
    'Operations: ' +
    'publish (params: baseUrl, topicName, payload, qos?, retain?, brokerType?), ' +
    'list_clients (params: baseUrl, pageSize?), ' +
    'get_client (params: baseUrl, clientId) — EMQX only, ' +
    'disconnect_client (params: baseUrl, clientId) — EMQX only, ' +
    'list_subscriptions (params: baseUrl, pageSize?) — EMQX only, ' +
    'list_topics (params: baseUrl, pageSize?) — EMQX only, ' +
    'get_topic (params: baseUrl, topicName) — EMQX only, ' +
    'list_rules (params: baseUrl) — EMQX only, ' +
    'get_broker_info (params: baseUrl) — EMQX only, ' +
    'list_nodes (params: baseUrl) — EMQX only. ' +
    'Auth: bearerToken → Bearer header; apiKey+apiSecret → Basic auth; otherwise no auth.';
end;

function TMQTTTool.ResolvedBrokerType(const P: TMQTTParams): string;
begin
  Result := LowerCase(Trim(P.BrokerType));
  if Result = '' then
    Result := 'emqx';
end;

function TMQTTTool.BuildAuthHeader(const P: TMQTTParams): string;
var
  Tok, Key, Sec: string;
  Bytes: TBytes;
begin
  Tok := Trim(P.BearerToken);
  if Tok <> '' then
  begin
    Result := 'Bearer ' + Tok;
    Exit;
  end;
  Key := Trim(P.ApiKey);
  Sec := Trim(P.ApiSecret);
  if Key <> '' then
  begin
    Bytes  := TEncoding.UTF8.GetBytes(Key + ':' + Sec);
    Result := 'Basic ' + TNetEncoding.Base64.EncodeBytesToString(Bytes);
    Exit;
  end;
  Result := '';
end;

function TMQTTTool.ParseResponse(const Raw: string; AStatusCode: Integer): TJSONObject;
var
  J: TJSONValue;
begin
  if Trim(Raw) = '' then
  begin
    Result := TJSONObject.Create;
    Result.AddPair('ok', TJSONBool.Create(AStatusCode < 300));
    Result.AddPair('status', TJSONNumber.Create(AStatusCode));
    Exit;
  end;
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
    Result.AddPair('raw', TJSONString.Create(Raw));
  end;
end;

function TMQTTTool.ApiGet(const URL, Auth: string): TJSONObject;
var
  HTTP: THTTPClient;
  Resp: IHTTPResponse;
  Raw:  string;
  Headers: TArray<TNameValuePair>;
begin
  HTTP := THTTPClient.Create;
  try
    if Auth <> '' then
      Headers := [TNameValuePair.Create('Authorization', Auth),
                  TNameValuePair.Create('Accept', 'application/json')]
    else
      Headers := [TNameValuePair.Create('Accept', 'application/json')];
    Resp   := HTTP.Get(URL, nil, Headers);
    Raw    := Resp.ContentAsString(TEncoding.UTF8);
    Result := ParseResponse(Raw, Resp.StatusCode);
  finally
    HTTP.Free;
  end;
end;

function TMQTTTool.ApiPost(const URL, Auth, Body: string): TJSONObject;
var
  HTTP:   THTTPClient;
  Resp:   IHTTPResponse;
  Stream: TStringStream;
  Raw:    string;
  Headers: TArray<TNameValuePair>;
begin
  HTTP   := THTTPClient.Create;
  Stream := TStringStream.Create(Body, TEncoding.UTF8);
  try
    if Auth <> '' then
      Headers := [TNameValuePair.Create('Authorization', Auth),
                  TNameValuePair.Create('Content-Type', 'application/json'),
                  TNameValuePair.Create('Accept', 'application/json')]
    else
      Headers := [TNameValuePair.Create('Content-Type', 'application/json'),
                  TNameValuePair.Create('Accept', 'application/json')];
    Resp   := HTTP.Post(URL, Stream, nil, Headers);
    Raw    := Resp.ContentAsString(TEncoding.UTF8);
    Result := ParseResponse(Raw, Resp.StatusCode);
  finally
    Stream.Free;
    HTTP.Free;
  end;
end;

function TMQTTTool.ApiDelete(const URL, Auth: string): TJSONObject;
var
  HTTP:    THTTPClient;
  Resp:    IHTTPResponse;
  Headers: TArray<TNameValuePair>;
begin
  HTTP := THTTPClient.Create;
  try
    if Auth <> '' then
      Headers := [TNameValuePair.Create('Authorization', Auth),
                  TNameValuePair.Create('Accept', 'application/json')]
    else
      Headers := [TNameValuePair.Create('Accept', 'application/json')];
    Resp   := HTTP.Delete(URL, nil, Headers);
    Result := TJSONObject.Create;
    Result.AddPair('ok', TJSONBool.Create(Resp.StatusCode < 300));
    Result.AddPair('status', TJSONNumber.Create(Resp.StatusCode));
  finally
    HTTP.Free;
  end;
end;

function TMQTTTool.DoPublish(const P: TMQTTParams): TJSONObject;
var
  Base, Auth, BType, Topic, PayloadStr, RetainStr, Body, URL: string;
  QosVal: Integer;
  JBody: TJSONObject;
begin
  Base    := Trim(P.BaseUrl);
  Topic   := Trim(P.TopicName);
  if Base  = '' then raise Exception.Create('"baseUrl" is required');
  if Topic = '' then raise Exception.Create('"topicName" is required for publish');
  Auth    := BuildAuthHeader(P);
  BType   := ResolvedBrokerType(P);
  PayloadStr := P.Payload;
  QosVal  := P.Qos;
  if P.Retain then RetainStr := 'true' else RetainStr := 'false';
  if BType = 'hivemq' then
  begin
    URL := Base + '/api/v1/mqtt/publish';
    JBody := TJSONObject.Create;
    try
      JBody.AddPair('topic',   TJSONString.Create(Topic));
      JBody.AddPair('payload', TJSONString.Create(PayloadStr));
      JBody.AddPair('qos',     TJSONNumber.Create(QosVal));
      Body := JBody.ToJSON;
    finally
      JBody.Free;
    end;
  end
  else
  begin
    URL := Base + '/api/v5/publish';
    Body := Format(
      '{"topic":%s,"payload":%s,"qos":%d,"retain":%s}',
      [TJSONString.Create(Topic).ToString,
       TJSONString.Create(PayloadStr).ToString,
       QosVal,
       RetainStr]);
  end;
  Result := ApiPost(URL, Auth, Body);
end;

function TMQTTTool.DoListClients(const P: TMQTTParams): TJSONObject;
var
  Base, Auth, BType, URL: string;
  PS: Integer;
begin
  Base  := Trim(P.BaseUrl);
  if Base = '' then raise Exception.Create('"baseUrl" is required');
  Auth  := BuildAuthHeader(P);
  BType := ResolvedBrokerType(P);
  PS    := P.PageSize;
  if PS <= 0 then PS := 100;
  if BType = 'hivemq' then
    URL := Base + '/api/v1/mqtt/connections'
  else
    URL := Base + '/api/v5/clients?page=1&limit=' + IntToStr(PS);
  Result := ApiGet(URL, Auth);
end;

function TMQTTTool.DoGetClient(const P: TMQTTParams): TJSONObject;
var
  Base, Auth, CID: string;
begin
  Base := Trim(P.BaseUrl);
  CID  := Trim(P.ClientId);
  if Base = '' then raise Exception.Create('"baseUrl" is required');
  if CID  = '' then raise Exception.Create('"clientId" is required for get_client');
  Auth   := BuildAuthHeader(P);
  Result := ApiGet(Base + '/api/v5/clients/' + TNetEncoding.URL.Encode(CID), Auth);
end;

function TMQTTTool.DoDisconnectClient(const P: TMQTTParams): TJSONObject;
var
  Base, Auth, CID: string;
begin
  Base := Trim(P.BaseUrl);
  CID  := Trim(P.ClientId);
  if Base = '' then raise Exception.Create('"baseUrl" is required');
  if CID  = '' then raise Exception.Create('"clientId" is required for disconnect_client');
  Auth   := BuildAuthHeader(P);
  Result := ApiDelete(Base + '/api/v5/clients/' + TNetEncoding.URL.Encode(CID), Auth);
end;

function TMQTTTool.DoListSubscriptions(const P: TMQTTParams): TJSONObject;
var
  Base, Auth: string;
  PS: Integer;
begin
  Base := Trim(P.BaseUrl);
  if Base = '' then raise Exception.Create('"baseUrl" is required');
  Auth := BuildAuthHeader(P);
  PS   := P.PageSize;
  if PS <= 0 then PS := 100;
  Result := ApiGet(Base + '/api/v5/subscriptions?page=1&limit=' + IntToStr(PS), Auth);
end;

function TMQTTTool.DoListTopics(const P: TMQTTParams): TJSONObject;
var
  Base, Auth: string;
  PS: Integer;
begin
  Base := Trim(P.BaseUrl);
  if Base = '' then raise Exception.Create('"baseUrl" is required');
  Auth := BuildAuthHeader(P);
  PS   := P.PageSize;
  if PS <= 0 then PS := 100;
  Result := ApiGet(Base + '/api/v5/topics?page=1&limit=' + IntToStr(PS), Auth);
end;

function TMQTTTool.DoGetTopic(const P: TMQTTParams): TJSONObject;
var
  Base, Auth, Topic: string;
begin
  Base  := Trim(P.BaseUrl);
  Topic := Trim(P.TopicName);
  if Base  = '' then raise Exception.Create('"baseUrl" is required');
  if Topic = '' then raise Exception.Create('"topicName" is required for get_topic');
  Auth   := BuildAuthHeader(P);
  Result := ApiGet(Base + '/api/v5/topics/' + TNetEncoding.URL.Encode(Topic), Auth);
end;

function TMQTTTool.DoListRules(const P: TMQTTParams): TJSONObject;
var
  Base, Auth: string;
begin
  Base := Trim(P.BaseUrl);
  if Base = '' then raise Exception.Create('"baseUrl" is required');
  Auth   := BuildAuthHeader(P);
  Result := ApiGet(Base + '/api/v5/rules', Auth);
end;

function TMQTTTool.DoGetBrokerInfo(const P: TMQTTParams): TJSONObject;
var
  Base, Auth: string;
begin
  Base := Trim(P.BaseUrl);
  if Base = '' then raise Exception.Create('"baseUrl" is required');
  Auth   := BuildAuthHeader(P);
  Result := ApiGet(Base + '/api/v5/broker', Auth);
end;

function TMQTTTool.DoListNodes(const P: TMQTTParams): TJSONObject;
var
  Base, Auth: string;
begin
  Base := Trim(P.BaseUrl);
  if Base = '' then raise Exception.Create('"baseUrl" is required');
  Auth   := BuildAuthHeader(P);
  Result := ApiGet(Base + '/api/v5/nodes', Auth);
end;

function TMQTTTool.ExecuteWithParams(const AParams: TMQTTParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op: string;
  R:  TJSONObject;
begin
  try
    Op := LowerCase(Trim(AParams.Operation));
    if Op = '' then raise Exception.Create('"operation" is required');

    if      Op = 'publish'            then R := DoPublish(AParams)
    else if Op = 'list_clients'       then R := DoListClients(AParams)
    else if Op = 'get_client'         then R := DoGetClient(AParams)
    else if Op = 'disconnect_client'  then R := DoDisconnectClient(AParams)
    else if Op = 'list_subscriptions' then R := DoListSubscriptions(AParams)
    else if Op = 'list_topics'        then R := DoListTopics(AParams)
    else if Op = 'get_topic'          then R := DoGetTopic(AParams)
    else if Op = 'list_rules'         then R := DoListRules(AParams)
    else if Op = 'get_broker_info'    then R := DoGetBrokerInfo(AParams)
    else if Op = 'list_nodes'         then R := DoListNodes(AParams)
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
  AServer.RegisterTool('mcp-mqtt',
    function: IAiMCPTool
    begin
      Result := TMQTTTool.Create;
    end);
  WriteLn(ErrOutput, '[MCPService]   + mcp-mqtt');
end;

end.
