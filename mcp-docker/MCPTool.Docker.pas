unit MCPTool.Docker;

{
  MCPTool.Docker  ·  mcp-docker

  Docker Engine REST API client. Connects to the Docker daemon via HTTP.

  Operations:
    info              - get Docker host info
    list_containers   - list containers (all or running only)
    inspect_container - get detailed container info
    start             - start a stopped container
    stop              - stop a running container
    restart           - restart a container
    remove_container  - remove a container
    logs              - get container logs
    list_images       - list local images
    pull              - pull an image from a registry
    remove_image      - remove a local image
    exec              - execute a command in a running container (create + start exec)
}

interface

uses
  uMakerAi.MCPServer.Core,
  System.SysUtils,
  System.JSON,
  System.Classes,
  System.Net.HttpClient,
  System.Net.URLClient,
  System.NetEncoding;

type

  TDockerParams = class
  private
    FOperation:   string;
    FHost:        string;
    FContainerId: string;
    FImage:       string;
    FAll:         Boolean;
    FTail:        Integer;
    FCommand:     string;
    FForce:       Boolean;
  public
    constructor Create;

    [AiMCPSchemaDescription('Operation: info, list_containers, inspect_container, start, stop, restart, remove_container, logs, list_images, pull, remove_image, exec')]
    property Operation:   string  read FOperation   write FOperation;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Docker API host URL (default: http://localhost:2375)')]
    property Host:        string  read FHost        write FHost;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Container ID or name')]
    property ContainerId: string  read FContainerId write FContainerId;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Image name (for pull, remove_image)')]
    property Image:       string  read FImage       write FImage;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Include stopped containers in list (default: false)')]
    property All:         Boolean read FAll         write FAll;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Number of log lines to return (default: 100)')]
    property Tail:        Integer read FTail        write FTail;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Command to execute (for exec), e.g. "ls -la"')]
    property Command:     string  read FCommand     write FCommand;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Force remove even if running (for remove_container/remove_image)')]
    property Force:       Boolean read FForce       write FForce;
  end;

  TDockerTool = class(TAiMCPToolBase<TDockerParams>)
  private
    function GetHost(const P: TDockerParams): string;
    function HttpGet(const URL: string): string;
    function HttpPost(const URL, Body: string): string;
    function HttpDelete(const URL: string): string;
    function DoInfo(const P: TDockerParams): TJSONObject;
    function DoListContainers(const P: TDockerParams): TJSONObject;
    function DoInspectContainer(const P: TDockerParams): TJSONObject;
    function DoStart(const P: TDockerParams): TJSONObject;
    function DoStop(const P: TDockerParams): TJSONObject;
    function DoRestart(const P: TDockerParams): TJSONObject;
    function DoRemoveContainer(const P: TDockerParams): TJSONObject;
    function DoLogs(const P: TDockerParams): TJSONObject;
    function DoListImages(const P: TDockerParams): TJSONObject;
    function DoPull(const P: TDockerParams): TJSONObject;
    function DoRemoveImage(const P: TDockerParams): TJSONObject;
    function DoExec(const P: TDockerParams): TJSONObject;
  protected
    function ExecuteWithParams(const AParams: TDockerParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

procedure RegisterTools(AServer: TAiMCPServer);

implementation

{ TDockerParams }

constructor TDockerParams.Create;
begin
  inherited;
  FHost := 'http://localhost:2375';
  FTail := 100;
end;

{ TDockerTool }

function TDockerTool.GetHost(const P: TDockerParams): string;
begin
  Result := Trim(P.Host);
  if Result = '' then Result := 'http://localhost:2375';
  if Result.EndsWith('/') then
    Result := Result.Substring(0, Length(Result) - 1);
end;

function TDockerTool.HttpGet(const URL: string): string;
var
  HTTP: THTTPClient;
  Resp: IHTTPResponse;
begin
  HTTP := THTTPClient.Create;
  try
    HTTP.ConnectionTimeout := 5000;
    HTTP.ResponseTimeout   := 30000;
    Resp := HTTP.Get(URL);
    Result := Resp.ContentAsString;
    if Resp.StatusCode >= 400 then
      raise Exception.CreateFmt('Docker API HTTP %d: %s',
        [Resp.StatusCode, Result.Substring(0, 300)]);
  finally
    HTTP.Free;
  end;
end;

function TDockerTool.HttpPost(const URL, Body: string): string;
var
  HTTP:    THTTPClient;
  Resp:    IHTTPResponse;
  Stream:  TStringStream;
begin
  HTTP   := THTTPClient.Create;
  Stream := TStringStream.Create(Body, TEncoding.UTF8);
  try
    HTTP.ConnectionTimeout := 5000;
    HTTP.ResponseTimeout   := 60000;
    Resp := HTTP.Post(URL, Stream, nil,
      [TNameValuePair.Create('Content-Type', 'application/json')]);
    Result := Resp.ContentAsString;
    if (Resp.StatusCode >= 400) then
      raise Exception.CreateFmt('Docker API HTTP %d: %s',
        [Resp.StatusCode, Result.Substring(0, 300)]);
  finally
    Stream.Free;
    HTTP.Free;
  end;
end;

function TDockerTool.HttpDelete(const URL: string): string;
var
  HTTP: THTTPClient;
  Resp: IHTTPResponse;
begin
  HTTP := THTTPClient.Create;
  try
    HTTP.ConnectionTimeout := 5000;
    HTTP.ResponseTimeout   := 30000;
    Resp := HTTP.Delete(URL);
    Result := Resp.ContentAsString;
    if Resp.StatusCode >= 400 then
      raise Exception.CreateFmt('Docker API HTTP %d: %s',
        [Resp.StatusCode, Result.Substring(0, 300)]);
  finally
    HTTP.Free;
  end;
end;

function TDockerTool.DoInfo(const P: TDockerParams): TJSONObject;
var
  Host:    string;
  RespStr: string;
  Parsed:  TJSONValue;
  J:       TJSONObject;
begin
  Host    := GetHost(P);
  RespStr := HttpGet(Host + '/info');
  Parsed  := TJSONObject.ParseJSONValue(RespStr);
  try
    if not (Parsed is TJSONObject) then
      raise Exception.Create('Invalid response from Docker daemon');
    J := Parsed as TJSONObject;

    Result := TJSONObject.Create;
    Result.AddPair('name',        J.GetValue<string>('Name', ''));
    Result.AddPair('server_version', J.GetValue<string>('ServerVersion', ''));
    Result.AddPair('containers',  TJSONNumber.Create(J.GetValue<Integer>('Containers', 0)));
    Result.AddPair('running',     TJSONNumber.Create(J.GetValue<Integer>('ContainersRunning', 0)));
    Result.AddPair('paused',      TJSONNumber.Create(J.GetValue<Integer>('ContainersPaused', 0)));
    Result.AddPair('stopped',     TJSONNumber.Create(J.GetValue<Integer>('ContainersStopped', 0)));
    Result.AddPair('images',      TJSONNumber.Create(J.GetValue<Integer>('Images', 0)));
    Result.AddPair('os',          J.GetValue<string>('OperatingSystem', ''));
    Result.AddPair('arch',        J.GetValue<string>('Architecture', ''));
    Result.AddPair('cpus',        TJSONNumber.Create(J.GetValue<Integer>('NCPU', 0)));
    Result.AddPair('memory_mb',   TJSONNumber.Create(J.GetValue<Int64>('MemTotal', 0) div (1024 * 1024)));
    Result.AddPair('ok', TJSONTrue.Create);
  finally
    Parsed.Free;
  end;
end;

function TDockerTool.DoListContainers(const P: TDockerParams): TJSONObject;
var
  Host:    string;
  URL:     string;
  RespStr: string;
  Parsed:  TJSONValue;
  Arr:     TJSONArray;
  Out:     TJSONArray;
  i:       Integer;
begin
  Host := GetHost(P);
  URL  := Host + '/containers/json';
  if P.All then URL := URL + '?all=true';

  RespStr := HttpGet(URL);
  Parsed  := TJSONObject.ParseJSONValue(RespStr);
  try
    Out := TJSONArray.Create;
    if Parsed is TJSONArray then
    begin
      Arr := Parsed as TJSONArray;
      for i := 0 to Arr.Count - 1 do
      begin
        var C    := Arr.Items[i] as TJSONObject;
        var Item := TJSONObject.Create;
        Item.AddPair('id',     C.GetValue<string>('Id', '').Substring(0, 12));
        Item.AddPair('image',  C.GetValue<string>('Image', ''));
        Item.AddPair('status', C.GetValue<string>('Status', ''));
        Item.AddPair('state',  C.GetValue<string>('State', ''));
        var Names: TJSONArray := nil;
        C.TryGetValue<TJSONArray>('Names', Names);
        if (Names <> nil) and (Names.Count > 0) then
          Item.AddPair('name', Names.Items[0].Value.TrimLeft(['/']))
        else
          Item.AddPair('name', '');
        Out.AddElement(Item);
      end;
    end;

    Result := TJSONObject.Create;
    Result.AddPair('containers', Out);
    Result.AddPair('count',      TJSONNumber.Create(Out.Count));
    Result.AddPair('ok',         TJSONTrue.Create);
  finally
    Parsed.Free;
  end;
end;

function TDockerTool.DoInspectContainer(const P: TDockerParams): TJSONObject;
var
  Host:    string;
  RespStr: string;
  Parsed:  TJSONValue;
  J:       TJSONObject;
begin
  if P.ContainerId = '' then raise Exception.Create('"container_id" required for inspect_container');
  Host    := GetHost(P);
  RespStr := HttpGet(Host + '/containers/' + P.ContainerId + '/json');
  Parsed  := TJSONObject.ParseJSONValue(RespStr);
  try
    if not (Parsed is TJSONObject) then raise Exception.Create('Invalid response');
    J := Parsed as TJSONObject;
    Result := TJSONObject.Create;
    Result.AddPair('id',      J.GetValue<string>('Id', '').Substring(0, 12));
    Result.AddPair('name',    J.GetValue<string>('Name', '').TrimLeft(['/']));
    Result.AddPair('image',   J.GetValue<string>('Image', ''));
    var State: TJSONObject := nil;
    if J.TryGetValue<TJSONObject>('State', State) then
    begin
      Result.AddPair('state',    State.GetValue<string>('Status', ''));
      Result.AddPair('running',  TJSONBool.Create(State.GetValue<Boolean>('Running', False)));
      Result.AddPair('pid',      TJSONNumber.Create(State.GetValue<Integer>('Pid', 0)));
      Result.AddPair('started',  State.GetValue<string>('StartedAt', ''));
    end;
    Result.AddPair('ok', TJSONTrue.Create);
  finally
    Parsed.Free;
  end;
end;

function TDockerTool.DoStart(const P: TDockerParams): TJSONObject;
var
  Host: string;
begin
  if P.ContainerId = '' then raise Exception.Create('"container_id" required for start');
  Host := GetHost(P);
  HttpPost(Host + '/containers/' + P.ContainerId + '/start', '');
  Result := TJSONObject.Create;
  Result.AddPair('container_id', P.ContainerId);
  Result.AddPair('action', 'start');
  Result.AddPair('ok', TJSONTrue.Create);
end;

function TDockerTool.DoStop(const P: TDockerParams): TJSONObject;
var
  Host: string;
begin
  if P.ContainerId = '' then raise Exception.Create('"container_id" required for stop');
  Host := GetHost(P);
  HttpPost(Host + '/containers/' + P.ContainerId + '/stop', '');
  Result := TJSONObject.Create;
  Result.AddPair('container_id', P.ContainerId);
  Result.AddPair('action', 'stop');
  Result.AddPair('ok', TJSONTrue.Create);
end;

function TDockerTool.DoRestart(const P: TDockerParams): TJSONObject;
var
  Host: string;
begin
  if P.ContainerId = '' then raise Exception.Create('"container_id" required for restart');
  Host := GetHost(P);
  HttpPost(Host + '/containers/' + P.ContainerId + '/restart', '');
  Result := TJSONObject.Create;
  Result.AddPair('container_id', P.ContainerId);
  Result.AddPair('action', 'restart');
  Result.AddPair('ok', TJSONTrue.Create);
end;

function TDockerTool.DoRemoveContainer(const P: TDockerParams): TJSONObject;
var
  Host: string;
  URL:  string;
begin
  if P.ContainerId = '' then raise Exception.Create('"container_id" required for remove_container');
  Host := GetHost(P);
  URL  := Host + '/containers/' + P.ContainerId;
  if P.Force then URL := URL + '?force=true';
  HttpDelete(URL);
  Result := TJSONObject.Create;
  Result.AddPair('container_id', P.ContainerId);
  Result.AddPair('action', 'removed');
  Result.AddPair('ok', TJSONTrue.Create);
end;

function TDockerTool.DoLogs(const P: TDockerParams): TJSONObject;
var
  Host:    string;
  Tail:    Integer;
  URL:     string;
  RespStr: string;
begin
  if P.ContainerId = '' then raise Exception.Create('"container_id" required for logs');
  Host := GetHost(P);
  Tail := P.Tail;
  if Tail <= 0 then Tail := 100;
  URL     := Format('%s/containers/%s/logs?stdout=true&stderr=true&tail=%d',
    [Host, P.ContainerId, Tail]);
  RespStr := HttpGet(URL);

  // Docker log streams have 8-byte headers per line; strip non-printable prefixes
  var SL := TStringList.Create;
  try
    SL.Text := RespStr;
    var CleanSB := TStringBuilder.Create;
    try
      for var Line in SL do
      begin
        var L := Line;
        // Strip leading control chars (Docker stream header bytes)
        while (Length(L) > 0) and (Ord(L[1]) < 32) do
          L := L.Substring(1);
        CleanSB.AppendLine(L);
      end;
      RespStr := CleanSB.ToString.TrimRight;
    finally
      CleanSB.Free;
    end;
  finally
    SL.Free;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('container_id', P.ContainerId);
  Result.AddPair('tail',         TJSONNumber.Create(Tail));
  Result.AddPair('logs',         RespStr);
  Result.AddPair('ok',           TJSONTrue.Create);
end;

function TDockerTool.DoListImages(const P: TDockerParams): TJSONObject;
var
  Host:    string;
  RespStr: string;
  Parsed:  TJSONValue;
  Arr:     TJSONArray;
  Out:     TJSONArray;
  i:       Integer;
begin
  Host    := GetHost(P);
  RespStr := HttpGet(Host + '/images/json');
  Parsed  := TJSONObject.ParseJSONValue(RespStr);
  try
    Out := TJSONArray.Create;
    if Parsed is TJSONArray then
    begin
      Arr := Parsed as TJSONArray;
      for i := 0 to Arr.Count - 1 do
      begin
        var Img  := Arr.Items[i] as TJSONObject;
        var Item := TJSONObject.Create;
        Item.AddPair('id',      Img.GetValue<string>('Id', '').Substring(7, 12));
        Item.AddPair('size_mb', TJSONNumber.Create(Img.GetValue<Int64>('Size', 0) div (1024*1024)));
        var Tags: TJSONArray := nil;
        Img.TryGetValue<TJSONArray>('RepoTags', Tags);
        if (Tags <> nil) and (Tags.Count > 0) then
          Item.AddPair('tag', Tags.Items[0].Value)
        else
          Item.AddPair('tag', '<none>');
        Out.AddElement(Item);
      end;
    end;

    Result := TJSONObject.Create;
    Result.AddPair('images', Out);
    Result.AddPair('count',  TJSONNumber.Create(Out.Count));
    Result.AddPair('ok',     TJSONTrue.Create);
  finally
    Parsed.Free;
  end;
end;

function TDockerTool.DoPull(const P: TDockerParams): TJSONObject;
var
  Host:    string;
  RespStr: string;
begin
  if P.Image = '' then raise Exception.Create('"image" required for pull');
  Host    := GetHost(P);
  RespStr := HttpPost(Host + '/images/create?fromImage=' +
    TNetEncoding.URL.EncodeQuery(P.Image), '');

  Result := TJSONObject.Create;
  Result.AddPair('image',  P.Image);
  Result.AddPair('output', RespStr.Substring(0, 500));
  Result.AddPair('ok',     TJSONTrue.Create);
end;

function TDockerTool.DoRemoveImage(const P: TDockerParams): TJSONObject;
var
  Host: string;
  URL:  string;
begin
  if P.Image = '' then raise Exception.Create('"image" required for remove_image');
  Host := GetHost(P);
  URL  := Host + '/images/' + TNetEncoding.URL.EncodeQuery(P.Image);
  if P.Force then URL := URL + '?force=true';
  HttpDelete(URL);

  Result := TJSONObject.Create;
  Result.AddPair('image',  P.Image);
  Result.AddPair('action', 'removed');
  Result.AddPair('ok',     TJSONTrue.Create);
end;

function TDockerTool.DoExec(const P: TDockerParams): TJSONObject;
var
  Host:    string;
  Body:    string;
  RespStr: string;
  Parsed:  TJSONValue;
  ExecId:  string;
begin
  if P.ContainerId = '' then raise Exception.Create('"container_id" required for exec');
  if P.Command     = '' then raise Exception.Create('"command" required for exec');
  Host := GetHost(P);

  // Build command array from shell-split
  var Parts := P.Command.Split([' '], 2);
  var CmdArr := TJSONArray.Create;
  CmdArr.Add('/bin/sh');
  CmdArr.Add('-c');
  CmdArr.Add(P.Command);

  var ExecCreate := TJSONObject.Create;
  ExecCreate.AddPair('AttachStdout', TJSONTrue.Create);
  ExecCreate.AddPair('AttachStderr', TJSONTrue.Create);
  ExecCreate.AddPair('Cmd', CmdArr);

  Body    := ExecCreate.ToJSON;
  ExecCreate.Free;

  RespStr := HttpPost(Host + '/containers/' + P.ContainerId + '/exec', Body);
  Parsed  := TJSONObject.ParseJSONValue(RespStr);
  ExecId  := '';
  try
    if Parsed is TJSONObject then
      ExecId := (Parsed as TJSONObject).GetValue<string>('Id', '');
  finally
    Parsed.Free;
  end;

  if ExecId = '' then
    raise Exception.Create('Failed to create exec instance');

  // Start the exec
  var StartBody := '{"Detach":false,"Tty":false}';
  RespStr := HttpPost(Host + '/exec/' + ExecId + '/start', StartBody);

  Result := TJSONObject.Create;
  Result.AddPair('container_id', P.ContainerId);
  Result.AddPair('command',      P.Command);
  Result.AddPair('output',       RespStr.Substring(0, 2000));
  Result.AddPair('ok',           TJSONTrue.Create);
end;

function TDockerTool.ExecuteWithParams(const AParams: TDockerParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op: string;
  R:  TJSONObject;
begin
  try
    Op := LowerCase(Trim(AParams.Operation));
    if Op = '' then raise Exception.Create('"operation" is required');

    if      Op = 'info'              then R := DoInfo(AParams)
    else if Op = 'list_containers'   then R := DoListContainers(AParams)
    else if Op = 'inspect_container' then R := DoInspectContainer(AParams)
    else if Op = 'start'             then R := DoStart(AParams)
    else if Op = 'stop'              then R := DoStop(AParams)
    else if Op = 'restart'           then R := DoRestart(AParams)
    else if Op = 'remove_container'  then R := DoRemoveContainer(AParams)
    else if Op = 'logs'              then R := DoLogs(AParams)
    else if Op = 'list_images'       then R := DoListImages(AParams)
    else if Op = 'pull'              then R := DoPull(AParams)
    else if Op = 'remove_image'      then R := DoRemoveImage(AParams)
    else if Op = 'exec'              then R := DoExec(AParams)
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

constructor TDockerTool.Create;
begin
  inherited;
  FName        := 'mcp-docker';
  FDescription :=
    'Docker Engine management via REST API. Requires Docker daemon with TCP enabled. ' +
    'Operations: ' +
    'info (host info), ' +
    'list_containers (list containers; param: all?), ' +
    'inspect_container (container details; param: container_id), ' +
    'start/stop/restart (container lifecycle; param: container_id), ' +
    'remove_container (param: container_id, force?), ' +
    'logs (get logs; params: container_id, tail?), ' +
    'list_images (list local images), ' +
    'pull (pull image; param: image), ' +
    'remove_image (param: image, force?), ' +
    'exec (run command; params: container_id, command). ' +
    'Default host: http://localhost:2375.';
end;

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-docker',
    function: IAiMCPTool
    begin
      Result := TDockerTool.Create;
    end);
  WriteLn(ErrOutput, '[MCPService]   + mcp-docker');
end;

end.
