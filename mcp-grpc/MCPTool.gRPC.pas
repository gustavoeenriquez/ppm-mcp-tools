unit MCPTool.gRPC;

(*
  MCPTool.gRPC  ·  mcp-grpc  (port 8655)
  gRPC service wrapper — interact with gRPC services via grpcurl CLI
  or via gRPC-Gateway / gRPC-Web HTTP/JSON transcoding.

  Operations:
    list_services    - list available gRPC services (grpcurl ... list)
    describe_service - describe a service (grpcurl ... describe ServiceName)
    describe_method  - describe a specific method
    call             - call a gRPC method (plaintext)
    call_tls         - call a gRPC method with TLS
    list_methods     - list methods of a service
    health_check     - check gRPC health via grpc.health.v1.Health/Check
    http_call        - call a gRPC-Gateway HTTP transcoding endpoint (REST)
*)

interface

uses
  uMakerAi.MCPServer.Core,
  System.JSON;

type
  TgRPCParams = class
  private
    FOperation   : string;
    FHost        : string;
    FGrpcPort    : Integer;
    FServiceName : string;
    FMethodName  : string;
    FRequestBody : string;
    FProtoFile   : string;
    FProtoDir    : string;
    FAuthToken   : string;
    FHttpPort    : Integer;
    FHttpPath    : string;
    FHttpBody    : string;
    FTimeoutSec  : Integer;
  public
    constructor Create;

    [AiMCPSchemaDescription('Operation: list_services, describe_service, describe_method, call, call_tls, list_methods, health_check, http_call')]
    property Operation   : string  read FOperation   write FOperation;

    [AiMCPSchemaDescription('gRPC server host e.g. localhost')]
    property Host        : string  read FHost        write FHost;

    [AiMCPOptional]
    [AiMCPSchemaDescription('gRPC port (default: 50051)')]
    property GrpcPort    : Integer read FGrpcPort    write FGrpcPort;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Fully qualified service name e.g. helloworld.Greeter')]
    property ServiceName : string  read FServiceName write FServiceName;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Method name e.g. SayHello')]
    property MethodName  : string  read FMethodName  write FMethodName;

    [AiMCPOptional]
    [AiMCPSchemaDescription('JSON request body string e.g. {"name":"world"}')]
    property RequestBody : string  read FRequestBody write FRequestBody;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Path to .proto file for grpcurl -proto flag')]
    property ProtoFile   : string  read FProtoFile   write FProtoFile;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Path to proto import directory for grpcurl -import-path flag')]
    property ProtoDir    : string  read FProtoDir    write FProtoDir;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Bearer token for grpcurl -H "Authorization: Bearer {token}"')]
    property AuthToken   : string  read FAuthToken   write FAuthToken;

    [AiMCPOptional]
    [AiMCPSchemaDescription('HTTP port for http_call operation (default: 8080)')]
    property HttpPort    : Integer read FHttpPort    write FHttpPort;

    [AiMCPOptional]
    [AiMCPSchemaDescription('URL path for http_call e.g. /v1/hello')]
    property HttpPath    : string  read FHttpPath    write FHttpPath;

    [AiMCPOptional]
    [AiMCPSchemaDescription('JSON body for http_call')]
    property HttpBody    : string  read FHttpBody    write FHttpBody;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Command timeout in seconds (default: 30)')]
    property TimeoutSec  : Integer read FTimeoutSec  write FTimeoutSec;
  end;

  TgRPCTool = class(TAiMCPToolBase<TgRPCParams>)
  private
    function RunCmd(const Cmd: string; TimeoutSec: Integer): TJSONObject;
    function BuildGrpcurlCmd(const P: TgRPCParams; const ExtraArgs: string): string;

    function DoListServices(const P: TgRPCParams): TJSONObject;
    function DoDescribeService(const P: TgRPCParams): TJSONObject;
    function DoDescribeMethod(const P: TgRPCParams): TJSONObject;
    function DoCall(const P: TgRPCParams): TJSONObject;
    function DoCallTLS(const P: TgRPCParams): TJSONObject;
    function DoListMethods(const P: TgRPCParams): TJSONObject;
    function DoHealthCheck(const P: TgRPCParams): TJSONObject;
    function DoHttpCall(const P: TgRPCParams): TJSONObject;
  protected
    function ExecuteWithParams(const AParams: TgRPCParams;
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

{ TgRPCParams }

constructor TgRPCParams.Create;
begin
  inherited;
  FGrpcPort   := 50051;
  FHttpPort   := 8080;
  FTimeoutSec := 30;
end;

{ TgRPCTool }

constructor TgRPCTool.Create;
begin
  inherited;
  FName        := 'mcp-grpc';
  FDescription :=
    'gRPC service wrapper — interact with gRPC services via grpcurl CLI or ' +
    'gRPC-Gateway HTTP/JSON transcoding. ' +
    'Operations: list_services (host, grpcPort?), ' +
    'describe_service (host, grpcPort?, serviceName), ' +
    'describe_method (host, grpcPort?, serviceName, methodName), ' +
    'call (host, grpcPort?, serviceName, methodName, requestBody?), ' +
    'call_tls (host, grpcPort?, serviceName, methodName, requestBody?), ' +
    'list_methods (host, grpcPort?, serviceName), ' +
    'health_check (host, grpcPort?), ' +
    'http_call (host, httpPort?, httpPath, httpBody?). ' +
    'Requires grpcurl in PATH for gRPC operations.';
end;

function TgRPCTool.RunCmd(const Cmd: string; TimeoutSec: Integer): TJSONObject;
var
  SA:         TSecurityAttributes;
  PipeRead, PipeWrite: THandle;
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

  TOut    := TimeoutSec; if TOut <= 0 then TOut := 30;
  CmdLine := 'cmd.exe /c ' + Cmd + ' 2>&1';

  FillChar(PI, SizeOf(PI), 0);
  if not CreateProcess(nil, PChar(CmdLine), nil, nil, True,
    CREATE_NO_WINDOW, nil, nil, SI, PI) then
  begin
    CloseHandle(PipeWrite);
    CloseHandle(PipeRead);
    raise Exception.Create('Failed to run command: ' + SysErrorMessage(GetLastError));
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
  Result.AddPair('output', Output.Trim);
  Result.AddPair('exit_code', TJSONNumber.Create(ExitCode));
  Result.AddPair('ok', TJSONBool.Create(ExitCode = 0));
  if WaitResult = WAIT_TIMEOUT then
    Result.AddPair('timeout', TJSONBool.Create(True));
end;

function TgRPCTool.BuildGrpcurlCmd(const P: TgRPCParams; const ExtraArgs: string): string;
var
  Base: string;
begin
  Base := 'grpcurl -plaintext';
  if P.AuthToken <> '' then Base := Base + ' -H "Authorization: Bearer ' + P.AuthToken + '"';
  if P.ProtoFile <> '' then Base := Base + ' -proto "' + P.ProtoFile + '"';
  if P.ProtoDir  <> '' then Base := Base + ' -import-path "' + P.ProtoDir + '"';
  Base := Base + ' ' + P.Host + ':' + IntToStr(P.GrpcPort);
  Base := Base + ' ' + ExtraArgs;
  Result := Base;
end;

function TgRPCTool.DoListServices(const P: TgRPCParams): TJSONObject;
begin
  Result := RunCmd(BuildGrpcurlCmd(P, 'list'), P.TimeoutSec);
end;

function TgRPCTool.DoDescribeService(const P: TgRPCParams): TJSONObject;
begin
  if Trim(P.ServiceName) = '' then
    raise Exception.Create('"serviceName" is required for describe_service');
  Result := RunCmd(BuildGrpcurlCmd(P, 'describe ' + Trim(P.ServiceName)), P.TimeoutSec);
end;

function TgRPCTool.DoDescribeMethod(const P: TgRPCParams): TJSONObject;
begin
  if Trim(P.ServiceName) = '' then
    raise Exception.Create('"serviceName" is required for describe_method');
  if Trim(P.MethodName) = '' then
    raise Exception.Create('"methodName" is required for describe_method');
  Result := RunCmd(
    BuildGrpcurlCmd(P, 'describe ' + Trim(P.ServiceName) + '.' + Trim(P.MethodName)),
    P.TimeoutSec);
end;

function TgRPCTool.DoCall(const P: TgRPCParams): TJSONObject;
var
  Cmd: string;
  Body: string;
begin
  if Trim(P.ServiceName) = '' then
    raise Exception.Create('"serviceName" is required for call');
  if Trim(P.MethodName) = '' then
    raise Exception.Create('"methodName" is required for call');
  Body := Trim(P.RequestBody);
  if Body = '' then
    Body := '{}';
  Cmd := 'grpcurl -plaintext';
  if P.AuthToken <> '' then Cmd := Cmd + ' -H "Authorization: Bearer ' + P.AuthToken + '"';
  if P.ProtoFile <> '' then Cmd := Cmd + ' -proto "' + P.ProtoFile + '"';
  if P.ProtoDir  <> '' then Cmd := Cmd + ' -import-path "' + P.ProtoDir + '"';
  Cmd := Cmd + ' -d "' + Body.Replace('\', '\\').Replace('"', '\"') + '"';
  Cmd := Cmd + ' ' + P.Host + ':' + IntToStr(P.GrpcPort);
  Cmd := Cmd + ' ' + Trim(P.ServiceName) + '/' + Trim(P.MethodName);
  Result := RunCmd(Cmd, P.TimeoutSec);
end;

function TgRPCTool.DoCallTLS(const P: TgRPCParams): TJSONObject;
var
  Cmd: string;
  Body: string;
begin
  if Trim(P.ServiceName) = '' then
    raise Exception.Create('"serviceName" is required for call_tls');
  if Trim(P.MethodName) = '' then
    raise Exception.Create('"methodName" is required for call_tls');
  Body := Trim(P.RequestBody);
  if Body = '' then
    Body := '{}';
  Cmd := 'grpcurl';
  if P.AuthToken <> '' then Cmd := Cmd + ' -H "Authorization: Bearer ' + P.AuthToken + '"';
  if P.ProtoFile <> '' then Cmd := Cmd + ' -proto "' + P.ProtoFile + '"';
  if P.ProtoDir  <> '' then Cmd := Cmd + ' -import-path "' + P.ProtoDir + '"';
  Cmd := Cmd + ' -d "' + Body.Replace('\', '\\').Replace('"', '\"') + '"';
  Cmd := Cmd + ' ' + P.Host + ':' + IntToStr(P.GrpcPort);
  Cmd := Cmd + ' ' + Trim(P.ServiceName) + '/' + Trim(P.MethodName);
  Result := RunCmd(Cmd, P.TimeoutSec);
end;

function TgRPCTool.DoListMethods(const P: TgRPCParams): TJSONObject;
begin
  if Trim(P.ServiceName) = '' then
    raise Exception.Create('"serviceName" is required for list_methods');
  Result := RunCmd(BuildGrpcurlCmd(P, 'list ' + Trim(P.ServiceName)), P.TimeoutSec);
end;

function TgRPCTool.DoHealthCheck(const P: TgRPCParams): TJSONObject;
var
  Cmd: string;
begin
  Cmd := 'grpcurl -plaintext';
  if P.AuthToken <> '' then Cmd := Cmd + ' -H "Authorization: Bearer ' + P.AuthToken + '"';
  Cmd := Cmd + ' -d "{\"service\":\"\"}"';
  Cmd := Cmd + ' ' + P.Host + ':' + IntToStr(P.GrpcPort);
  Cmd := Cmd + ' grpc.health.v1.Health/Check';
  Result := RunCmd(Cmd, P.TimeoutSec);
end;

function TgRPCTool.DoHttpCall(const P: TgRPCParams): TJSONObject;
var
  Client:   THTTPClient;
  Response: IHTTPResponse;
  Stream:   TStringStream;
  URL:      string;
  RespText: string;
  HttpPt:   Integer;
begin
  if Trim(P.HttpPath) = '' then
    raise Exception.Create('"httpPath" is required for http_call');
  HttpPt := P.HttpPort;
  if HttpPt <= 0 then
    HttpPt := 8080;
  URL    := 'http://' + Trim(P.Host) + ':' + IntToStr(HttpPt) + Trim(P.HttpPath);
  Client := THTTPClient.Create;
  try
    Client.ConnectionTimeout := P.TimeoutSec * 1000;
    Client.ResponseTimeout   := P.TimeoutSec * 1000;
    if P.AuthToken <> '' then
      Client.CustomHeaders['Authorization'] := 'Bearer ' + P.AuthToken;
    Stream := TStringStream.Create(P.HttpBody, TEncoding.UTF8);
    try
      Response := Client.Post(URL, Stream, nil,
        [TNameValuePair.Create('Content-Type', 'application/json')]);
      RespText := Response.ContentAsString(TEncoding.UTF8);
    finally
      Stream.Free;
    end;
    Result := TJSONObject.Create;
    Result.AddPair('ok',          TJSONBool.Create(Response.StatusCode < 400));
    Result.AddPair('status_code', TJSONNumber.Create(Response.StatusCode));
    Result.AddPair('response',    RespText);
  finally
    Client.Free;
  end;
end;

function TgRPCTool.ExecuteWithParams(const AParams: TgRPCParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op: string;
  R:  TJSONObject;
begin
  try
    Op := LowerCase(Trim(AParams.Operation));
    if Op = '' then raise Exception.Create('"operation" is required');
    if Trim(AParams.Host) = '' then raise Exception.Create('"host" is required');

    if      Op = 'list_services'    then R := DoListServices(AParams)
    else if Op = 'describe_service' then R := DoDescribeService(AParams)
    else if Op = 'describe_method'  then R := DoDescribeMethod(AParams)
    else if Op = 'call'             then R := DoCall(AParams)
    else if Op = 'call_tls'         then R := DoCallTLS(AParams)
    else if Op = 'list_methods'     then R := DoListMethods(AParams)
    else if Op = 'health_check'     then R := DoHealthCheck(AParams)
    else if Op = 'http_call'        then R := DoHttpCall(AParams)
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
  AServer.RegisterTool('mcp-grpc',
    function: IAiMCPTool
    begin
      Result := TgRPCTool.Create;
    end);
  WriteLn(ErrOutput, '[MCPService]   + mcp-grpc');
end;

end.
