unit MCPTool.WebSocket;

(*
  MCPTool.WebSocket  ·  mcp-websocket  (port 8653)

  Tests and interacts with WebSocket servers via HTTP upgrade handshake and
  subprocess-based CLI tools (wscat / websocat).

  Operations:
    test_connection        - HTTP upgrade handshake check (ws:// -> http://)
    send_message           - send/receive via wscat or websocat subprocess
    check_websocket_health - upgrade check + parse HTTP response body for health info
    list_ws_routes         - GET Socket.IO discovery endpoint
    socketio_connect       - test Socket.IO endpoint availability
    get_server_info        - GET base URL, return status + headers
    proxy_http             - regular HTTP request (GET/POST/PUT/DELETE) to base URL
*)

interface

uses
  uMakerAi.MCPServer.Core,
  System.JSON;

type
  TWebSocketParams = class
  private
    FOperation  : string;
    FUrl        : string;
    FMessage    : string;
    FHeaders    : string;
    FMethod     : string;
    FBody       : string;
    FTimeoutSec : Integer;
  public
    constructor Create;

    [AiMCPSchemaDescription('Operation: test_connection, send_message, check_websocket_health, ' +
      'list_ws_routes, socketio_connect, get_server_info, proxy_http')]
    property Operation  : string  read FOperation  write FOperation;

    [AiMCPSchemaDescription('WebSocket URL (ws:// or wss://) or HTTP URL for proxy_http / get_server_info')]
    property Url        : string  read FUrl        write FUrl;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Message to send (used by send_message)')]
    property WsMessage  : string  read FMessage    write FMessage;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Additional HTTP headers as JSON object string e.g. {"Authorization":"Bearer token"}')]
    property Headers    : string  read FHeaders    write FHeaders;

    [AiMCPOptional]
    [AiMCPSchemaDescription('HTTP method for proxy_http: GET, POST, PUT, DELETE (default: GET)')]
    property HttpMethod : string  read FMethod     write FMethod;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Request body for proxy_http POST/PUT')]
    property Body       : string  read FBody       write FBody;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Connection timeout in seconds (default: 10)')]
    property TimeoutSec : Integer read FTimeoutSec write FTimeoutSec;
  end;

  TWebSocketTool = class(TAiMCPToolBase<TWebSocketParams>)
  private
    function RunCmd(const Cmd: string; TimeoutSec: Integer): TJSONObject;
    function WsUrlToHttp(const Url: string): string;
    function ApplyExtraHeaders(Client: TObject; const HeadersJSON: string): string;

    function DoTestConnection(const P: TWebSocketParams): TJSONObject;
    function DoSendMessage(const P: TWebSocketParams): TJSONObject;
    function DoCheckHealth(const P: TWebSocketParams): TJSONObject;
    function DoListWsRoutes(const P: TWebSocketParams): TJSONObject;
    function DoSocketIoConnect(const P: TWebSocketParams): TJSONObject;
    function DoGetServerInfo(const P: TWebSocketParams): TJSONObject;
    function DoProxyHttp(const P: TWebSocketParams): TJSONObject;

    function HttpGetWithUpgrade(const HttpUrl: string; TimeoutSec: Integer;
      const ExtraHeadersJSON: string; out StatusCode: Integer;
      out ResponseBody: string): string;
    function HttpRequest(const Url, Method, Body, HeadersJSON: string;
      TimeoutSec: Integer; out StatusCode: Integer;
      out ResponseBody: string): string;
  protected
    function ExecuteWithParams(const AParams: TWebSocketParams;
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
  Winapi.Windows;

{ TWebSocketParams }

constructor TWebSocketParams.Create;
begin
  inherited;
  FTimeoutSec := 10;
  FMethod     := 'GET';
end;

{ TWebSocketTool }

constructor TWebSocketTool.Create;
begin
  inherited;
  FName        := 'mcp-websocket';
  FDescription :=
    'Tests and interacts with WebSocket servers via HTTP upgrade handshake and CLI tools. ' +
    'Operations: ' +
    'test_connection (url) — check WebSocket server via HTTP upgrade; ' +
    'send_message (url, wsMessage) — send/receive via wscat or websocat subprocess; ' +
    'check_websocket_health (url) — upgrade check + parse HTTP body for health info; ' +
    'list_ws_routes (url) — GET Socket.IO discovery endpoint at {baseUrl}/socket.io/; ' +
    'socketio_connect (url) — test Socket.IO polling endpoint; ' +
    'get_server_info (url) — GET base URL, return status and headers; ' +
    'proxy_http (url, httpMethod?, body?, headers?) — regular HTTP request. ' +
    'Optional: headers (JSON), timeoutSec (default 10).';
end;

(* ── RunCmd: run a shell command, capture stdout+stderr ── *)

function TWebSocketTool.RunCmd(const Cmd: string; TimeoutSec: Integer): TJSONObject;
var
  SA:         TSecurityAttributes;
  PipeRead:   THandle;
  PipeWrite:  THandle;
  PI:         TProcessInformation;
  SI:         TStartupInfo;
  ExitCode:   DWORD;
  WaitResult: DWORD;
  Buffer:     array[0..4095] of AnsiChar;
  BytesRead:  DWORD;
  Output:     string;
  TOut:       DWORD;
  CmdLine:    string;
begin
  SA.nLength              := SizeOf(SA);
  SA.lpSecurityDescriptor := nil;
  SA.bInheritHandle       := True;

  if not CreatePipe(PipeRead, PipeWrite, @SA, 0) then
    raise Exception.Create('CreatePipe failed: ' + SysErrorMessage(GetLastError));
  SetHandleInformation(PipeRead, HANDLE_FLAG_INHERIT, 0);

  FillChar(SI, SizeOf(SI), 0);
  SI.cb         := SizeOf(SI);
  SI.dwFlags    := STARTF_USESTDHANDLES;
  SI.hStdOutput := PipeWrite;
  SI.hStdError  := PipeWrite;
  SI.hStdInput  := INVALID_HANDLE_VALUE;

  TOut    := TimeoutSec;
  if TOut <= 0 then TOut := 10;

  CmdLine := 'cmd.exe /c ' + Cmd + ' 2>&1';

  FillChar(PI, SizeOf(PI), 0);
  if not CreateProcess(nil, PChar(CmdLine), nil, nil, True,
    CREATE_NO_WINDOW, nil, nil, SI, PI) then
  begin
    CloseHandle(PipeWrite);
    CloseHandle(PipeRead);
    raise Exception.Create('Failed to start process: ' + SysErrorMessage(GetLastError));
  end;

  CloseHandle(PipeWrite);
  Output := '';
  repeat
    if not ReadFile(PipeRead, Buffer, SizeOf(Buffer) - 1, BytesRead, nil) then Break;
    if BytesRead = 0 then Break;
    Buffer[BytesRead] := #0;
    Output := Output + string(AnsiString(PChar(@Buffer[0])));
  until False;

  WaitResult := WaitForSingleObject(PI.hProcess, TOut * 1000);
  GetExitCodeProcess(PI.hProcess, ExitCode);
  CloseHandle(PI.hProcess);
  CloseHandle(PI.hThread);
  CloseHandle(PipeRead);

  Result := TJSONObject.Create;
  Result.AddPair('output',    Output.Trim);
  Result.AddPair('exit_code', TJSONNumber.Create(ExitCode));
  Result.AddPair('ok',        TJSONBool.Create(ExitCode = 0));
  if WaitResult = WAIT_TIMEOUT then
    Result.AddPair('timeout', TJSONBool.Create(True));
end;

(* ── WsUrlToHttp: convert ws:// -> http://, wss:// -> https:// ── *)

function TWebSocketTool.WsUrlToHttp(const Url: string): string;
var
  Lower: string;
begin
  Lower := LowerCase(Url);
  if Copy(Lower, 1, 6) = 'wss://' then
    Result := 'https://' + Copy(Url, 7, MaxInt)
  else if Copy(Lower, 1, 5) = 'ws://' then
    Result := 'http://' + Copy(Url, 6, MaxInt)
  else
    Result := Url;
end;

(* ── ApplyExtraHeaders: parse JSON header object into THTTPClient ── *)

function TWebSocketTool.ApplyExtraHeaders(Client: TObject;
  const HeadersJSON: string): string;
var
  JV:   TJSONValue;
  JObj: TJSONObject;
  Pair: TJSONPair;
  HC:   THTTPClient;
begin
  Result := '';
  if Trim(HeadersJSON) = '' then Exit;
  HC := Client as THTTPClient;
  JV := TJSONObject.ParseJSONValue(HeadersJSON);
  if not Assigned(JV) then Exit;
  try
    if JV is TJSONObject then
    begin
      JObj := TJSONObject(JV);
      for Pair in JObj do
        HC.CustomHeaders[Pair.JsonString.Value] := Pair.JsonValue.Value;
    end;
  finally
    JV.Free;
  end;
end;

(* ── HttpGetWithUpgrade: send WS upgrade headers, return status/body ── *)

function TWebSocketTool.HttpGetWithUpgrade(const HttpUrl: string;
  TimeoutSec: Integer; const ExtraHeadersJSON: string;
  out StatusCode: Integer; out ResponseBody: string): string;
var
  Client:   THTTPClient;
  Response: IHTTPResponse;
  Stream:   TStringStream;
  Pair:     TJSONPair;
  JV:       TJSONValue;
  JObj:     TJSONObject;
begin
  Result       := '';
  StatusCode   := 0;
  ResponseBody := '';

  Client := THTTPClient.Create;
  try
    Client.ConnectionTimeout := TimeoutSec * 1000;
    Client.ResponseTimeout   := TimeoutSec * 1000;

    Client.CustomHeaders['Upgrade']               := 'websocket';
    Client.CustomHeaders['Connection']            := 'Upgrade';
    Client.CustomHeaders['Sec-WebSocket-Key']     := 'dGhlIHNhbXBsZSBub25jZQ==';
    Client.CustomHeaders['Sec-WebSocket-Version'] := '13';

    if Trim(ExtraHeadersJSON) <> '' then
    begin
      JV := TJSONObject.ParseJSONValue(ExtraHeadersJSON);
      if Assigned(JV) then
      try
        if JV is TJSONObject then
        begin
          JObj := TJSONObject(JV);
          for Pair in JObj do
            Client.CustomHeaders[Pair.JsonString.Value] := Pair.JsonValue.Value;
        end;
      finally
        JV.Free;
      end;
    end;

    Stream := TStringStream.Create('', TEncoding.UTF8);
    try
      try
        Response := Client.Get(HttpUrl, Stream);
        StatusCode   := Response.StatusCode;
        ResponseBody := Stream.DataString;
        Result       := Response.StatusText;
      except
        on E: Exception do
        begin
          Result       := E.Message;
          StatusCode   := -1;
          ResponseBody := '';
        end;
      end;
    finally
      Stream.Free;
    end;
  finally
    Client.Free;
  end;
end;

(* ── HttpRequest: generic HTTP request helper ── *)

function TWebSocketTool.HttpRequest(const Url, Method, Body,
  HeadersJSON: string; TimeoutSec: Integer; out StatusCode: Integer;
  out ResponseBody: string): string;
var
  Client:      THTTPClient;
  Response:    IHTTPResponse;
  Stream:      TStringStream;
  BodyStream:  TStringStream;
  Meth:        string;
  Pair:        TJSONPair;
  JV:          TJSONValue;
  JObj:        TJSONObject;
begin
  Result       := '';
  StatusCode   := 0;
  ResponseBody := '';

  Client := THTTPClient.Create;
  try
    Client.ConnectionTimeout := TimeoutSec * 1000;
    Client.ResponseTimeout   := TimeoutSec * 1000;

    if Trim(HeadersJSON) <> '' then
    begin
      JV := TJSONObject.ParseJSONValue(HeadersJSON);
      if Assigned(JV) then
      try
        if JV is TJSONObject then
        begin
          JObj := TJSONObject(JV);
          for Pair in JObj do
            Client.CustomHeaders[Pair.JsonString.Value] := Pair.JsonValue.Value;
        end;
      finally
        JV.Free;
      end;
    end;

    Meth   := UpperCase(Trim(Method));
    if Meth = '' then Meth := 'GET';

    Stream := TStringStream.Create('', TEncoding.UTF8);
    try
      try
        if (Meth = 'POST') or (Meth = 'PUT') or (Meth = 'PATCH') then
        begin
          BodyStream := TStringStream.Create(Body, TEncoding.UTF8);
          try
            if Meth = 'POST' then
              Response := Client.Post(Url, BodyStream, Stream)
            else if Meth = 'PUT' then
              Response := Client.Put(Url, BodyStream, Stream)
            else
              Response := Client.Patch(Url, BodyStream, Stream);
          finally
            BodyStream.Free;
          end;
        end
        else if Meth = 'DELETE' then
          Response := Client.Delete(Url, Stream)
        else
          Response := Client.Get(Url, Stream);

        StatusCode   := Response.StatusCode;
        ResponseBody := Stream.DataString;
        Result       := Response.StatusText;
      except
        on E: Exception do
        begin
          Result       := E.Message;
          StatusCode   := -1;
          ResponseBody := '';
        end;
      end;
    finally
      Stream.Free;
    end;
  finally
    Client.Free;
  end;
end;

(* ── Operations ── *)

function TWebSocketTool.DoTestConnection(const P: TWebSocketParams): TJSONObject;
var
  HttpUrl:      string;
  StatusCode:   Integer;
  ResponseBody: string;
  StatusText:   string;
  Upgraded:     Boolean;
  Msg:          string;
begin
  if Trim(P.Url) = '' then
    raise Exception.Create('"url" is required');

  HttpUrl    := WsUrlToHttp(Trim(P.Url));
  StatusText := HttpGetWithUpgrade(HttpUrl, P.TimeoutSec, P.Headers,
    StatusCode, ResponseBody);

  Upgraded := StatusCode = 101;

  if StatusCode = -1 then
    Msg := 'Connection failed: ' + StatusText
  else if Upgraded then
    Msg := 'WebSocket upgrade accepted'
  else if StatusCode = 200 then
    Msg := 'Server responded with 200 OK (not a WebSocket upgrade response)'
  else if StatusCode = 400 then
    Msg := 'Bad Request — server may require a valid WebSocket key or different headers'
  else if StatusCode = 426 then
    Msg := 'Upgrade Required — server confirms WebSocket but rejected this request'
  else
    Msg := 'Server responded with HTTP ' + IntToStr(StatusCode) + ': ' + StatusText;

  Result := TJSONObject.Create;
  Result.AddPair('ok',         TJSONBool.Create(StatusCode >= 0));
  Result.AddPair('upgraded',   TJSONBool.Create(Upgraded));
  Result.AddPair('status',     TJSONNumber.Create(StatusCode));
  Result.AddPair('message',    Msg);
  Result.AddPair('http_url',   HttpUrl);
  if ResponseBody <> '' then
    Result.AddPair('body_preview', Copy(ResponseBody, 1, 256));
end;

function TWebSocketTool.DoSendMessage(const P: TWebSocketParams): TJSONObject;
var
  Url:      string;
  Msg:      string;
  Cmd:      string;
  R:        TJSONObject;
  CheckR:   TJSONObject;
  ToolUsed: string;
  ExitCode: TJSONNumber;
begin
  if Trim(P.Url) = '' then
    raise Exception.Create('"url" is required');
  if Trim(P.WsMessage) = '' then
    raise Exception.Create('"wsMessage" is required for send_message');

  Url := Trim(P.Url);
  Msg := Trim(P.WsMessage).Replace('"', '\"');

  (* Try wscat first *)
  Cmd  := 'wscat --version';
  CheckR := RunCmd(Cmd, 5);
  ExitCode := CheckR.GetValue<TJSONNumber>('exit_code');
  if Assigned(ExitCode) and (ExitCode.AsInt = 0) then
  begin
    CheckR.Free;
    Cmd      := 'wscat -c "' + Url.Replace('"', '\"') + '" --execute "' + Msg + '"';
    R        := RunCmd(Cmd, P.TimeoutSec);
    ToolUsed := 'wscat';
    R.AddPair('tool_used', ToolUsed);
    Result := R;
    Exit;
  end;
  CheckR.Free;

  (* Try websocat *)
  Cmd    := 'websocat --version';
  CheckR := RunCmd(Cmd, 5);
  ExitCode := CheckR.GetValue<TJSONNumber>('exit_code');
  if Assigned(ExitCode) and (ExitCode.AsInt = 0) then
  begin
    CheckR.Free;
    Cmd      := 'echo "' + Msg + '" | websocat "' + Url.Replace('"', '\"') + '"';
    R        := RunCmd(Cmd, P.TimeoutSec);
    ToolUsed := 'websocat';
    R.AddPair('tool_used', ToolUsed);
    Result := R;
    Exit;
  end;
  CheckR.Free;

  Result := TJSONObject.Create;
  Result.AddPair('ok',      TJSONBool.Create(False));
  Result.AddPair('error',   'Neither wscat nor websocat found in PATH. ' +
    'Install with: npm install -g wscat   or   cargo install websocat');
  Result.AddPair('url',     Url);
  Result.AddPair('message', P.WsMessage);
end;

function TWebSocketTool.DoCheckHealth(const P: TWebSocketParams): TJSONObject;
var
  HttpUrl:      string;
  StatusCode:   Integer;
  ResponseBody: string;
  StatusText:   string;
  Upgraded:     Boolean;
  Msg:          string;
  BodyJSON:     TJSONValue;
begin
  if Trim(P.Url) = '' then
    raise Exception.Create('"url" is required');

  HttpUrl    := WsUrlToHttp(Trim(P.Url));
  StatusText := HttpGetWithUpgrade(HttpUrl, P.TimeoutSec, P.Headers,
    StatusCode, ResponseBody);

  Upgraded := StatusCode = 101;

  if StatusCode = -1 then
    Msg := 'Connection failed: ' + StatusText
  else if Upgraded then
    Msg := 'WebSocket upgrade accepted'
  else
    Msg := 'HTTP ' + IntToStr(StatusCode) + ': ' + StatusText;

  Result := TJSONObject.Create;
  Result.AddPair('ok',       TJSONBool.Create(StatusCode >= 0));
  Result.AddPair('upgraded', TJSONBool.Create(Upgraded));
  Result.AddPair('status',   TJSONNumber.Create(StatusCode));
  Result.AddPair('message',  Msg);
  Result.AddPair('http_url', HttpUrl);

  if ResponseBody <> '' then
  begin
    BodyJSON := TJSONObject.ParseJSONValue(ResponseBody);
    if Assigned(BodyJSON) then
    begin
      Result.AddPair('health_json', BodyJSON);
    end
    else
    begin
      Result.AddPair('body_preview', Copy(ResponseBody, 1, 512));
    end;
  end;
end;

function TWebSocketTool.DoListWsRoutes(const P: TWebSocketParams): TJSONObject;
var
  BaseUrl:      string;
  TargetUrl:    string;
  StatusCode:   Integer;
  ResponseBody: string;
  StatusText:   string;
  BodyJSON:     TJSONValue;
begin
  if Trim(P.Url) = '' then
    raise Exception.Create('"url" is required');

  BaseUrl   := WsUrlToHttp(Trim(P.Url));
  (* Strip trailing slash *)
  if (Length(BaseUrl) > 0) and (BaseUrl[Length(BaseUrl)] = '/') then
    BaseUrl := Copy(BaseUrl, 1, Length(BaseUrl) - 1);

  TargetUrl := BaseUrl + '/socket.io/?EIO=4&transport=polling';

  StatusText := HttpRequest(TargetUrl, 'GET', '', P.Headers, P.TimeoutSec,
    StatusCode, ResponseBody);

  Result := TJSONObject.Create;
  Result.AddPair('ok',         TJSONBool.Create((StatusCode >= 200) and (StatusCode < 300)));
  Result.AddPair('status',     TJSONNumber.Create(StatusCode));
  Result.AddPair('target_url', TargetUrl);

  if ResponseBody <> '' then
  begin
    BodyJSON := TJSONObject.ParseJSONValue(ResponseBody);
    if Assigned(BodyJSON) then
      Result.AddPair('response_json', BodyJSON)
    else
      Result.AddPair('response_body', Copy(ResponseBody, 1, 1024));
  end;

  if StatusCode = -1 then
    Result.AddPair('error', StatusText);
end;

function TWebSocketTool.DoSocketIoConnect(const P: TWebSocketParams): TJSONObject;
var
  BaseUrl:      string;
  TargetUrl:    string;
  StatusCode:   Integer;
  ResponseBody: string;
  StatusText:   string;
  BodyJSON:     TJSONValue;
  Available:    Boolean;
begin
  if Trim(P.Url) = '' then
    raise Exception.Create('"url" is required');

  BaseUrl := WsUrlToHttp(Trim(P.Url));
  if (Length(BaseUrl) > 0) and (BaseUrl[Length(BaseUrl)] = '/') then
    BaseUrl := Copy(BaseUrl, 1, Length(BaseUrl) - 1);

  TargetUrl := BaseUrl + '/socket.io/?EIO=4&transport=polling';

  StatusText := HttpRequest(TargetUrl, 'GET', '', P.Headers, P.TimeoutSec,
    StatusCode, ResponseBody);

  Available := (StatusCode >= 200) and (StatusCode < 400);

  Result := TJSONObject.Create;
  Result.AddPair('ok',                TJSONBool.Create(Available));
  Result.AddPair('socketio_available', TJSONBool.Create(Available));
  Result.AddPair('status',            TJSONNumber.Create(StatusCode));
  Result.AddPair('endpoint',          TargetUrl);

  if ResponseBody <> '' then
  begin
    BodyJSON := TJSONObject.ParseJSONValue(ResponseBody);
    if Assigned(BodyJSON) then
      Result.AddPair('socketio_data', BodyJSON)
    else
      Result.AddPair('response_body', Copy(ResponseBody, 1, 512));
  end;

  if StatusCode = -1 then
    Result.AddPair('error', StatusText)
  else if not Available then
    Result.AddPair('message', 'Socket.IO endpoint returned HTTP ' +
      IntToStr(StatusCode) + ' — may not be a Socket.IO server');
end;

function TWebSocketTool.DoGetServerInfo(const P: TWebSocketParams): TJSONObject;
var
  BaseUrl:      string;
  StatusCode:   Integer;
  ResponseBody: string;
  StatusText:   string;
  Client:       THTTPClient;
  Response:     IHTTPResponse;
  Stream:       TStringStream;
  HeadersArr:   TJSONArray;
  HeaderPair:   TJSONObject;
  Pair:         TJSONPair;
  JV:           TJSONValue;
  JObj:         TJSONObject;
  I:            Integer;
begin
  if Trim(P.Url) = '' then
    raise Exception.Create('"url" is required');

  BaseUrl    := WsUrlToHttp(Trim(P.Url));
  StatusCode := 0;

  Result := TJSONObject.Create;

  Client := THTTPClient.Create;
  try
    Client.ConnectionTimeout := P.TimeoutSec * 1000;
    Client.ResponseTimeout   := P.TimeoutSec * 1000;

    if Trim(P.Headers) <> '' then
    begin
      JV := TJSONObject.ParseJSONValue(P.Headers);
      if Assigned(JV) then
      try
        if JV is TJSONObject then
        begin
          JObj := TJSONObject(JV);
          for Pair in JObj do
            Client.CustomHeaders[Pair.JsonString.Value] := Pair.JsonValue.Value;
        end;
      finally
        JV.Free;
      end;
    end;

    Stream := TStringStream.Create('', TEncoding.UTF8);
    try
      try
        Response     := Client.Get(BaseUrl, Stream);
        StatusCode   := Response.StatusCode;
        ResponseBody := Stream.DataString;
        StatusText   := Response.StatusText;

        HeadersArr := TJSONArray.Create;
        for I := 0 to Length(Response.Headers) - 1 do
        begin
          HeaderPair := TJSONObject.Create;
          HeaderPair.AddPair('name',  Response.Headers[I].Name);
          HeaderPair.AddPair('value', Response.Headers[I].Value);
          HeadersArr.Add(HeaderPair);
        end;

        Result.AddPair('ok',              TJSONBool.Create((StatusCode >= 200) and (StatusCode < 400)));
        Result.AddPair('status',          TJSONNumber.Create(StatusCode));
        Result.AddPair('status_text',     StatusText);
        Result.AddPair('url',             BaseUrl);
        Result.AddPair('headers',         HeadersArr);
        Result.AddPair('body_preview',    Copy(ResponseBody, 1, 512));
      except
        on E: Exception do
        begin
          Result.AddPair('ok',    TJSONBool.Create(False));
          Result.AddPair('error', E.Message);
          Result.AddPair('url',   BaseUrl);
        end;
      end;
    finally
      Stream.Free;
    end;
  finally
    Client.Free;
  end;
end;

function TWebSocketTool.DoProxyHttp(const P: TWebSocketParams): TJSONObject;
var
  TargetUrl:    string;
  Meth:         string;
  StatusCode:   Integer;
  ResponseBody: string;
  StatusText:   string;
begin
  if Trim(P.Url) = '' then
    raise Exception.Create('"url" is required');

  TargetUrl := WsUrlToHttp(Trim(P.Url));
  Meth      := UpperCase(Trim(P.HttpMethod));
  if Meth = '' then Meth := 'GET';

  StatusText := HttpRequest(TargetUrl, Meth, P.Body, P.Headers, P.TimeoutSec,
    StatusCode, ResponseBody);

  Result := TJSONObject.Create;
  Result.AddPair('ok',          TJSONBool.Create((StatusCode >= 200) and (StatusCode < 300)));
  Result.AddPair('status',      TJSONNumber.Create(StatusCode));
  Result.AddPair('status_text', StatusText);
  Result.AddPair('method',      Meth);
  Result.AddPair('url',         TargetUrl);

  if ResponseBody <> '' then
  begin
    if StatusCode = -1 then
      Result.AddPair('error', StatusText)
    else
      Result.AddPair('body', Copy(ResponseBody, 1, 8192));
  end;

  if StatusCode = -1 then
    Result.AddPair('error', StatusText);
end;

{ TWebSocketTool.ExecuteWithParams }

function TWebSocketTool.ExecuteWithParams(const AParams: TWebSocketParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op: string;
  R:  TJSONObject;
begin
  try
    Op := LowerCase(Trim(AParams.Operation));
    if Op = '' then
      raise Exception.Create('"operation" is required');

    if      Op = 'test_connection'        then R := DoTestConnection(AParams)
    else if Op = 'send_message'           then R := DoSendMessage(AParams)
    else if Op = 'check_websocket_health' then R := DoCheckHealth(AParams)
    else if Op = 'list_ws_routes'         then R := DoListWsRoutes(AParams)
    else if Op = 'socketio_connect'       then R := DoSocketIoConnect(AParams)
    else if Op = 'get_server_info'        then R := DoGetServerInfo(AParams)
    else if Op = 'proxy_http'             then R := DoProxyHttp(AParams)
    else raise Exception.CreateFmt('Unknown operation "%s". Valid: ' +
      'test_connection, send_message, check_websocket_health, list_ws_routes, ' +
      'socketio_connect, get_server_info, proxy_http', [Op]);

    Result := TAiMCPResponseBuilder.New.AddText(R.ToJSON).Build;
    R.Free;
  except
    on E: Exception do
      Result := TAiMCPResponseBuilder.New
        .AddText('{"ok":false,"error":"' +
          E.Message
            .Replace('\', '\\')
            .Replace('"', '\"')
            .Replace(#10, '\n')
            .Replace(#13, '')
          + '"}')
        .Build;
  end;
end;

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-websocket',
    function: IAiMCPTool
    begin
      Result := TWebSocketTool.Create;
    end);
  WriteLn(ErrOutput, '[MCPService]   + mcp-websocket');
end;

end.
