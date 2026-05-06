unit MCPTool.Kafka;

(*
  MCPTool.Kafka  ·  mcp-kafka  (port 8636)
  Apache Kafka via Confluent REST Proxy API (HTTP-based).

  Operations:
    list_topics    - GET  /topics
    get_topic      - GET  /topics/:topic
    create_topic   - POST /v3/clusters/:clusterId/topics
    delete_topic   - DELETE /v3/clusters/:clusterId/topics/:topic
    produce        - POST /topics/:topic  — produce message(s)
    consume        - GET  /topics/:topic/partitions/:partition/messages
    list_consumers - GET  /consumers/:group
    get_offsets    - GET  /topics/:topic/partitions/:partition/offsets

  Auth: if apiKey + apiSecret provided, Basic auth (base64 apiKey:apiSecret).
*)

interface

uses
  uMakerAi.MCPServer.Core,
  System.JSON;

type
  TKafkaParams = class
  private
    FOperation:  string;
    FBaseUrl:    string;
    FApiKey:     string;
    FApiSecret:  string;
    FClusterId:  string;
    FTopic:      string;
    FGroup:      string;
    FInstance:   string;
    FPartition:  Integer;
    FOffset:     Integer;
    FCount:      Integer;
    FBody:       string;
    FKey:        string;
  public
    constructor Create;

    [AiMCPSchemaDescription('Operation: list_topics, get_topic, create_topic, delete_topic, produce, consume, list_consumers, get_offsets')]
    property Operation:  string  read FOperation  write FOperation;

    [AiMCPSchemaDescription('Confluent REST Proxy base URL (e.g. http://localhost:8082 or https://pkc-xxx.us-east-1.aws.confluent.cloud:443)')]
    property BaseUrl:    string  read FBaseUrl    write FBaseUrl;

    [AiMCPOptional]
    [AiMCPSchemaDescription('API key for Confluent Cloud (optional). Used as username in Basic auth together with apiSecret.')]
    property ApiKey:     string  read FApiKey     write FApiKey;

    [AiMCPOptional]
    [AiMCPSchemaDescription('API secret for Confluent Cloud (optional). Used as password in Basic auth together with apiKey.')]
    property ApiSecret:  string  read FApiSecret  write FApiSecret;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Kafka cluster ID required for v3 API operations (create_topic, delete_topic). E.g. lkc-xxxxx.')]
    property ClusterId:  string  read FClusterId  write FClusterId;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Topic name — required for get_topic, create_topic, delete_topic, produce, consume, get_offsets.')]
    property Topic:      string  read FTopic      write FTopic;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Consumer group name — required for list_consumers.')]
    property Group:      string  read FGroup      write FGroup;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Consumer instance name within the group — required for consume.')]
    property Instance:   string  read FInstance   write FInstance;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Partition number (integer, default 0) — used by consume and get_offsets.')]
    property Partition:  Integer read FPartition  write FPartition;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Start offset (integer, default 0) — used by consume.')]
    property Offset:     Integer read FOffset     write FOffset;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Number of messages to fetch (integer, default 10) — used by consume.')]
    property Count:      Integer read FCount      write FCount;

    [AiMCPOptional]
    [AiMCPSchemaDescription('JSON body string for produce (e.g. {"records":[{"value":"hello"}]}) or create_topic.')]
    property Body:       string  read FBody       write FBody;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Message key string — if provided, wraps body records with this key for produce.')]
    property Key:        string  read FKey        write FKey;
  end;

  TKafkaTool = class(TAiMCPToolBase<TKafkaParams>)
  private
    function BuildAuth(const AKey, ASecret: string): string;
    function ApiGet(const URL, Auth: string): string;
    function ApiPost(const URL, Auth, Body: string): string;
    function ApiDelete(const URL, Auth: string): string;
    function ParseResponse(const Raw: string): TJSONObject;
    function DoListTopics(const P: TKafkaParams): TJSONObject;
    function DoGetTopic(const P: TKafkaParams): TJSONObject;
    function DoCreateTopic(const P: TKafkaParams): TJSONObject;
    function DoDeleteTopic(const P: TKafkaParams): TJSONObject;
    function DoProduce(const P: TKafkaParams): TJSONObject;
    function DoConsume(const P: TKafkaParams): TJSONObject;
    function DoListConsumers(const P: TKafkaParams): TJSONObject;
    function DoGetOffsets(const P: TKafkaParams): TJSONObject;
  protected
    function ExecuteWithParams(const AParams: TKafkaParams;
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

{ TKafkaParams }

constructor TKafkaParams.Create;
begin
  inherited;
  FPartition := 0;
  FOffset    := 0;
  FCount     := 10;
end;

{ TKafkaTool }

function TKafkaTool.BuildAuth(const AKey, ASecret: string): string;
begin
  if (Trim(AKey) <> '') and (Trim(ASecret) <> '') then
    Result := 'Basic ' + TNetEncoding.Base64.Encode(Trim(AKey) + ':' + Trim(ASecret))
  else
    Result := '';
end;

function TKafkaTool.ApiGet(const URL, Auth: string): string;
var
  HTTP: THTTPClient;
  Resp: IHTTPResponse;
begin
  HTTP := THTTPClient.Create;
  try
    if Auth <> '' then
      Resp := HTTP.Get(URL, nil,
        [TNameValuePair.Create('Authorization', Auth),
         TNameValuePair.Create('Accept', 'application/json')])
    else
      Resp := HTTP.Get(URL, nil,
        [TNameValuePair.Create('Accept', 'application/json')]);
    Result := Resp.ContentAsString(TEncoding.UTF8);
  finally
    HTTP.Free;
  end;
end;

function TKafkaTool.ApiPost(const URL, Auth, Body: string): string;
var
  HTTP:   THTTPClient;
  Resp:   IHTTPResponse;
  Stream: TStringStream;
begin
  HTTP   := THTTPClient.Create;
  Stream := TStringStream.Create(Body, TEncoding.UTF8);
  try
    if Auth <> '' then
      Resp := HTTP.Post(URL, Stream, nil,
        [TNameValuePair.Create('Authorization', Auth),
         TNameValuePair.Create('Content-Type', 'application/json'),
         TNameValuePair.Create('Accept', 'application/json')])
    else
      Resp := HTTP.Post(URL, Stream, nil,
        [TNameValuePair.Create('Content-Type', 'application/json'),
         TNameValuePair.Create('Accept', 'application/json')]);
    Result := Resp.ContentAsString(TEncoding.UTF8);
  finally
    Stream.Free;
    HTTP.Free;
  end;
end;

function TKafkaTool.ApiDelete(const URL, Auth: string): string;
var
  HTTP: THTTPClient;
  Resp: IHTTPResponse;
begin
  HTTP := THTTPClient.Create;
  try
    if Auth <> '' then
      Resp := HTTP.Delete(URL, nil,
        [TNameValuePair.Create('Authorization', Auth),
         TNameValuePair.Create('Accept', 'application/json')])
    else
      Resp := HTTP.Delete(URL, nil,
        [TNameValuePair.Create('Accept', 'application/json')]);
    Result := Resp.ContentAsString(TEncoding.UTF8);
  finally
    HTTP.Free;
  end;
end;

function TKafkaTool.ParseResponse(const Raw: string): TJSONObject;
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
    Result.AddPair('raw', TJSONString.Create(Raw));
  end;
  Result.AddPair('ok', TJSONTrue.Create);
end;

function TKafkaTool.DoListTopics(const P: TKafkaParams): TJSONObject;
var
  Base, Auth, Raw: string;
begin
  Base := Trim(P.BaseUrl);
  if Base = '' then raise Exception.Create('"baseUrl" is required');
  Auth := BuildAuth(P.ApiKey, P.ApiSecret);
  Raw  := ApiGet(Base + '/topics', Auth);
  Result := ParseResponse(Raw);
end;

function TKafkaTool.DoGetTopic(const P: TKafkaParams): TJSONObject;
var
  Base, Topic, Auth, Raw: string;
begin
  Base  := Trim(P.BaseUrl);
  Topic := Trim(P.Topic);
  if Base  = '' then raise Exception.Create('"baseUrl" is required');
  if Topic = '' then raise Exception.Create('"topic" is required for get_topic');
  Auth   := BuildAuth(P.ApiKey, P.ApiSecret);
  Raw    := ApiGet(Base + '/topics/' + Topic, Auth);
  Result := ParseResponse(Raw);
end;

function TKafkaTool.DoCreateTopic(const P: TKafkaParams): TJSONObject;
var
  Base, ClusterId, Topic, Auth, Body, Raw: string;
  JBody: TJSONObject;
begin
  Base      := Trim(P.BaseUrl);
  ClusterId := Trim(P.ClusterId);
  Topic     := Trim(P.Topic);
  if Base      = '' then raise Exception.Create('"baseUrl" is required');
  if ClusterId = '' then raise Exception.Create('"clusterId" is required for create_topic');
  if Topic     = '' then raise Exception.Create('"topic" is required for create_topic');
  Auth := BuildAuth(P.ApiKey, P.ApiSecret);
  Body := Trim(P.Body);
  if Body = '' then
  begin
    JBody := TJSONObject.Create;
    try
      JBody.AddPair('topic_name', TJSONString.Create(Topic));
      Body := JBody.ToJSON;
    finally
      JBody.Free;
    end;
  end;
  Raw    := ApiPost(Base + '/v3/clusters/' + ClusterId + '/topics', Auth, Body);
  Result := ParseResponse(Raw);
end;

function TKafkaTool.DoDeleteTopic(const P: TKafkaParams): TJSONObject;
var
  Base, ClusterId, Topic, Auth, Raw: string;
begin
  Base      := Trim(P.BaseUrl);
  ClusterId := Trim(P.ClusterId);
  Topic     := Trim(P.Topic);
  if Base      = '' then raise Exception.Create('"baseUrl" is required');
  if ClusterId = '' then raise Exception.Create('"clusterId" is required for delete_topic');
  if Topic     = '' then raise Exception.Create('"topic" is required for delete_topic');
  Auth   := BuildAuth(P.ApiKey, P.ApiSecret);
  Raw    := ApiDelete(Base + '/v3/clusters/' + ClusterId + '/topics/' + Topic, Auth);
  if Trim(Raw) = '' then
  begin
    Result := TJSONObject.Create;
    Result.AddPair('ok', TJSONTrue.Create);
    Result.AddPair('deleted', TJSONString.Create(Topic));
  end
  else
    Result := ParseResponse(Raw);
end;

function TKafkaTool.DoProduce(const P: TKafkaParams): TJSONObject;
var
  Base, Topic, Auth, Body, Raw: string;
  JBody, JRecord: TJSONObject;
  JRecords: TJSONArray;
  KeyStr: string;
begin
  Base  := Trim(P.BaseUrl);
  Topic := Trim(P.Topic);
  if Base  = '' then raise Exception.Create('"baseUrl" is required');
  if Topic = '' then raise Exception.Create('"topic" is required for produce');
  Auth  := BuildAuth(P.ApiKey, P.ApiSecret);
  Body  := Trim(P.Body);
  KeyStr := Trim(P.Key);
  if Body = '' then
  begin
    JBody    := TJSONObject.Create;
    JRecords := TJSONArray.Create;
    JRecord  := TJSONObject.Create;
    try
      if KeyStr <> '' then
        JRecord.AddPair('key', TJSONString.Create(KeyStr));
      JRecord.AddPair('value', TJSONString.Create(''));
      JRecords.AddElement(JRecord);
      JBody.AddPair('records', JRecords);
      Body := JBody.ToJSON;
    finally
      JBody.Free;
    end;
  end;
  Raw    := ApiPost(Base + '/topics/' + Topic, Auth, Body);
  Result := ParseResponse(Raw);
end;

function TKafkaTool.DoConsume(const P: TKafkaParams): TJSONObject;
var
  Base, Topic, Auth, Raw: string;
  PartStr, OffStr, CntStr: string;
  URL: string;
begin
  Base  := Trim(P.BaseUrl);
  Topic := Trim(P.Topic);
  if Base  = '' then raise Exception.Create('"baseUrl" is required');
  if Topic = '' then raise Exception.Create('"topic" is required for consume');
  Auth    := BuildAuth(P.ApiKey, P.ApiSecret);
  PartStr := IntToStr(P.Partition);
  OffStr  := IntToStr(P.Offset);
  if P.Count > 0 then
    CntStr := IntToStr(P.Count)
  else
    CntStr := '10';
  URL    := Base + '/topics/' + Topic + '/partitions/' + PartStr +
            '/messages?offset=' + OffStr + '&count=' + CntStr;
  Raw    := ApiGet(URL, Auth);
  Result := ParseResponse(Raw);
end;

function TKafkaTool.DoListConsumers(const P: TKafkaParams): TJSONObject;
var
  Base, Group, Auth, Raw: string;
begin
  Base  := Trim(P.BaseUrl);
  Group := Trim(P.Group);
  if Base  = '' then raise Exception.Create('"baseUrl" is required');
  if Group = '' then raise Exception.Create('"group" is required for list_consumers');
  Auth   := BuildAuth(P.ApiKey, P.ApiSecret);
  Raw    := ApiGet(Base + '/consumers/' + Group, Auth);
  Result := ParseResponse(Raw);
end;

function TKafkaTool.DoGetOffsets(const P: TKafkaParams): TJSONObject;
var
  Base, Topic, Auth, Raw: string;
  PartStr: string;
begin
  Base  := Trim(P.BaseUrl);
  Topic := Trim(P.Topic);
  if Base  = '' then raise Exception.Create('"baseUrl" is required');
  if Topic = '' then raise Exception.Create('"topic" is required for get_offsets');
  Auth    := BuildAuth(P.ApiKey, P.ApiSecret);
  PartStr := IntToStr(P.Partition);
  Raw    := ApiGet(Base + '/topics/' + Topic + '/partitions/' + PartStr + '/offsets', Auth);
  Result := ParseResponse(Raw);
end;

function TKafkaTool.ExecuteWithParams(const AParams: TKafkaParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op: string;
  R:  TJSONObject;
begin
  try
    Op := LowerCase(Trim(AParams.Operation));
    if Op = '' then raise Exception.Create('"operation" is required');

    if      Op = 'list_topics'    then R := DoListTopics(AParams)
    else if Op = 'get_topic'      then R := DoGetTopic(AParams)
    else if Op = 'create_topic'   then R := DoCreateTopic(AParams)
    else if Op = 'delete_topic'   then R := DoDeleteTopic(AParams)
    else if Op = 'produce'        then R := DoProduce(AParams)
    else if Op = 'consume'        then R := DoConsume(AParams)
    else if Op = 'list_consumers' then R := DoListConsumers(AParams)
    else if Op = 'get_offsets'    then R := DoGetOffsets(AParams)
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

constructor TKafkaTool.Create;
begin
  inherited;
  FName        := 'mcp-kafka';
  FDescription :=
    'Apache Kafka via Confluent REST Proxy API (HTTP-based, no driver required). ' +
    'Operations: ' +
    'list_topics (params: baseUrl), ' +
    'get_topic (params: baseUrl, topic), ' +
    'create_topic (params: baseUrl, clusterId, topic, body?), ' +
    'delete_topic (params: baseUrl, clusterId, topic), ' +
    'produce (params: baseUrl, topic, body?, key?), ' +
    'consume (params: baseUrl, topic, partition?, offset?, count?), ' +
    'list_consumers (params: baseUrl, group), ' +
    'get_offsets (params: baseUrl, topic, partition?). ' +
    'For Confluent Cloud: provide apiKey and apiSecret (used as Basic auth). ' +
    'For local Confluent REST Proxy: baseUrl is typically http://localhost:8082.';
end;

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-kafka',
    function: IAiMCPTool
    begin
      Result := TKafkaTool.Create;
    end);
  WriteLn(ErrOutput, '[MCPService]   + mcp-kafka');
end;

end.
