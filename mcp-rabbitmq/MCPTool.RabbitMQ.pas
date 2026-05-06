unit MCPTool.RabbitMQ;

{
  MCPTool.RabbitMQ  ·  mcp-rabbitmq  (port 8637)
  RabbitMQ Management HTTP API v1.

  Operations:
    list_queues     - list all queues (optionally by vhost)
    get_queue       - get queue details
    create_queue    - declare a queue
    delete_queue    - delete a queue
    purge_queue     - purge all messages from a queue
    publish         - publish a message to an exchange
    get_messages    - get (consume) messages from a queue
    list_exchanges  - list exchanges
    list_vhosts     - list virtual hosts
    list_connections- list connections
    overview        - broker overview stats
}

interface

uses
  uMakerAi.MCPServer.Core,
  System.JSON;

type
  TRabbitMQParams = class
  private
    FOperation  : string;
    FHost       : string;
    FPort       : Integer;
    FUsername   : string;
    FPassword   : string;
    FVhost      : string;
    FQueue      : string;
    FExchange   : string;
    FRoutingKey : string;
    FBody       : string;
    FCount      : Integer;
    FDurable    : Boolean;
    FAutoDelete : Boolean;
  public
    constructor Create;

    [AiMCPSchemaDescription('Operation: list_queues, get_queue, create_queue, delete_queue, purge_queue, publish, get_messages, list_exchanges, list_vhosts, list_connections, overview')]
    property Operation  : string  read FOperation  write FOperation;

    [AiMCPSchemaDescription('RabbitMQ host (default: localhost)')]
    property Host       : string  read FHost       write FHost;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Management API port (default: 15672)')]
    property Port       : Integer read FPort       write FPort;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Username (default: guest)')]
    property Username   : string  read FUsername   write FUsername;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Password (default: guest)')]
    property Password   : string  read FPassword   write FPassword;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Virtual host (default: /)')]
    property Vhost      : string  read FVhost      write FVhost;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Queue name')]
    property Queue      : string  read FQueue      write FQueue;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Exchange name (default: amq.default for publish)')]
    property Exchange   : string  read FExchange   write FExchange;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Routing key (usually equals queue name for default exchange)')]
    property RoutingKey : string  read FRoutingKey write FRoutingKey;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Message body or queue definition JSON')]
    property Body       : string  read FBody       write FBody;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Number of messages to get (default: 1)')]
    property Count      : Integer read FCount      write FCount;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Durable queue (default: true)')]
    property Durable    : Boolean read FDurable    write FDurable;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Auto-delete queue when unused (default: false)')]
    property AutoDelete : Boolean read FAutoDelete write FAutoDelete;
  end;

  TRabbitMQTool = class(TAiMCPToolBase<TRabbitMQParams>)
  private
    function BaseURL(const P: TRabbitMQParams): string;
    function AuthHeader(const P: TRabbitMQParams): string;
    function VhostEnc(const Vhost: string): string;
    function ApiGet(const URL, Auth: string): TJSONObject;
    function ApiPost(const URL, Auth, Body: string): TJSONObject;
    function ApiPut(const URL, Auth, Body: string): TJSONObject;
    function ApiDelete(const URL, Auth: string): TJSONObject;

    function DoListQueues(const P: TRabbitMQParams): TJSONObject;
    function DoGetQueue(const P: TRabbitMQParams): TJSONObject;
    function DoCreateQueue(const P: TRabbitMQParams): TJSONObject;
    function DoDeleteQueue(const P: TRabbitMQParams): TJSONObject;
    function DoPurgeQueue(const P: TRabbitMQParams): TJSONObject;
    function DoPublish(const P: TRabbitMQParams): TJSONObject;
    function DoGetMessages(const P: TRabbitMQParams): TJSONObject;
    function DoListExchanges(const P: TRabbitMQParams): TJSONObject;
    function DoListVhosts(const P: TRabbitMQParams): TJSONObject;
    function DoListConnections(const P: TRabbitMQParams): TJSONObject;
    function DoOverview(const P: TRabbitMQParams): TJSONObject;
  protected
    function ExecuteWithParams(const AParams: TRabbitMQParams;
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

{ TRabbitMQParams }

constructor TRabbitMQParams.Create;
begin
  inherited;
  FHost       := 'localhost';
  FPort       := 15672;
  FUsername   := 'guest';
  FPassword   := 'guest';
  FVhost      := '/';
  FCount      := 1;
  FDurable    := True;
  FAutoDelete := False;
end;

{ TRabbitMQTool }

constructor TRabbitMQTool.Create;
begin
  inherited;
  FName        := 'mcp-rabbitmq';
  FDescription :=
    'RabbitMQ Management HTTP API — queues, exchanges, messages, connections. ' +
    'Operations: list_queues (vhost?), get_queue (queue, vhost?), ' +
    'create_queue (queue, vhost?, durable?, autoDelete?), delete_queue (queue, vhost?), ' +
    'purge_queue (queue, vhost?), publish (exchange?, routingKey, body), ' +
    'get_messages (queue, count?, vhost?), list_exchanges (vhost?), ' +
    'list_vhosts, list_connections, overview. ' +
    'Auth: host (default localhost), port (default 15672), username, password.';
end;

function TRabbitMQTool.BaseURL(const P: TRabbitMQParams): string;
var
  H: string;
  Pt: Integer;
begin
  H  := Trim(P.Host); if H = '' then H := 'localhost';
  Pt := P.Port;       if Pt <= 0 then Pt := 15672;
  Result := Format('http://%s:%d/api', [H, Pt]);
end;

function TRabbitMQTool.AuthHeader(const P: TRabbitMQParams): string;
var
  U, Pw: string;
  Bytes: TBytes;
begin
  U  := Trim(P.Username); if U  = '' then U  := 'guest';
  Pw := Trim(P.Password); if Pw = '' then Pw := 'guest';
  Bytes  := TEncoding.UTF8.GetBytes(U + ':' + Pw);
  Result := 'Basic ' + TNetEncoding.Base64.EncodeBytesToString(Bytes);
end;

function TRabbitMQTool.VhostEnc(const Vhost: string): string;
var
  V: string;
begin
  V := Trim(Vhost); if V = '' then V := '/';
  Result := TNetEncoding.URL.Encode(V);
end;

function TRabbitMQTool.ApiGet(const URL, Auth: string): TJSONObject;
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
    J   := TJSONObject.ParseJSONValue(Raw);
    if J is TJSONObject then
      Result := J as TJSONObject
    else
    begin
      Result := TJSONObject.Create;
      if J <> nil then Result.AddPair('data', J)
      else Result.AddPair('raw', Raw);
    end;
  finally
    HTTP.Free;
  end;
end;

function TRabbitMQTool.ApiPost(const URL, Auth, Body: string): TJSONObject;
var
  HTTP: THTTPClient;
  Resp: IHTTPResponse;
  Strm: TStringStream;
  Raw: string;
  J: TJSONValue;
begin
  HTTP := THTTPClient.Create;
  Strm := TStringStream.Create(Body, TEncoding.UTF8);
  try
    Resp := HTTP.Post(URL, Strm, nil,
      [TNameValuePair.Create('Authorization', Auth),
       TNameValuePair.Create('Content-Type',  'application/json'),
       TNameValuePair.Create('Accept',         'application/json')]);
    Raw := Resp.ContentAsString();
    J   := TJSONObject.ParseJSONValue(Raw);
    if J is TJSONObject then
      Result := J as TJSONObject
    else
    begin
      Result := TJSONObject.Create;
      Result.AddPair('status', IntToStr(Resp.StatusCode));
      Result.AddPair('ok', TJSONBool.Create(Resp.StatusCode < 300));
      if J <> nil then Result.AddPair('data', J)
      else Result.AddPair('raw', Raw);
    end;
  finally
    Strm.Free;
    HTTP.Free;
  end;
end;

function TRabbitMQTool.ApiPut(const URL, Auth, Body: string): TJSONObject;
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
       TNameValuePair.Create('Content-Type',  'application/json')]);
    Result := TJSONObject.Create;
    Result.AddPair('status', IntToStr(Resp.StatusCode));
    Result.AddPair('ok', TJSONBool.Create(Resp.StatusCode < 300));
  finally
    Strm.Free;
    HTTP.Free;
  end;
