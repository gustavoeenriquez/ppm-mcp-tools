unit MCPTool.HomeAssistant;

{
  MCPTool.HomeAssistant
  MCP tool: mcp-homeassistant

  Home Assistant REST API client (<HASS_URL>/api). Read entity states,
  history and logbook, call any service (lights, switches, climate, covers,
  media players, scripts, scenes, automations...), render Jinja templates
  and list areas.

  Credentials are never tool params (the model must not choose where to
  connect nor see the token):
    stdio:       HASS_URL / HASS_TOKEN env vars. HASS_TOKEN is a Long-Lived
                 Access Token (HA profile -> Security).
    server mode: (http/sse, MCPTool.Credential) HASS_URL and HASS_TOKEN come
                 from the JSON of the Authorization header of each request.

  Restrictions set by the machine owner (env vars, both modes):
    HASS_READONLY=1          blocks every write (call, on, off, toggle, fire)
    HASS_ALLOWED_DOMAINS=... comma list (light,switch,climate...). call/on/
                             off/toggle are rejected when the service domain
                             or the domain of any target entity is not listed.
                             It also turns on restricted mode for "fire":
                             no event can be fired unless listed below.
    HASS_ALLOWED_EVENTS=...  comma list of event types "fire" may send. When
                             set, any other event is rejected. Events feed
                             automations, sensors and notifications, so in
                             restricted mode none is allowed by default.

  Errors are returned with "isError": true (MCP tool error).

  Operations:
    config    - HA version, location, units, components count (connection test)
    states    - compact entity list (domain?, search?, limit?)
    state     - full state + attributes of one entity
    areas     - areas with their entities (via template)
    services  - available services (domain? filter)
    call      - call domain.service with entityId? and data? (JSON object)
    on/off/toggle - homeassistant.turn_on/turn_off/toggle on entityId
    history   - state history of entityId (hours? or startTime?/endTime?)
    logbook   - logbook entries (entityId? optional, hours? or startTime?/endTime?)
    template  - render a Jinja2 template
    events    - list event types with listener count
    fire      - fire an event (eventType, data?)
    errorlog  - tail of home-assistant.log
}

interface

uses
  uMakerAi.MCPServer.Core,
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.DateUtils,
  System.NetEncoding,
  System.Net.HttpClient,
  System.Net.HttpClientComponent,
  System.Net.URLClient;

