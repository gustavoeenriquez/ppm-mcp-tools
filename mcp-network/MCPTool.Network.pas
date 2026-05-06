unit MCPTool.Network;

{
  MCPTool.Network  ·  mcp-network

  Network diagnostics using Delphi native + OS CLI.
  No external dependencies beyond Delphi RTL/VCL/Indy.

  Operations:
    ping       - ICMP ping a host (N packets).
    traceroute - trace route to a host.
    dns        - resolve hostname to IP addresses.
    tcp        - check TCP connectivity to host:port.
    http       - HTTP HEAD/GET to a URL, return status and headers.
    whois      - basic WHOIS query via whois.iana.org TCP port 43.
}

interface

uses
  uMakerAi.MCPServer.Core,
  System.SysUtils,
  System.JSON,
  System.Classes,
  System.Net.HttpClient,
  System.Net.URLClient,
  IdTCPClient,
  IdDNSResolver,
  IdGlobal;

type

  TNetworkParams = class
  private
    FOperation: string;
    FHost:      string;
    FPort:      Integer;
    FUrl:       string;
    FCount:     Integer;
    FTimeout:   Integer;
    FMethod:    string;
  public
    constructor Create;

    [AiMCPSchemaDescription('Operation: ping, traceroute, dns, tcp, http, whois')]
    property Operation: string  read FOperation write FOperation;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Hostname or IP address (used by ping, traceroute, dns, tcp, whois)')]
    property Host:      string  read FHost      write FHost;

    [AiMCPOptional]
    [AiMCPSchemaDescription('TCP port (used by tcp operation; default 80)')]
    property Port:      Integer read FPort      write FPort;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Full URL (used by http operation)')]
    property Url:       string  read FUrl       write FUrl;

    [AiMCPOptional]
    [AiMCPSchemaDescription('ping: number of packets (default 4)')]
    property Count:     Integer read FCount     write FCount;

    [AiMCPOptional]
    [AiMCPSchemaDescription('tcp/http: timeout in milliseconds (default 5000)')]
    property Timeout:   Integer read FTimeout   write FTimeout;

    [AiMCPOptional]
    [AiMCPSchemaDescription('http: HTTP method HEAD or GET (default HEAD)')]
    property Method:    string  read FMethod    write FMethod;
  end;

  TNetworkTool = class(TAiMCPToolBase<TNetworkParams>)
  private
    function RunCommand(const Cmd: string): string;
    function DoPing(const P: TNetworkParams): TJSONObject;
    function DoTraceroute(const P: TNetworkParams): TJSONObject;
    function DoDns(const P: TNetworkParams): TJSONObject;
    function DoTcp(const P: TNetworkParams): TJSONObject;
    function DoHttp(const P: TNetworkParams): TJSONObject;
    function DoWhois(const P: TNetworkParams): TJSONObject;
  protected
    function ExecuteWithParams(const AParams: TNetworkParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

procedure RegisterTools(AServer: TAiMCPServer);

implementation

uses
  System.StrUtils,
  Winapi.Windows;

{ TNetworkParams }

constructor TNetworkParams.Create;
begin
  inherited;
  FPort    := 80;
  FCount   := 4;
  FTimeout := 5000;
  FMethod  := 'HEAD';
end;

{ TNetworkTool }

function TNetworkTool.RunCommand(const Cmd: string): string;
var
  SI:         TStartupInfo;
  PI:         TProcessInformation;
  SA:         TSecurityAttributes;
  hRead, hWrite: THandle;
  Buffer:     array[0..4095] of AnsiChar;
  BytesRead:  DWORD;
  Lines:      TStringList;
begin
  Result := '';
  SA.nLength              := SizeOf(SA);
  SA.bInheritHandle       := True;
  SA.lpSecurityDescriptor := nil;

  if not CreatePipe(hRead, hWrite, @SA, 0) then
    raise Exception.Create('CreatePipe failed');
  try
    SetHandleInformation(hRead, HANDLE_FLAG_INHERIT, 0);

    FillChar(SI, SizeOf(SI), 0);
    SI.cb          := SizeOf(SI);
    SI.dwFlags     := STARTF_USESTDHANDLES or STARTF_USESHOWWINDOW;
    SI.hStdOutput  := hWrite;
    SI.hStdError   := hWrite;
    SI.wShowWindow := SW_HIDE;

    var CmdLine := 'cmd.exe /C ' + Cmd;
    var CmdBuf  := CmdLine;

    FillChar(PI, SizeOf(PI), 0);
    if not CreateProcess(nil, PChar(CmdBuf), nil, nil, True,
      CREATE_NO_WINDOW, nil, nil, SI, PI) then
    begin
      CloseHandle(hRead);
      CloseHandle(hWrite);
      raise Exception.Create('CreateProcess failed: ' + Cmd);
    end;

    CloseHandle(hWrite);
    hWrite := 0;

    Lines := TStringList.Create;
    try
      while ReadFile(hRead, Buffer, SizeOf(Buffer) - 1, BytesRead, nil) and (BytesRead > 0) do
      begin
        Buffer[BytesRead] := #0;
        Lines.Add(string(AnsiString(Buffer)));
      end;
      WaitForSingleObject(PI.hProcess, INFINITE);
      Result := Lines.Text;
    finally
      Lines.Free;
    end;

    CloseHandle(PI.hProcess);
    CloseHandle(PI.hThread);
  finally
    CloseHandle(hRead);
    if hWrite <> 0 then CloseHandle(hWrite);
  end;
end;

function TNetworkTool.DoPing(const P: TNetworkParams): TJSONObject;
var
  Output:   string;
  Lines:    TStringList;
  Stats:    TJSONObject;
  Packets:  TJSONArray;
  Line:     string;
  Cnt:      Integer;
begin
  if P.Host = '' then raise Exception.Create('"host" is required for ping');

  Cnt := P.Count;
  if Cnt <= 0 then Cnt := 4;
  if Cnt > 20 then Cnt := 20;

  Output := RunCommand(Format('ping -n %d %s', [Cnt, P.Host]));

  Lines   := TStringList.Create;
  Packets := TJSONArray.Create;
  Stats   := TJSONObject.Create;
  try
    Lines.Text := Output;
    for Line in Lines do
    begin
      var L := Trim(Line);
      if L.Contains('bytes from') or L.Contains('Reply from') or
         L.Contains('tiempo') or L.Contains('time') then
        Packets.Add(L)
      else if L.Contains('Packets') or L.Contains('Paquetes') or
              L.Contains('Lost') or L.Contains('perdidos') then
        Stats.AddPair('summary', L)
      else if L.Contains('Average') or L.Contains('Promedio') or
              L.Contains('Minimum') or L.Contains('Maximum') then
        Stats.AddPair('latency', L);
    end;
  finally
    Lines.Free;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('host',    P.Host);
  Result.AddPair('count',   TJSONNumber.Create(Cnt));
  Result.AddPair('replies', Packets);
  Result.AddPair('stats',   Stats);
  Result.AddPair('raw',     Output.Trim);
  Result.AddPair('ok',      TJSONTrue.Create);
end;

function TNetworkTool.DoTraceroute(const P: TNetworkParams): TJSONObject;
var
  Output: string;
  Lines:  TStringList;
  Hops:   TJSONArray;
  Line:   string;
  i:      Integer;
begin
  if P.Host = '' then raise Exception.Create('"host" is required for traceroute');

  Output := RunCommand('tracert -d -h 30 ' + P.Host);

  Lines := TStringList.Create;
  Hops  := TJSONArray.Create;
  try
    Lines.Text := Output;
    for i := 0 to Lines.Count - 1 do
    begin
      Line := Trim(Lines[i]);
      if (Length(Line) > 0) and (Line[1] >= '1') and (Line[1] <= '9') then
        Hops.Add(Line);
    end;
  finally
    Lines.Free;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('host', P.Host);
  Result.AddPair('hops', Hops);
  Result.AddPair('raw',  Output.Trim);
  Result.AddPair('ok',   TJSONTrue.Create);
end;

function TNetworkTool.DoDns(const P: TNetworkParams): TJSONObject;
var
  Addresses: TJSONArray;
  Output:    string;
  Lines:     TStringList;
  Line:      string;
begin
  if P.Host = '' then raise Exception.Create('"host" is required for dns');

  Addresses := TJSONArray.Create;

  Output := RunCommand('nslookup ' + P.Host);
  Lines  := TStringList.Create;
  try
    Lines.Text := Output;
    var InAnswerSection := False;
    for Line in Lines do
    begin
      var L := Trim(Line);
      if L.StartsWith('Name:') then
        InAnswerSection := True
      else if InAnswerSection and (L.StartsWith('Address') or L.StartsWith('Addresses')) then
      begin
        var Colon := Pos(':', L);
        if Colon > 0 then
          Addresses.Add(Trim(L.Substring(Colon)));
      end;
    end;
  finally
    Lines.Free;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('host',      P.Host);
  Result.AddPair('addresses', Addresses);
  Result.AddPair('raw',       Output.Trim);
  Result.AddPair('ok',        TJSONTrue.Create);
end;

function TNetworkTool.DoTcp(const P: TNetworkParams): TJSONObject;
var
  Client:    TIdTCPClient;
  Port:      Integer;
  Connected: Boolean;
  ErrMsg:    string;
  Ms:        Int64;
  T0:        TDateTime;
begin
  if P.Host = '' then raise Exception.Create('"host" is required for tcp');

  Port := P.Port;
  if Port <= 0 then Port := 80;

  Connected := False;
  ErrMsg    := '';
  Ms        := 0;

  Client := TIdTCPClient.Create(nil);
  try
    Client.Host            := P.Host;
    Client.Port            := Port;
    Client.ConnectTimeout  := P.Timeout;
    Client.ReadTimeout     := P.Timeout;
    T0 := Now;
    try
      Client.Connect;
      Connected := True;
      Ms := Round((Now - T0) * 86400000);
      Client.Disconnect;
    except
      on E: Exception do
      begin
        Ms     := Round((Now - T0) * 86400000);
        ErrMsg := E.Message;
      end;
    end;
  finally
    Client.Free;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('host',      P.Host);
  Result.AddPair('port',      TJSONNumber.Create(Port));
  Result.AddPair('connected', TJSONBool.Create(Connected));
  Result.AddPair('ms',        TJSONNumber.Create(Ms));
  if ErrMsg <> '' then
    Result.AddPair('error', ErrMsg);
  Result.AddPair('ok', TJSONTrue.Create);
end;

function TNetworkTool.DoHttp(const P: TNetworkParams): TJSONObject;
var
  Client:   THTTPClient;
  Resp:     IHTTPResponse;
  Headers:  TJSONObject;
  Method:   string;
  Ms:       Int64;
  T0:       TDateTime;
begin
  if P.Url = '' then raise Exception.Create('"url" is required for http');

  Method := UpperCase(Trim(P.Method));
  if Method = '' then Method := 'HEAD';

  Client  := THTTPClient.Create;
  Headers := TJSONObject.Create;
  try
    Client.ConnectionTimeout  := P.Timeout;
    Client.ResponseTimeout    := P.Timeout;
    Client.HandleRedirects    := True;
    Client.MaxRedirects       := 5;

    T0 := Now;
    if Method = 'GET' then
      Resp := Client.Get(P.Url)
    else
      Resp := Client.Head(P.Url);
    Ms := Round((Now - T0) * 86400000);

    for var H in Resp.Headers do
      Headers.AddPair(H.Name, H.Value);

    Result := TJSONObject.Create;
    Result.AddPair('url',         P.Url);
    Result.AddPair('method',      Method);
    Result.AddPair('status_code', TJSONNumber.Create(Resp.StatusCode));
    Result.AddPair('status_text', Resp.StatusText);
    Result.AddPair('ms',          TJSONNumber.Create(Ms));
    Result.AddPair('headers',     Headers);
    if Method = 'GET' then
      Result.AddPair('body_preview', Resp.ContentAsString.Substring(0, 500));
    Result.AddPair('ok', TJSONTrue.Create);
  finally
    Client.Free;
  end;
end;

function TNetworkTool.DoWhois(const P: TNetworkParams): TJSONObject;
var
  Client:   TIdTCPClient;
  Response: string;
begin
  if P.Host = '' then raise Exception.Create('"host" is required for whois');

  Client := TIdTCPClient.Create(nil);
  try
    Client.Host           := 'whois.iana.org';
    Client.Port           := 43;
    Client.ConnectTimeout := P.Timeout;
    Client.ReadTimeout    := P.Timeout * 2;
    Client.Connect;
    try
      Client.IOHandler.WriteLn(P.Host);
      Response := '';
      while not Client.IOHandler.InputBufferIsEmpty or Client.Connected do
      begin
        try
          Response := Response + Client.IOHandler.ReadLn(IndyTextEncoding_UTF8);
          Response := Response + #10;
        except
          Break;
        end;
      end;
    finally
      Client.Disconnect;
    end;
  finally
    Client.Free;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('host',   P.Host);
  Result.AddPair('whois',  Response.Trim);
  Result.AddPair('server', 'whois.iana.org');
  Result.AddPair('ok',     TJSONTrue.Create);
end;

function TNetworkTool.ExecuteWithParams(const AParams: TNetworkParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op: string;
  R:  TJSONObject;
begin
  try
    Op := LowerCase(Trim(AParams.Operation));
    if Op = '' then raise Exception.Create('"operation" is required');

    if      Op = 'ping'       then R := DoPing(AParams)
    else if Op = 'traceroute' then R := DoTraceroute(AParams)
    else if Op = 'dns'        then R := DoDns(AParams)
    else if Op = 'tcp'        then R := DoTcp(AParams)
    else if Op = 'http'       then R := DoHttp(AParams)
    else if Op = 'whois'      then R := DoWhois(AParams)
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

constructor TNetworkTool.Create;
begin
  inherited;
  FName        := 'mcp-network';
  FDescription :=
    'Network diagnostics. ' +
    'Operations: ' +
    'ping (ICMP ping host N times; params: host, count), ' +
    'traceroute (trace route to host; params: host), ' +
    'dns (resolve hostname to IPs via nslookup; params: host), ' +
    'tcp (check TCP port connectivity; params: host, port, timeout), ' +
    'http (HTTP HEAD or GET request; params: url, method, timeout), ' +
    'whois (WHOIS lookup via whois.iana.org; params: host).';
end;

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-network',
    function: IAiMCPTool
    begin
      Result := TNetworkTool.Create;
    end);
  WriteLn(ErrOutput, '[mcp-network] registered');
end;

end.