end;

function TRabbitMQTool.ApiDelete(const URL, Auth: string): TJSONObject;
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

function TRabbitMQTool.DoListQueues(const P: TRabbitMQParams): TJSONObject;
var
  Vh: string;
begin
  Vh := Trim(P.Vhost);
  if Vh <> '' then
    Result := ApiGet(
      Format('%s/queues/%s', [BaseURL(P), VhostEnc(Vh)]),
      AuthHeader(P))
  else
    Result := ApiGet(BaseURL(P) + '/queues', AuthHeader(P));
end;

function TRabbitMQTool.DoGetQueue(const P: TRabbitMQParams): TJSONObject;
begin
  if Trim(P.Queue) = '' then raise Exception.Create('"queue" required');
  Result := ApiGet(
    Format('%s/queues/%s/%s', [BaseURL(P), VhostEnc(P.Vhost), TNetEncoding.URL.Encode(Trim(P.Queue))]),
    AuthHeader(P));
end;

function TRabbitMQTool.DoCreateQueue(const P: TRabbitMQParams): TJSONObject;
var
  Dur, AD: string;
begin
  if Trim(P.Queue) = '' then raise Exception.Create('"queue" required');
  if P.Durable then Dur := 'true' else Dur := 'false';
  if P.AutoDelete then AD := 'true' else AD := 'false';
  Result := ApiPut(
    Format('%s/queues/%s/%s', [BaseURL(P), VhostEnc(P.Vhost), TNetEncoding.URL.Encode(Trim(P.Queue))]),
    AuthHeader(P),
    Format('{"durable":%s,"auto_delete":%s,"arguments":{}}', [Dur, AD]));