type

  THomeAssistantParams = class
  private
    FOperation: string;
    FEntityId:  string;
    FDomain:    string;
    FService:   string;
    FData:      string;
    FSearch:    string;
    FLimit:     Integer;
    FHours:     Integer;
    FStartTime: string;
    FEndTime:   string;
    FTemplate:  string;
    FEventType: string;
    FReturnResponse: Boolean;
  public
    [AiMCPSchemaDescription(
      'Operation to perform. Required params per operation: ' +
      'config=none; states=none (domain, search, limit optional); ' +
      'state=entityId; areas=none; services=none (domain optional); ' +
      'call=domain+service (entityId, data, returnResponse optional); ' +
      'on/off/toggle=entityId; history=entityId (hours or startTime/endTime optional); ' +
      'logbook=none (entityId, hours or startTime/endTime optional); ' +
      'template=template; events=none; fire=eventType (data optional); ' +
      'errorlog=none (limit = last N lines)')]
    property Operation: string read FOperation write FOperation;

    [AiMCPOptional]
    [AiMCPSchemaDescription(
      'Entity id, e.g. light.cocina. For call/on/off/toggle it may be a ' +
      'comma separated list: light.cocina,light.sala')]
    property EntityId: string read FEntityId write FEntityId;

    [AiMCPOptional]
    [AiMCPSchemaDescription(
      'Domain: service domain for call (light, switch, climate, script...), ' +
      'or filter for states/services')]
    property Domain: string read FDomain write FDomain;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Service name for call, e.g. turn_on, set_temperature, open_cover')]
    property Service: string read FService write FService;

    [AiMCPOptional]
    [AiMCPSchemaDescription(
      'Service or event data as a JSON object string, e.g. ' +
      '"{\"brightness_pct\":50}" or "{\"temperature\":22}"')]
    property Data: string read FData write FData;

    [AiMCPOptional]
    [AiMCPSchemaDescription('states only: case-insensitive text matched against entity_id and friendly_name')]
    property Search: string read FSearch write FSearch;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Max items returned (states default 200; history/logbook default 200; errorlog default 100 lines)')]
    property Limit: Integer read FLimit write FLimit;

    [AiMCPOptional]
    [AiMCPSchemaDescription('history/logbook: how many hours back from now (default 24). Ignored if startTime is given.')]
    property Hours: Integer read FHours write FHours;

    [AiMCPOptional]
    [AiMCPSchemaDescription('history/logbook: start time ISO 8601, e.g. 2026-10-15T08:00:00-05:00')]
    property StartTime: string read FStartTime write FStartTime;

    [AiMCPOptional]
    [AiMCPSchemaDescription('history/logbook: end time ISO 8601 (default now)')]
    property EndTime: string read FEndTime write FEndTime;

    [AiMCPOptional]
    [AiMCPSchemaDescription('template only: Jinja2 template, e.g. "{{ states(''sensor.temperatura'') }}"')]
    property Template: string read FTemplate write FTemplate;

    [AiMCPOptional]
    [AiMCPSchemaDescription('fire only: event type to fire')]
    property EventType: string read FEventType write FEventType;

    [AiMCPOptional]
    [AiMCPSchemaDescription('call only: true for services that return data (e.g. weather.get_forecasts, calendar.get_events)')]
    property ReturnResponse: Boolean read FReturnResponse write FReturnResponse;
  end;

  // The server keeps ONE tool instance for every request (http/sse serve
  // several users at once), so the account travels as a value, never in fields.
  THassAccount = record
    Base:  string;
    Token: string;
  end;

  THomeAssistantTool = class(TAiMCPToolBase<THomeAssistantParams>)
  private
    function ResolveAccount(const AParams: THomeAssistantParams;
      const AuthContext: TAiAuthContext): THassAccount;
    function ApiRequest(const Acc: THassAccount; const AMethod, APath,
      ABody: string): string;
    function ApiGetJSON(const Acc: THassAccount; const APath: string): TJSONValue;
    procedure EnsureWritable;
    procedure EnsureDomainAllowed(const ADomain: string);
    procedure EnsureEventAllowed(const AEventType: string);
    function CallService(const Acc: THassAccount; const ADomain, AService,
      AEntities, AData: string; AReturnResponse: Boolean): TJSONObject;
    function TimeRange(const AParams: THomeAssistantParams;
      out AStart, AEndQuery: string): Boolean;
    function BuildText(const AJson: TJSONValue): TJSONObject;
  protected
    function ExecuteWithParams(const AParams: THomeAssistantParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

procedure RegisterTools(AServer: TAiMCPServer);

implementation

uses
  MCPTool.Credential;

const
  AREAS_TEMPLATE =
    '{% set ns = namespace(r=[]) %}' +
    '{% for a in areas() %}' +
    '{% set ns.r = ns.r + [{''area_id'': a, ''name'': area_name(a), ' +
    '''entities'': area_entities(a)}] %}' +
    '{% endfor %}{{ ns.r | tojson }}';

// ---- Helpers ---------------------------------------------------------------

function UrlEnc(const S: string): string;
begin
  Result := TNetEncoding.URL.EncodeQuery(S);
  // EncodeQuery leaves '+' as is, but HA would read it as a space.
  Result := StringReplace(Result, '+', '%2B', [rfReplaceAll]);
end;

function IsTrue(const S: string): Boolean;
begin
  Result := SameText(S, '1') or SameText(S, 'true') or SameText(S, 'yes');
end;

function EntityDomain(const AEntity: string): string;
var
  P: Integer;
begin
  P := Pos('.', AEntity);
  if P > 0 then
    Result := LowerCase(Copy(AEntity, 1, P - 1))
  else
    Result := '';
end;

function SplitEntities(const S: string): TArray<string>;
var
  Parts: TArray<string>;
  E: string;
begin
  Result := [];
  Parts := S.Split([',', ';', ' '], TStringSplitOptions.ExcludeEmpty);
  for E in Parts do
    if Trim(E) <> '' then
      Result := Result + [Trim(E)];
end;

function ParseDataObject(const AData: string): TJSONObject;
var
  V: TJSONValue;
begin
  if Trim(AData) = '' then
    Exit(TJSONObject.Create);
  V := TJSONObject.ParseJSONValue(AData);
  if not (V is TJSONObject) then
  begin
    V.Free;
    raise Exception.Create('"data" must be a JSON object string, e.g. "{\"brightness_pct\":50}"');
  end;
  Result := TJSONObject(V);
end;

function THomeAssistantTool.ResolveAccount(const AParams: THomeAssistantParams;
  const AuthContext: TAiAuthContext): THassAccount;
var
  LBase, LToken: string;
begin
  if ServerMode then
  begin
    LBase  := Cred(AuthContext, 'HASS_URL');
    LToken := Cred(AuthContext, 'HASS_TOKEN');
    if (LBase = '') or (LToken = '') then
      raise Exception.Create('La cuenta de Home Assistant conectada no trae HASS_URL y HASS_TOKEN.');
  end
  else
  begin
    LBase  := Trim(GetEnvironmentVariable('HASS_URL'));
    LToken := Trim(GetEnvironmentVariable('HASS_TOKEN'));
    if LBase = '' then
      raise Exception.Create('HASS_URL env var is not set (e.g. http://192.168.1.10:8123)');
    if LToken = '' then
      raise Exception.Create('HASS_TOKEN env var is not set (Long-Lived Access Token)');
  end;

  LBase := Trim(LBase);
  while LBase.EndsWith('/') do
    SetLength(LBase, Length(LBase) - 1);
  // Accept both http://host:8123 and http://host:8123/api
  if LBase.EndsWith('/api', True) then
    SetLength(LBase, Length(LBase) - 4);
  if not (LBase.StartsWith('http://', True) or LBase.StartsWith('https://', True)) then
    raise Exception.Create('HASS_URL must start with http:// or https://');
  Result.Base  := LBase;
  Result.Token := LToken;
end;

function THomeAssistantTool.ApiRequest(const Acc: THassAccount; const AMethod,
  APath, ABody: string): string;
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
    Client.ResponseTimeout   := 60000;

    SetLength(Hdrs, 2);
    Hdrs[0] := TNetHeader.Create('Authorization', 'Bearer ' + Acc.Token);
    Hdrs[1] := TNetHeader.Create('Content-Type', 'application/json');

    if SameText(AMethod, 'GET') then
      Res := Client.Get(Acc.Base + '/api' + APath, RespSt, Hdrs)
    else if SameText(AMethod, 'POST') then
    begin
      BodySt := TStringStream.Create(ABody, TEncoding.UTF8);
      Res := Client.Post(Acc.Base + '/api' + APath, BodySt, RespSt, Hdrs);
    end
    else
      raise Exception.Create('Unsupported HTTP method: ' + AMethod);

    if Res.StatusCode = 401 then
      raise Exception.Create('Home Assistant rejected the token (401): check HASS_TOKEN');
    if (Res.StatusCode < 200) or (Res.StatusCode >= 300) then
      raise Exception.CreateFmt('Home Assistant API %d on %s %s: %s',
        [Res.StatusCode, AMethod, APath, Copy(RespSt.DataString, 1, 500)]);

    Result := RespSt.DataString;
  finally
    BodySt.Free;
    RespSt.Free;
    Client.Free;
  end;
end;

function THomeAssistantTool.ApiGetJSON(const Acc: THassAccount;
  const APath: string): TJSONValue;
begin
  Result := TJSONObject.ParseJSONValue(ApiRequest(Acc, 'GET', APath, ''));
  if Result = nil then
    raise Exception.Create('Invalid JSON from Home Assistant on ' + APath);
end;

procedure THomeAssistantTool.EnsureWritable;
begin
  if IsTrue(Trim(GetEnvironmentVariable('HASS_READONLY'))) then
    raise Exception.Create('Write operations are disabled (HASS_READONLY)');
end;

procedure THomeAssistantTool.EnsureDomainAllowed(const ADomain: string);
var
  Allowed: string;
  D: string;
begin
  Allowed := Trim(GetEnvironmentVariable('HASS_ALLOWED_DOMAINS'));
  if Allowed = '' then
    Exit;
  for D in Allowed.Split([',', ';', ' '], TStringSplitOptions.ExcludeEmpty) do
    if SameText(Trim(D), ADomain) then
      Exit;
  raise Exception.CreateFmt(
    'Domain "%s" is not allowed (HASS_ALLOWED_DOMAINS=%s)', [ADomain, Allowed]);
end;

procedure THomeAssistantTool.EnsureEventAllowed(const AEventType: string);
var
  Events: string;
  E: string;
begin
  Events := Trim(GetEnvironmentVariable('HASS_ALLOWED_EVENTS'));
  if Events <> '' then
  begin
    for E in Events.Split([',', ';', ' '], TStringSplitOptions.ExcludeEmpty) do
      if SameText(Trim(E), AEventType) then
        Exit;
    raise Exception.CreateFmt(
      'Event "%s" is not allowed (HASS_ALLOWED_EVENTS=%s)', [AEventType, Events]);
  end;
  // Restricted mode without an event list: events can trigger anything
  // (automations, alarms, notifications), so none is allowed.
  if Trim(GetEnvironmentVariable('HASS_ALLOWED_DOMAINS')) <> '' then
    raise Exception.CreateFmt(
      'Firing events is disabled while HASS_ALLOWED_DOMAINS is set; list the ' +
      'allowed ones in HASS_ALLOWED_EVENTS (event "%s" rejected)', [AEventType]);
end;

function THomeAssistantTool.CallService(const Acc: THassAccount; const ADomain,
  AService, AEntities, AData: string; AReturnResponse: Boolean): TJSONObject;
var
  Body:     TJSONObject;
  Ents:     TArray<string>;
  E:        string;
  Arr:      TJSONArray;
  Path:     string;
  RespStr:  string;
  RespJson: TJSONValue;
begin
  EnsureWritable;
  // homeassistant.* is generic: what matters is the domain of each entity.
  if not SameText(ADomain, 'homeassistant') then
    EnsureDomainAllowed(ADomain);
  Ents := SplitEntities(AEntities);
  for E in Ents do
  begin
    if EntityDomain(E) = '' then
      raise Exception.CreateFmt('Invalid entity id "%s" (expected domain.object_id)', [E]);
    EnsureDomainAllowed(EntityDomain(E));
  end;
  if SameText(ADomain, 'homeassistant') and (Length(Ents) = 0) then
    raise Exception.Create('"entityId" is required for homeassistant.* services');

  Body := ParseDataObject(AData);
  try
    if Length(Ents) > 0 then
    begin
      Body.RemovePair('entity_id').Free;
      if Length(Ents) = 1 then
        Body.AddPair('entity_id', Ents[0])
      else
      begin
        Arr := TJSONArray.Create;
        for E in Ents do
          Arr.Add(E);
        Body.AddPair('entity_id', Arr);
      end;
    end;
    Path := '/services/' + ADomain + '/' + AService;
    if AReturnResponse then
      Path := Path + '?return_response';
    RespStr := ApiRequest(Acc, 'POST', Path, Body.ToJSON);
  finally
    Body.Free;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('ok', TJSONBool.Create(True));
  Result.AddPair('service', ADomain + '.' + AService);
  RespJson := TJSONObject.ParseJSONValue(RespStr);
  if RespJson = nil then
    RespJson := TJSONString.Create(RespStr);
  if AReturnResponse then
    Result.AddPair('response', RespJson)
  else
  begin
    // HA answers with the states that changed while the service ran.
    Result.AddPair('changed_states', RespJson);
    if (RespJson is TJSONArray) and (TJSONArray(RespJson).Count = 0) then
      Result.AddPair('note',
        'No state changed (maybe it already was in that state, or the ' +
        'device is slow/unavailable): re-read with "state" to verify');
  end;
end;

// Builds "/<start>" and "?end_time=..." parts. Returns False if no start.
function THomeAssistantTool.TimeRange(const AParams: THomeAssistantParams;
  out AStart, AEndQuery: string): Boolean;
var
  H: Integer;
  StartUtc: TDateTime;
begin
  AEndQuery := '';
  if Trim(AParams.StartTime) <> '' then
    AStart := Trim(AParams.StartTime)
  else
  begin
    H := AParams.Hours;
    if H <= 0 then
      H := 24;
    StartUtc := IncHour(TTimeZone.Local.ToUniversalTime(Now), -H);
    AStart := FormatDateTime('yyyy"-"mm"-"dd"T"hh":"nn":"ss', StartUtc) + '+00:00';
  end;
  if Trim(AParams.EndTime) <> '' then
    AEndQuery := 'end_time=' + UrlEnc(Trim(AParams.EndTime));
  Result := AStart <> '';
end;

function THomeAssistantTool.BuildText(const AJson: TJSONValue): TJSONObject;
begin
  Result := TAiMCPResponseBuilder.New.AddText(AJson.ToJSON).Build;
end;

function CompactState(AIt: TJSONValue): TJSONObject;
var
  Attrs: TJSONObject;
  S: string;
begin
  Result := TJSONObject.Create;
  Result.AddPair('entity_id', AIt.GetValue<string>('entity_id', ''));
  Result.AddPair('state', AIt.GetValue<string>('state', ''));
  Attrs := AIt.GetValue<TJSONObject>('attributes', nil);
  if Attrs <> nil then
  begin
    S := Attrs.GetValue<string>('friendly_name', '');
    if S <> '' then
      Result.AddPair('name', S);
    S := Attrs.GetValue<string>('unit_of_measurement', '');
    if S <> '' then
      Result.AddPair('unit', S);
    S := Attrs.GetValue<string>('device_class', '');
    if S <> '' then
      Result.AddPair('device_class', S);
  end;
  Result.AddPair('last_changed', AIt.GetValue<string>('last_changed', ''));
end;

// ---- Main execution --------------------------------------------------------

function THomeAssistantTool.ExecuteWithParams(const AParams: THomeAssistantParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op:   string;
  Acc:  THassAccount;
  Root: TJSONValue;
  R:    TJSONObject;
begin
  try
    Op := LowerCase(Trim(AParams.Operation));
    Acc := ResolveAccount(AParams, AuthContext);

    // -- config ---------------------------------------------------------
    if Op = 'config' then
    begin
      Root := ApiGetJSON(Acc, '/config');
      try
        R := TJSONObject.Create;
        try
          for var Key in ['location_name', 'version', 'time_zone', 'country',
            'currency', 'state', 'external_url', 'internal_url'] do
          begin
            var V := Root.FindValue(Key);
            if (V <> nil) and not (V is TJSONNull) then
              R.AddPair(Key, TJSONValue(V.Clone));
          end;
          var Units := Root.FindValue('unit_system');
          if Units <> nil then
            R.AddPair('unit_system', TJSONValue(Units.Clone));
          var Comps := Root.GetValue<TJSONArray>('components', nil);
          if Comps <> nil then
            R.AddPair('components_count', TJSONNumber.Create(Comps.Count));
          R.AddPair('readonly', TJSONBool.Create(IsTrue(GetEnvironmentVariable('HASS_READONLY'))));
          var Allowed := Trim(GetEnvironmentVariable('HASS_ALLOWED_DOMAINS'));
          if Allowed <> '' then
            R.AddPair('allowed_domains', Allowed);
          var Events := Trim(GetEnvironmentVariable('HASS_ALLOWED_EVENTS'));
          if Events <> '' then
            R.AddPair('allowed_events', Events)
          else if Allowed <> '' then
            R.AddPair('allowed_events', 'none');
          Result := BuildText(R);
        finally
          R.Free;
        end;
      finally
        Root.Free;
      end;
    end

    // -- states ---------------------------------------------------------
    else if Op = 'states' then
    begin
      var Dom    := LowerCase(Trim(AParams.Domain));
      var Search := LowerCase(Trim(AParams.Search));
      var Limit  := AParams.Limit;
      if Limit <= 0 then
        Limit := 200;

      Root := ApiGetJSON(Acc, '/states');
      try
        var Items := TJSONArray.Create;
        var Total := 0;
        for var It in Root as TJSONArray do
        begin
          var Eid := It.GetValue<string>('entity_id', '');
          if (Dom <> '') and (EntityDomain(Eid) <> Dom) then
            Continue;
          if Search <> '' then
          begin
            var Name := LowerCase(It.GetValue<string>('attributes.friendly_name', ''));
            if (Pos(Search, LowerCase(Eid)) = 0) and (Pos(Search, Name) = 0) then
              Continue;
          end;
          Inc(Total);
          if Items.Count < Limit then
            Items.AddElement(CompactState(It));
        end;
        R := TJSONObject.Create;
        try
          R.AddPair('count', TJSONNumber.Create(Total));
          if Total > Items.Count then
            R.AddPair('truncated_to', TJSONNumber.Create(Items.Count));
          R.AddPair('entities', Items);
          Result := BuildText(R);
        finally
          R.Free;
        end;
      finally
        Root.Free;
      end;
    end

    // -- state ----------------------------------------------------------
    else if Op = 'state' then
    begin
      if Trim(AParams.EntityId) = '' then raise Exception.Create('"entityId" is required');
      Root := ApiGetJSON(Acc, '/states/' + Trim(AParams.EntityId));
      try
        Result := BuildText(Root);
      finally
        Root.Free;
      end;
    end

    // -- areas ----------------------------------------------------------
    else if Op = 'areas' then
    begin
      var Body := TJSONObject.Create;
      try
        Body.AddPair('template', AREAS_TEMPLATE);
        var Txt := ApiRequest(Acc, 'POST', '/template', Body.ToJSON);
        Result := TAiMCPResponseBuilder.New.AddText(Txt).Build;
      finally
        Body.Free;
      end;
    end

    // -- services -------------------------------------------------------
    else if Op = 'services' then
    begin
      var Dom := LowerCase(Trim(AParams.Domain));
      Root := ApiGetJSON(Acc, '/services');
      try
        R := TJSONObject.Create;
        try
          for var It in Root as TJSONArray do
          begin
            var D := It.GetValue<string>('domain', '');
            if (Dom <> '') and (D <> Dom) then
              Continue;
            var Svcs := It.GetValue<TJSONObject>('services', nil);
            if Svcs = nil then
              Continue;
            if Dom <> '' then
              // Single domain: full detail (fields, targets)
              R.AddPair(D, TJSONValue(Svcs.Clone))
            else
            begin
              // All domains: only the service names, to keep it small
              var Names := TJSONArray.Create;
              for var P in Svcs do
                Names.Add(P.JsonString.Value);
              R.AddPair(D, Names);
            end;
          end;
          Result := BuildText(R);
        finally
          R.Free;
        end;
      finally
        Root.Free;
      end;
    end

    // -- call -----------------------------------------------------------
    else if Op = 'call' then
    begin
      var Dom := LowerCase(Trim(AParams.Domain));
      var Svc := LowerCase(Trim(AParams.Service));
      // Accept service = "light.turn_on" without domain
      if (Dom = '') and (Pos('.', Svc) > 0) then
      begin
        Dom := EntityDomain(Svc);
        Svc := Copy(Svc, Pos('.', Svc) + 1, MaxInt);
      end;
      if Dom = '' then raise Exception.Create('"domain" is required');
      if Svc = '' then raise Exception.Create('"service" is required');
      R := CallService(Acc, Dom, Svc, AParams.EntityId, AParams.Data, AParams.ReturnResponse);
      try
        Result := BuildText(R);
      finally
        R.Free;
      end;
    end

    // -- on / off / toggle ----------------------------------------------
    else if (Op = 'on') or (Op = 'off') or (Op = 'toggle') then
    begin
      if Trim(AParams.EntityId) = '' then raise Exception.Create('"entityId" is required');
      var Svc := 'toggle';
      if Op = 'on' then Svc := 'turn_on'
      else if Op = 'off' then Svc := 'turn_off';
      R := CallService(Acc, 'homeassistant', Svc, AParams.EntityId, AParams.Data, False);
      try
        Result := BuildText(R);
      finally
        R.Free;
      end;
    end

    // -- history --------------------------------------------------------
    else if Op = 'history' then
    begin
      if Trim(AParams.EntityId) = '' then raise Exception.Create('"entityId" is required');
      var StartS, EndQ: string;
      TimeRange(AParams, StartS, EndQ);
      var Path := '/history/period/' + UrlEnc(StartS) +
        '?filter_entity_id=' + UrlEnc(Trim(AParams.EntityId)) +
        '&minimal_response&no_attributes';
      if EndQ <> '' then
        Path := Path + '&' + EndQ;
      var Limit := AParams.Limit;
      if Limit <= 0 then
        Limit := 200;

      Root := ApiGetJSON(Acc, Path);
      try
        R := TJSONObject.Create;
        try
          R.AddPair('start', StartS);
          var Series := TJSONObject.Create;
          R.AddPair('history', Series);
          for var Group in Root as TJSONArray do
          begin
            var Arr := Group as TJSONArray;
            if Arr.Count = 0 then
              Continue;
            var Eid := Arr[0].GetValue<string>('entity_id', '');
            var Points := TJSONArray.Create;
            // Keep the most recent points when over the limit
            var First := 0;
            if Arr.Count > Limit then
              First := Arr.Count - Limit;
            for var k := First to Arr.Count - 1 do
            begin
              var P := TJSONObject.Create;
              P.AddPair('state', Arr[k].GetValue<string>('state', ''));
              P.AddPair('at', Arr[k].GetValue<string>('last_changed', ''));
              Points.AddElement(P);
            end;
            var S := TJSONObject.Create;
            S.AddPair('points', TJSONNumber.Create(Arr.Count));
            if First > 0 then
              S.AddPair('truncated_to_last', TJSONNumber.Create(Limit));
            S.AddPair('values', Points);
            Series.AddPair(Eid, S);
          end;
          Result := BuildText(R);
        finally
          R.Free;
        end;
      finally
        Root.Free;
      end;
    end

    // -- logbook --------------------------------------------------------
    else if Op = 'logbook' then
    begin
      var StartS, EndQ: string;
      TimeRange(AParams, StartS, EndQ);
      var Path := '/logbook/' + UrlEnc(StartS);
      var Q := EndQ;
      if Trim(AParams.EntityId) <> '' then
      begin
        if Q <> '' then Q := Q + '&';
        Q := Q + 'entity=' + UrlEnc(Trim(AParams.EntityId));
      end;
      if Q <> '' then
        Path := Path + '?' + Q;
      var Limit := AParams.Limit;
      if Limit <= 0 then
        Limit := 200;

      Root := ApiGetJSON(Acc, Path);
      try
        var Arr := Root as TJSONArray;
        var Items := TJSONArray.Create;
        var First := 0;
        if Arr.Count > Limit then
          First := Arr.Count - Limit;
        for var k := First to Arr.Count - 1 do
          Items.AddElement(TJSONValue(Arr[k].Clone));
        R := TJSONObject.Create;
        try
          R.AddPair('start', StartS);
          R.AddPair('count', TJSONNumber.Create(Arr.Count));
          if First > 0 then
            R.AddPair('truncated_to_last', TJSONNumber.Create(Limit));
          R.AddPair('entries', Items);
          Result := BuildText(R);
        finally
          R.Free;
        end;
      finally
        Root.Free;
      end;
    end

    // -- template -------------------------------------------------------
    else if Op = 'template' then
    begin
      if Trim(AParams.Template) = '' then raise Exception.Create('"template" is required');
      var Body := TJSONObject.Create;
      try
        Body.AddPair('template', AParams.Template);
        var Txt := ApiRequest(Acc, 'POST', '/template', Body.ToJSON);
        Result := TAiMCPResponseBuilder.New.AddText(Txt).Build;
      finally
        Body.Free;
      end;
    end

    // -- events ---------------------------------------------------------
    else if Op = 'events' then
    begin
      Root := ApiGetJSON(Acc, '/events');
      try
        Result := BuildText(Root);
      finally
        Root.Free;
      end;
    end

    // -- fire -----------------------------------------------------------
    else if Op = 'fire' then
    begin
      EnsureWritable;
      var Ev := Trim(AParams.EventType);
      if Ev = '' then raise Exception.Create('"eventType" is required');
      EnsureEventAllowed(Ev);
      var Body := ParseDataObject(AParams.Data);
      try
        var Txt := ApiRequest(Acc, 'POST', '/events/' + UrlEnc(Ev), Body.ToJSON);
        Result := TAiMCPResponseBuilder.New.AddText(Txt).Build;
      finally
        Body.Free;
      end;
    end

    // -- errorlog -------------------------------------------------------
    else if Op = 'errorlog' then
    begin
      var Lines := TStringList.Create;
      try
        Lines.Text := ApiRequest(Acc, 'GET', '/error_log', '');
        var N := AParams.Limit;
        if N <= 0 then
          N := 100;
        while Lines.Count > N do
          Lines.Delete(0);
        Result := TAiMCPResponseBuilder.New.AddText(Lines.Text).Build;
      finally
        Lines.Free;
      end;
    end

    else
      raise Exception.CreateFmt(
        'Unknown operation: "%s". Valid: config, states, state, areas, services, ' +
        'call, on, off, toggle, history, logbook, template, events, fire, errorlog', [Op]);

  except
    on E: Exception do
    begin
      Result := TAiMCPResponseBuilder.New
        .AddText('Error [mcp-homeassistant]: ' + E.Message)
        .Build;
      // MCP tool error: lets the client tell a failure from a good answer
      Result.AddPair('isError', TJSONBool.Create(True));
    end;
  end;
end;

constructor THomeAssistantTool.Create;
begin
  inherited;
  FName        := 'mcp-homeassistant';
  FDescription :=
    'Control and query a Home Assistant instance via its REST API. ' +
    'The connection (URL and token) is configured outside the tool. ' +
    'Typical flow: "states" with domain/search to find the entity_id, then ' +
    '"call" or on/off/toggle, then "state" to verify. ' +
    'Operations and required params -- ' +
    'config: none (connection test, version); ' +
    'states: none (domain? e.g. light, search? text, limit?); ' +
    'state: entityId (full attributes); ' +
    'areas: none (areas with their entities); ' +
    'services: none (domain? gives full field detail for that domain); ' +
    'call: domain, service, entityId? (comma list ok), data? (JSON object ' +
    'string, e.g. {"brightness_pct":50}), returnResponse? (for services that ' +
    'return data such as weather.get_forecasts); ' +
    'on/off/toggle: entityId (any domain); ' +
    'history: entityId, hours? (default 24) or startTime?/endTime? (ISO 8601); ' +
    'logbook: entityId?, hours? or startTime?/endTime?; ' +
    'template: template (Jinja2); ' +
    'events: none; fire: eventType, data?; ' +
    'errorlog: limit? (last N lines). ' +
    'Use "config" to see the restrictions in force: readonly blocks every ' +
    'write; allowed_domains limits which domains can be commanded; ' +
    'allowed_events limits which events can be fired.';
end;

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-homeassistant',
    function: IAiMCPTool
    begin
      Result := THomeAssistantTool.Create;
    end);
  WriteLn(ErrOutput, '[MCPService]   + mcp-homeassistant');
end;

end.
