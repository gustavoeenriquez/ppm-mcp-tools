unit MCPTool.SmartThings;

{
  MCPTool.SmartThings
  MCP tool: mcp-smartthings

  Samsung SmartThings cloud API client (https://api.smartthings.com/v1).
  Control switches/dimmers, read device status and power metering,
  execute scenes, check device health.

  Token: pass "token" param or set SMARTTHINGS_TOKEN env var (PAT or OAuth).
  Server mode (http/sse alojado en MKAIServer, MCPTool.Credential): el token
  OAuth de QUIEN llama llega en Authorization ("Bearer <token>") en cada
  peticion; se ignora el "token" del modelo y SMARTTHINGS_TOKEN.
  Location restriction: if SMARTTHINGS_LOCATION_ID env var is set, every
  operation is restricted to that location. Listing filters by it and any
  device/scene command first verifies ownership; anything outside the
  allowed location is rejected.

  Operations:
    locations - list locations visible to the token
    devices   - list devices (label, id, room, capabilities, online state)
    status    - read main-component attribute values of a device
    health    - device health (ONLINE/OFFLINE + last change)
    on        - switch a device on
    off       - switch a device off
    level     - set dimmer level 0..100 (switchLevel.setLevel)
    command   - generic command: capability + command + optional JSON args
    scenes    - list scenes
    scene     - execute a scene by sceneId

  IMPORTANT: SmartThings answers ACCEPTED for commands even when the target
  device is OFFLINE. Callers should verify with "health" or re-read "status".
}

interface

uses
  uMakerAi.MCPServer.Core,
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.Net.HttpClient,
  System.Net.HttpClientComponent,
  System.Net.URLClient;

type

  TSmartThingsParams = class
  private
    FOperation:  string;
    FToken:      string;
    FDeviceId:   string;
    FSceneId:    string;
    FLocationId: string;
    FLevel:      Integer;
    FCapability: string;
    FCommand:    string;
    FArguments:  string;
    FFull:       Boolean;
  public
    [AiMCPSchemaDescription(
      'Operation to perform. Required params per operation: ' +
      'locations=none; devices=none (locationId optional); ' +
      'status=deviceId (full optional); health=deviceId; ' +
      'on=deviceId; off=deviceId; level=deviceId+level; ' +
      'command=deviceId+capability+command (arguments optional); ' +
      'scenes=none; scene=sceneId')]
    property Operation: string read FOperation write FOperation;

    [AiMCPOptional]
    [AiMCPSchemaDescription(
      'SmartThings API token (PAT or OAuth access token). ' +
      'OPTIONAL: omit to use SMARTTHINGS_TOKEN env var instead.')]
    property Token: string read FToken write FToken;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Target device ID (required for status, health, on, off, level, command)')]
    property DeviceId: string read FDeviceId write FDeviceId;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Scene ID (required for scene operation)')]
    property SceneId: string read FSceneId write FSceneId;

    [AiMCPOptional]
    [AiMCPSchemaDescription(
      'Location ID filter for devices/scenes listing. ' +
      'Ignored when SMARTTHINGS_LOCATION_ID env var enforces a location.')]
    property LocationId: string read FLocationId write FLocationId;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Dimmer level 0..100 (required for level operation)')]
    property Level: Integer read FLevel write FLevel;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Capability id for generic command, e.g. switch, switchLevel, audioVolume')]
    property Capability: string read FCapability write FCapability;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Command name for generic command, e.g. on, off, setLevel, setVolume')]
    property Command: string read FCommand write FCommand;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Command arguments as JSON array string, e.g. "[50]" for setLevel. Default: no arguments.')]
    property Arguments: string read FArguments write FArguments;

    [AiMCPOptional]
    [AiMCPSchemaDescription('status only: true returns the full raw main-component JSON instead of the compact summary')]
    property Full: Boolean read FFull write FFull;
  end;

  TSmartThingsTool = class(TAiMCPToolBase<TSmartThingsParams>)
  private
    function ResolveToken(const Param: string; const AuthContext: TAiAuthContext): string;
    function AllowedLocation: string;
    function ApiRequest(const AToken, AMethod, APath, ABody: string): string;
    function ApiGetJSON(const AToken, APath: string): TJSONValue;
    procedure EnsureDeviceAllowed(const AToken, ADeviceId: string);
    function SendCommand(const AToken, ADeviceId, ACapability, ACommand,
      AArguments: string): TJSONObject;
    function BuildText(const AJson: TJSONValue): TJSONObject;
  protected
    function ExecuteWithParams(const AParams: TSmartThingsParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

procedure RegisterTools(AServer: TAiMCPServer);

implementation

uses
  MCPTool.Credential;

const
  API_BASE = 'https://api.smartthings.com/v1';

// ---- Helpers ---------------------------------------------------------------

function TSmartThingsTool.ResolveToken(const Param: string;
  const AuthContext: TAiAuthContext): string;
begin
  if ServerMode then
  begin
    Result := Trim(AuthContext.UserID);
    if Result.StartsWith('Bearer ', True) then
      Result := Trim(Copy(Result, 8, MaxInt));
    if Result = '' then
      raise Exception.Create('No hay una cuenta de SmartThings conectada (Conexiones).');
    Exit;
  end;
  Result := Trim(Param);
  if Result = '' then
    Result := GetEnvironmentVariable('SMARTTHINGS_TOKEN');
  if Result = '' then
    raise Exception.Create(
      'API token required: pass "token" or set SMARTTHINGS_TOKEN env var');
end;

function TSmartThingsTool.AllowedLocation: string;
begin
  Result := Trim(GetEnvironmentVariable('SMARTTHINGS_LOCATION_ID'));
end;

function TSmartThingsTool.ApiRequest(const AToken, AMethod, APath,
  ABody: string): string;
var
  Client: TNetHTTPClient;
  RespSt: TStringStream;
  BodySt: TStringStream;
  Res:    IHTTPResponse;
  Hdrs:   TNetHeaders;
begin
  Client := TNetHTTPClient.Create(nil);
  RespSt := TStringStream.Create('', TEncoding.UTF8);
  BodySt := nil;
  try
    Client.SynchronizeEvents := False;
    Client.ConnectionTimeout := 15000;
    Client.ResponseTimeout   := 30000;

    SetLength(Hdrs, 2);
    Hdrs[0] := TNetHeader.Create('Authorization', 'Bearer ' + AToken);
    Hdrs[1] := TNetHeader.Create('Content-Type', 'application/json');

    if ABody <> '' then
      BodySt := TStringStream.Create(ABody, TEncoding.UTF8);

    if SameText(AMethod, 'GET') then
      Res := Client.Get(API_BASE + APath, RespSt, Hdrs)
    else if SameText(AMethod, 'POST') then
      Res := Client.Post(API_BASE + APath, BodySt, RespSt, Hdrs)
    else
      raise Exception.Create('Unsupported HTTP method: ' + AMethod);

    if (Res.StatusCode < 200) or (Res.StatusCode >= 300) then
      raise Exception.CreateFmt('SmartThings API %d on %s %s: %s',
        [Res.StatusCode, AMethod, APath, Copy(RespSt.DataString, 1, 500)]);

    Result := RespSt.DataString;
  finally
    BodySt.Free;
    RespSt.Free;
    Client.Free;
  end;
end;

function TSmartThingsTool.ApiGetJSON(const AToken, APath: string): TJSONValue;
begin
  Result := TJSONObject.ParseJSONValue(ApiRequest(AToken, 'GET', APath, ''));
  if Result = nil then
    raise Exception.Create('Invalid JSON from SmartThings API on ' + APath);
end;

// Raises if a location restriction is active and the device lives elsewhere.
procedure TSmartThingsTool.EnsureDeviceAllowed(const AToken, ADeviceId: string);
var
  Dev:     TJSONValue;
  LocId:   string;
  Allowed: string;
begin
  Allowed := AllowedLocation;
  if Allowed = '' then
    Exit;

  Dev := ApiGetJSON(AToken, '/devices/' + ADeviceId);
  try
    LocId := Dev.GetValue<string>('locationId', '');
    if not SameText(LocId, Allowed) then
      raise Exception.CreateFmt(
        'Device %s belongs to location %s, outside the allowed location %s ' +
        '(SMARTTHINGS_LOCATION_ID restriction)',
        [ADeviceId, LocId, Allowed]);
  finally
    Dev.Free;
  end;
end;

function TSmartThingsTool.SendCommand(const AToken, ADeviceId, ACapability,
  ACommand, AArguments: string): TJSONObject;
var
  Body:    TJSONObject;
  Cmd:     TJSONObject;
  Cmds:    TJSONArray;
  Args:    TJSONValue;
  RespStr: string;
begin
  EnsureDeviceAllowed(AToken, ADeviceId);

  Cmd := TJSONObject.Create;
  Cmd.AddPair('component', 'main');
  Cmd.AddPair('capability', ACapability);
  Cmd.AddPair('command', ACommand);
  if Trim(AArguments) <> '' then
  begin
    Args := TJSONObject.ParseJSONValue(AArguments);
    if not (Args is TJSONArray) then
    begin
      Args.Free;
      Cmd.Free;
      raise Exception.Create('"arguments" must be a JSON array string, e.g. "[50]"');
    end;
    Cmd.AddPair('arguments', TJSONArray(Args));
  end;

  Cmds := TJSONArray.Create;
  Cmds.AddElement(Cmd);
  Body := TJSONObject.Create;
  Body.AddPair('commands', Cmds);
  try
    RespStr := ApiRequest(AToken, 'POST',
      '/devices/' + ADeviceId + '/commands', Body.ToJSON);
  finally
    Body.Free;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('ok', TJSONBool.Create(True));
  Result.AddPair('deviceId', ADeviceId);
  Result.AddPair('capability', ACapability);
  Result.AddPair('command', ACommand);
  Result.AddPair('response', TJSONObject.ParseJSONValue(RespStr));
  Result.AddPair('note',
    'ACCEPTED does not guarantee execution: verify with "health" or "status"');
end;

function TSmartThingsTool.BuildText(const AJson: TJSONValue): TJSONObject;
begin
  Result := TAiMCPResponseBuilder.New.AddText(AJson.ToJSON).Build;
end;

// Extracts components.main.<cap>.<attr>.value (nil when absent).
function MainAttr(AMain: TJSONObject; const ACap, AAttr: string): TJSONValue;
var
  CapObj, AttrObj: TJSONObject;
begin
  Result := nil;
  if AMain = nil then Exit;
  CapObj := AMain.GetValue(ACap) as TJSONObject;
  if CapObj = nil then Exit;
  AttrObj := CapObj.GetValue(AAttr) as TJSONObject;
  if AttrObj = nil then Exit;
  Result := AttrObj.GetValue('value');
end;

procedure AddAttrIf(ASummary: TJSONObject; AMain: TJSONObject;
  const AName, ACap, AAttr: string);
var
  V: TJSONValue;
begin
  V := MainAttr(AMain, ACap, AAttr);
  if (V <> nil) and not (V is TJSONNull) then
    ASummary.AddPair(AName, TJSONValue(V.Clone));
end;

// ---- Main execution --------------------------------------------------------

function TSmartThingsTool.ExecuteWithParams(const AParams: TSmartThingsParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op:      string;
  Token:   string;
  Allowed: string;
  Root:    TJSONValue;
  R:       TJSONObject;
begin
  try
    Op      := LowerCase(Trim(AParams.Operation));
    Token   := ResolveToken(AParams.Token, AuthContext);
    Allowed := AllowedLocation;

    // -- locations ------------------------------------------------------
    if Op = 'locations' then
    begin
      Root := ApiGetJSON(Token, '/locations');
      try
        var Items := TJSONArray.Create;
        for var It in Root.GetValue<TJSONArray>('items') do
        begin
          var LocId := It.GetValue<string>('locationId', '');
          if (Allowed <> '') and not SameText(LocId, Allowed) then
            Continue;
          var Item := TJSONObject.Create;
          Item.AddPair('name', It.GetValue<string>('name', ''));
          Item.AddPair('locationId', LocId);
          Items.AddElement(Item);
        end;
        R := TJSONObject.Create;
        R.AddPair('locations', Items);
        if Allowed <> '' then
          R.AddPair('restrictedTo', Allowed);
        Result := BuildText(R);
        R.Free;
      finally
        Root.Free;
      end;
    end

    // -- devices --------------------------------------------------------
    else if Op = 'devices' then
    begin
      var Filter := Allowed;
      if Filter = '' then
        Filter := Trim(AParams.LocationId);

      var Path := '/devices';
      if Filter <> '' then
        Path := Path + '?locationId=' + Filter;

      Root := ApiGetJSON(Token, Path);
      try
        var Items := TJSONArray.Create;
        for var It in Root.GetValue<TJSONArray>('items') do
        begin
          var Item := TJSONObject.Create;
          Item.AddPair('label', It.GetValue<string>('label', ''));
          Item.AddPair('deviceId', It.GetValue<string>('deviceId', ''));
          Item.AddPair('type', It.GetValue<string>('type', ''));
          var Caps := TJSONArray.Create;
          var Comps := It.GetValue<TJSONArray>('components', nil);
          if (Comps <> nil) and (Comps.Count > 0) then
          begin
            var CapArr := TJSONObject(Comps[0]).GetValue<TJSONArray>('capabilities', nil);
            if CapArr <> nil then
              for var C in CapArr do
                Caps.Add(C.GetValue<string>('id', ''));
          end;
          Item.AddPair('capabilities', Caps);
          Items.AddElement(Item);
        end;
        R := TJSONObject.Create;
        R.AddPair('count', TJSONNumber.Create(Items.Count));
        R.AddPair('devices', Items);
        if Allowed <> '' then
          R.AddPair('restrictedTo', Allowed);
        Result := BuildText(R);
        R.Free;
      finally
        Root.Free;
      end;
    end

    // -- status ---------------------------------------------------------
    else if Op = 'status' then
    begin
      if AParams.DeviceId = '' then raise Exception.Create('"deviceId" is required');
      EnsureDeviceAllowed(Token, AParams.DeviceId);

      Root := ApiGetJSON(Token, '/devices/' + AParams.DeviceId + '/status');
      try
        var Main := Root.FindValue('components.main') as TJSONObject;
        if AParams.Full or (Main = nil) then
          Result := BuildText(Root)
        else
        begin
          R := TJSONObject.Create;
          R.AddPair('deviceId', AParams.DeviceId);
          AddAttrIf(R, Main, 'switch',      'switch', 'switch');
          AddAttrIf(R, Main, 'level',       'switchLevel', 'level');
          AddAttrIf(R, Main, 'power_w',     'powerMeter', 'power');
          AddAttrIf(R, Main, 'energy_kwh',  'energyMeter', 'energy');
          AddAttrIf(R, Main, 'temperature', 'temperatureMeasurement', 'temperature');
          AddAttrIf(R, Main, 'humidity',    'relativeHumidityMeasurement', 'humidity');
          AddAttrIf(R, Main, 'illuminance', 'illuminanceMeasurement', 'illuminance');
          AddAttrIf(R, Main, 'motion',      'motionSensor', 'motion');
          AddAttrIf(R, Main, 'battery',     'battery', 'battery');
          AddAttrIf(R, Main, 'presence',    'presenceSensor', 'presence');
          AddAttrIf(R, Main, 'volume',      'audioVolume', 'volume');
          AddAttrIf(R, Main, 'playback',    'mediaPlayback', 'playbackStatus');
          R.AddPair('note', 'values may be stale if the device is OFFLINE; check "health"');
          Result := BuildText(R);
          R.Free;
        end;
      finally
        Root.Free;
      end;
    end

    // -- health ---------------------------------------------------------
    else if Op = 'health' then
    begin
      if AParams.DeviceId = '' then raise Exception.Create('"deviceId" is required');
      EnsureDeviceAllowed(Token, AParams.DeviceId);

      Root := ApiGetJSON(Token, '/devices/' + AParams.DeviceId + '/health');
      try
        Result := BuildText(Root);
      finally
        Root.Free;
      end;
    end

    // -- on / off -------------------------------------------------------
    else if (Op = 'on') or (Op = 'off') then
    begin
      if AParams.DeviceId = '' then raise Exception.Create('"deviceId" is required');
      R := SendCommand(Token, AParams.DeviceId, 'switch', Op, '');
      Result := BuildText(R);
      R.Free;
    end

    // -- level ----------------------------------------------------------
    else if Op = 'level' then
    begin
      if AParams.DeviceId = '' then raise Exception.Create('"deviceId" is required');
      if (AParams.Level < 0) or (AParams.Level > 100) then
        raise Exception.Create('"level" must be 0..100');
      R := SendCommand(Token, AParams.DeviceId, 'switchLevel', 'setLevel',
        '[' + IntToStr(AParams.Level) + ']');
      Result := BuildText(R);
      R.Free;
    end

    // -- command (generic) ----------------------------------------------
    else if Op = 'command' then
    begin
      if AParams.DeviceId   = '' then raise Exception.Create('"deviceId" is required');
      if AParams.Capability = '' then raise Exception.Create('"capability" is required');
      if AParams.Command    = '' then raise Exception.Create('"command" is required');
      R := SendCommand(Token, AParams.DeviceId, AParams.Capability,
        AParams.Command, AParams.Arguments);
      Result := BuildText(R);
      R.Free;
    end

    // -- scenes ---------------------------------------------------------
    else if Op = 'scenes' then
    begin
      var Path := '/scenes';
      if Allowed <> '' then
        Path := Path + '?locationId=' + Allowed
      else if Trim(AParams.LocationId) <> '' then
        Path := Path + '?locationId=' + Trim(AParams.LocationId);

      Root := ApiGetJSON(Token, Path);
      try
        Result := BuildText(Root);
      finally
        Root.Free;
      end;
    end

    // -- scene (execute) --------------------------------------------------
    else if Op = 'scene' then
    begin
      if AParams.SceneId = '' then raise Exception.Create('"sceneId" is required');

      if Allowed <> '' then
      begin
        // Verify the scene belongs to the allowed location before executing.
        Root := ApiGetJSON(Token, '/scenes?locationId=' + Allowed);
        try
          var Found := False;
          var ItemsArr := Root.GetValue<TJSONArray>('items', nil);
          if ItemsArr <> nil then
            for var It in ItemsArr do
              if SameText(It.GetValue<string>('sceneId', ''), AParams.SceneId) then
              begin
                Found := True;
                Break;
              end;
          if not Found then
            raise Exception.CreateFmt(
              'Scene %s not found in allowed location %s ' +
              '(SMARTTHINGS_LOCATION_ID restriction)',
              [AParams.SceneId, Allowed]);
        finally
          Root.Free;
        end;
      end;

      var RespStr := ApiRequest(Token, 'POST',
        '/scenes/' + AParams.SceneId + '/execute', '');
      R := TJSONObject.Create;
      R.AddPair('ok', TJSONBool.Create(True));
      R.AddPair('sceneId', AParams.SceneId);
      R.AddPair('response', TJSONObject.ParseJSONValue(RespStr));
      Result := BuildText(R);
      R.Free;
    end

    else
      raise Exception.CreateFmt(
        'Unknown operation: "%s". Valid: locations, devices, status, health, ' +
        'on, off, level, command, scenes, scene', [Op]);

  except
    on E: Exception do
      Result := TAiMCPResponseBuilder.New
        .AddText('Error [mcp-smartthings]: ' + E.Message)
        .Build;
  end;
end;

constructor TSmartThingsTool.Create;
begin
  inherited;
  FName        := 'mcp-smartthings';
  FDescription :=
    'Control Samsung SmartThings devices via the cloud API. ' +
    'token: OPTIONAL if SMARTTHINGS_TOKEN env var is set. ' +
    'If SMARTTHINGS_LOCATION_ID env var is set, all operations are restricted ' +
    'to that location and commands to devices elsewhere are rejected. ' +
    'Operations and required params -- ' +
    'locations: none; ' +
    'devices: none (locationId? filter); ' +
    'status: deviceId, full? (raw JSON); ' +
    'health: deviceId (ONLINE/OFFLINE -- commands are ACCEPTED even for ' +
    'offline devices, so verify health or re-read status after commanding); ' +
    'on: deviceId; off: deviceId; ' +
    'level: deviceId, level (0..100); ' +
    'command: deviceId, capability, command, arguments? (JSON array string); ' +
    'scenes: none (locationId? filter); ' +
    'scene: sceneId.';
end;

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-smartthings',
    function: IAiMCPTool
    begin
      Result := TSmartThingsTool.Create;
    end);
  WriteLn(ErrOutput, '[MCPService]   + mcp-smartthings');
end;

end.