end;

function TRabbitMQTool.DoDeleteQueue(const P: TRabbitMQParams): TJSONObject;
begin
  if Trim(P.Queue) = '' then raise Exception.Create('"queue" required');
  Result := ApiDelete(
    Format('%s/queues/%s/%s', [BaseURL(P), VhostEnc(P.Vhost), TNetEncoding.URL.Encode(Trim(P.Queue))]),
    AuthHeader(P));
end;

function TRabbitMQTool.DoPurgeQueue(const P: TRabbitMQParams): TJSONObject;
begin
  if Trim(P.Queue) = '' then raise Exception.Create('"queue" required');
  Result := ApiDelete(
    Format('%s/queues/%s/%s/contents', [BaseURL(P), VhostEnc(P.Vhost), TNetEncoding.URL.Encode(Trim(P.Queue))]),
    AuthHeader(P));
end;

function TRabbitMQTool.DoPublish(const P: TRabbitMQParams): TJSONObject;
var
  Exch, RK, Msg, PayloadEnc: string;
begin
  RK  := Trim(P.RoutingKey);
  Exch := Trim(P.Exchange); if Exch = '' then Exch := 'amq.default';
  Msg  := Trim(P.Body);
  PayloadEnc := Msg.Replace('\','\\').Replace('"','\"').Replace(#10,'\n').Replace(#13,'');
  Result := ApiPost(
    Format('%s/exchanges/%s/%s/publish', [BaseURL(P), VhostEnc(P.Vhost), TNetEncoding.URL.Encode(Exch)]),
    AuthHeader(P),
    Format('{"properties":{},"routing_key":"%s","payload":"%s","payload_encoding":"string"}',
      [RK.Replace('"','\"'), PayloadEnc]));
end;

function TRabbitMQTool.DoGetMessages(const P: TRabbitMQParams): TJSONObject;
var
  Cnt: Integer;
begin
  if Trim(P.Queue) = '' then raise Exception.Create('"queue" required');
  Cnt := P.Count; if Cnt <= 0 then Cnt := 1;
  Result := ApiPost(
    Format('%s/queues/%s/%s/get', [BaseURL(P), VhostEnc(P.Vhost), TNetEncoding.URL.Encode(Trim(P.Queue))]),
    AuthHeader(P),
    Format('{"count":%d,"ackmode":"ack_requeue_true","encoding":"auto","truncate":50000}', [Cnt]));
end;

function TRabbitMQTool.DoListExchanges(const P: TRabbitMQParams): TJSONObject;
var
  Vh: string;
begin
  Vh := Trim(P.Vhost);
  if Vh <> '' then
    Result := ApiGet(
      Format('%s/exchanges/%s', [BaseURL(P), VhostEnc(Vh)]),
      AuthHeader(P))
  else
    Result := ApiGet(BaseURL(P) + '/exchanges', AuthHeader(P));
end;

function TRabbitMQTool.DoListVhosts(const P: TRabbitMQParams): TJSONObject;
begin
  Result := ApiGet(BaseURL(P) + '/vhosts', AuthHeader(P));
end;

function TRabbitMQTool.DoListConnections(const P: TRabbitMQParams): TJSONObject;
begin
  Result := ApiGet(BaseURL(P) + '/connections', AuthHeader(P));
end;

function TRabbitMQTool.DoOverview(const P: TRabbitMQParams): TJSONObject;
begin
  Result := ApiGet(BaseURL(P) + '/overview', AuthHeader(P));
end;

function TRabbitMQTool.ExecuteWithParams(const AParams: TRabbitMQParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op: string;
  R:  TJSONObject;
begin
  try
    Op := LowerCase(Trim(AParams.Operation));
    if Op = '' then raise Exception.Create('"operation" is required');

    if      Op = 'list_queues'      then R := DoListQueues(AParams)
    else if Op = 'get_queue'        then R := DoGetQueue(AParams)
    else if Op = 'create_queue'     then R := DoCreateQueue(AParams)
    else if Op = 'delete_queue'     then R := DoDeleteQueue(AParams)
    else if Op = 'purge_queue'      then R := DoPurgeQueue(AParams)
    else if Op = 'publish'          then R := DoPublish(AParams)
    else if Op = 'get_messages'     then R := DoGetMessages(AParams)
    else if Op = 'list_exchanges'   then R := DoListExchanges(AParams)
    else if Op = 'list_vhosts'      then R := DoListVhosts(AParams)
    else if Op = 'list_connections' then R := DoListConnections(AParams)
    else if Op = 'overview'         then R := DoOverview(AParams)
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
  AServer.RegisterTool('mcp-rabbitmq',
    function: IAiMCPTool
    begin
      Result := TRabbitMQTool.Create;
    end);
  WriteLn(ErrOutput, '[MCPService]   + mcp-rabbitmq');
end;

end.
