unit MCPTool.Prometheus;

{
  MCPTool.Prometheus  ·  mcp-prometheus  (port 8640)
  Prometheus HTTP API v1.

  Operations:
    query        - instant query (PromQL)
    query_range  - range query with step
    labels       - list label names
    label_values - list values for a label
    series       - find series matching selectors
    targets      - list scrape targets
    alerts       - list active alerts
    rules        - list alerting and recording rules
    metadata     - metric metadata
    tsdb_status  - TSDB status
}

interface

uses
  uMakerAi.MCPServer.Core,
  System.JSON;

type
  TPrometheusParams = class
  private
    FOperation  : string;
    FBaseUrl    : string;
    FUsername   : string;
    FPassword   : string;
    FBearerToken: string;
    FQuery      : string;
    FStart      : string;
    FEnd_       : string;
    FStep       : string;
    FTime       : string;
    FLabelName      : string;
    FMatch      : string;
    FTimeout    : string;
  public
    constructor Create;

    [AiMCPSchemaDescription('Operation: query, query_range, labels, label_values, series, targets, alerts, rules, metadata, tsdb_status')]
    property Operation  : string  read FOperation   write FOperation;

    [AiMCPSchemaDescription('Prometheus base URL (default: http://localhost:9090)')]
    property BaseUrl    : string  read FBaseUrl     write FBaseUrl;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Basic auth username')]
    property Username   : string  read FUsername    write FUsername;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Basic auth password')]
    property Password   : string  read FPassword    write FPassword;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Bearer token for auth')]
    property BearerToken: string  read FBearerToken write FBearerToken;

    [AiMCPOptional]
    [AiMCPSchemaDescription('PromQL query expression e.g. up, rate(http_requests_total[5m])')]
    property Query      : string  read FQuery       write FQuery;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Start timestamp (RFC3339 or Unix timestamp) for query_range')]
    property Start      : string  read FStart       write FStart;

    [AiMCPOptional]
    [AiMCPSchemaDescription('End timestamp (RFC3339 or Unix timestamp) for query_range')]
    property End_       : string  read FEnd_        write FEnd_;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Query resolution step for query_range e.g. 15s, 1m, 5m')]
    property Step       : string  read FStep        write FStep;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Evaluation timestamp for instant query (RFC3339 or Unix, default: now)')]
    property Time       : string  read FTime        write FTime;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Label name for label_values operation')]
    property LabelName  : string  read FLabelName       write FLabelName;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Series selector for series/label_values e.g. {job="prometheus"}')]
    property Match      : string  read FMatch       write FMatch;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Evaluation timeout e.g. 30s (passed to Prometheus)')]
    property Timeout    : string  read FTimeout     write FTimeout;
  end;

  TPrometheusTool = class(TAiMCPToolBase<TPrometheusParams>)
  private
    function GetBase(const P: TPrometheusParams): string;
    function GetAuth(const P: TPrometheusParams): string;
    function ApiGet(const URL, Auth: string): TJSONObject;

    function DoQuery(const P: TPrometheusParams): TJSONObject;
    function DoQueryRange(const P: TPrometheusParams): TJSONObject;
    function DoLabels(const P: TPrometheusParams): TJSONObject;
    function DoLabelValues(const P: TPrometheusParams): TJSONObject;
    function DoSeries(const P: TPrometheusParams): TJSONObject;
    function DoTargets(const P: TPrometheusParams): TJSONObject;
    function DoAlerts(const P: TPrometheusParams): TJSONObject;
    function DoRules(const P: TPrometheusParams): TJSONObject;
    function DoMetadata(const P: TPrometheusParams): TJSONObject;
    function DoTsdbStatus(const P: TPrometheusParams): TJSONObject;
  protected
    function ExecuteWithParams(const AParams: TPrometheusParams;
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

{ TPrometheusParams }

constructor TPrometheusParams.Create;
begin
  inherited;
  FBaseUrl := 'http://localhost:9090';
  FStep    := '15s';
end;

{ TPrometheusTool }

constructor TPrometheusTool.Create;
begin
  inherited;
  FName        := 'mcp-prometheus';
  FDescription :=
    'Prometheus HTTP API v1 — PromQL queries, targets, alerts, rules. ' +
    'Operations: query (query, time?), query_range (query, start, end, step?), ' +
    'labels (match?), label_values (label, match?), series (match), ' +
    'targets, alerts, rules, metadata (query?), tsdb_status. ' +
    'Auth: baseUrl (default http://localhost:9090), username+password or bearerToken.';
end;

function TPrometheusTool.GetBase(const P: TPrometheusParams): string;
var
  B: string;
begin
  B := Trim(P.BaseUrl);
  if B = '' then B := 'http://localhost:9090';
  // Remove trailing slash
  while (Length(B) > 0) and (B[Length(B)] = '/') do
    SetLength(B, Length(B) - 1);
  Result := B + '/api/v1';
end;

function TPrometheusTool.GetAuth(const P: TPrometheusParams): string;
var
  Bytes: TBytes;
begin
  if Trim(P.BearerToken) <> '' then
    Result := 'Bearer ' + Trim(P.BearerToken)
  else if Trim(P.Username) <> '' then
  begin
    Bytes  := TEncoding.UTF8.GetBytes(Trim(P.Username) + ':' + Trim(P.Password));
    Result := 'Basic ' + TNetEncoding.Base64.EncodeBytesToString(Bytes);
  end
  else
    Result := '';
end;

function TPrometheusTool.ApiGet(const URL, Auth: string): TJSONObject;
var
  HTTP: THTTPClient;
  Resp: IHTTPResponse;
begin
  HTTP := THTTPClient.Create;
  try
    if Auth <> '' then
      Resp := HTTP.Get(URL, nil, [TNameValuePair.Create('Authorization', Auth)])
    else
      Resp := HTTP.Get(URL);
    Result := TJSONObject.ParseJSONValue(Resp.ContentAsString()) as TJSONObject;
    if Result = nil then Result := TJSONObject.Create;
  finally
    HTTP.Free;
  end;
end;

function TPrometheusTool.DoQuery(const P: TPrometheusParams): TJSONObject;
var
  URL: string;
begin
  if Trim(P.Query) = '' then raise Exception.Create('"query" required');
  URL := GetBase(P) + '/query?query=' + TNetEncoding.URL.Encode(Trim(P.Query));
  if Trim(P.Time)    <> '' then URL := URL + '&time='    + TNetEncoding.URL.Encode(Trim(P.Time));
  if Trim(P.Timeout) <> '' then URL := URL + '&timeout=' + TNetEncoding.URL.Encode(Trim(P.Timeout));
  Result := ApiGet(URL, GetAuth(P));
end;

function TPrometheusTool.DoQueryRange(const P: TPrometheusParams): TJSONObject;
var
  URL, St: string;
begin
  if Trim(P.Query) = '' then raise Exception.Create('"query" required');
  if Trim(P.Start) = '' then raise Exception.Create('"start" required');
  if Trim(P.End_)  = '' then raise Exception.Create('"end" required');
  St := Trim(P.Step); if St = '' then St := '15s';
  URL := GetBase(P) + '/query_range' +
    '?query=' + TNetEncoding.URL.Encode(Trim(P.Query)) +
    '&start=' + TNetEncoding.URL.Encode(Trim(P.Start)) +
    '&end='   + TNetEncoding.URL.Encode(Trim(P.End_)) +
    '&step='  + TNetEncoding.URL.Encode(St);
  if Trim(P.Timeout) <> '' then URL := URL + '&timeout=' + TNetEncoding.URL.Encode(Trim(P.Timeout));
  Result := ApiGet(URL, GetAuth(P));
end;

function TPrometheusTool.DoLabels(const P: TPrometheusParams): TJSONObject;
var
  URL: string;
begin
  URL := GetBase(P) + '/labels';
  if Trim(P.Match) <> '' then URL := URL + '?match[]=' + TNetEncoding.URL.Encode(Trim(P.Match));
  Result := ApiGet(URL, GetAuth(P));
end;

function TPrometheusTool.DoLabelValues(const P: TPrometheusParams): TJSONObject;
var
  URL: string;
begin
  if Trim(P.LabelName) = '' then raise Exception.Create('"label" required for label_values');
  URL := GetBase(P) + '/label/' + TNetEncoding.URL.Encode(Trim(P.LabelName)) + '/values';
  if Trim(P.Match) <> '' then URL := URL + '?match[]=' + TNetEncoding.URL.Encode(Trim(P.Match));
  Result := ApiGet(URL, GetAuth(P));
end;

function TPrometheusTool.DoSeries(const P: TPrometheusParams): TJSONObject;
var
  URL: string;
begin
  if Trim(P.Match) = '' then raise Exception.Create('"match" required for series');
  URL := GetBase(P) + '/series?match[]=' + TNetEncoding.URL.Encode(Trim(P.Match));
  if Trim(P.Start) <> '' then URL := URL + '&start=' + TNetEncoding.URL.Encode(Trim(P.Start));
  if Trim(P.End_)  <> '' then URL := URL + '&end='   + TNetEncoding.URL.Encode(Trim(P.End_));
  Result := ApiGet(URL, GetAuth(P));
end;

function TPrometheusTool.DoTargets(const P: TPrometheusParams): TJSONObject;
begin
  Result := ApiGet(GetBase(P) + '/targets', GetAuth(P));
end;

function TPrometheusTool.DoAlerts(const P: TPrometheusParams): TJSONObject;
begin
  Result := ApiGet(GetBase(P) + '/alerts', GetAuth(P));
end;

function TPrometheusTool.DoRules(const P: TPrometheusParams): TJSONObject;
begin
  Result := ApiGet(GetBase(P) + '/rules', GetAuth(P));
end;

function TPrometheusTool.DoMetadata(const P: TPrometheusParams): TJSONObject;
var
  URL: string;
begin
  URL := GetBase(P) + '/metadata';
  if Trim(P.Query) <> '' then URL := URL + '?metric=' + TNetEncoding.URL.Encode(Trim(P.Query));
  Result := ApiGet(URL, GetAuth(P));
end;

function TPrometheusTool.DoTsdbStatus(const P: TPrometheusParams): TJSONObject;
begin
  Result := ApiGet(GetBase(P) + '/status/tsdb', GetAuth(P));
end;

function TPrometheusTool.ExecuteWithParams(const AParams: TPrometheusParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op: string;
  R:  TJSONObject;
begin
  try
    Op := LowerCase(Trim(AParams.Operation));
    if Op = '' then raise Exception.Create('"operation" is required');

    if      Op = 'query'        then R := DoQuery(AParams)
    else if Op = 'query_range'  then R := DoQueryRange(AParams)
    else if Op = 'labels'       then R := DoLabels(AParams)
    else if Op = 'label_values' then R := DoLabelValues(AParams)
    else if Op = 'series'       then R := DoSeries(AParams)
    else if Op = 'targets'      then R := DoTargets(AParams)
    else if Op = 'alerts'       then R := DoAlerts(AParams)
    else if Op = 'rules'        then R := DoRules(AParams)
    else if Op = 'metadata'     then R := DoMetadata(AParams)
    else if Op = 'tsdb_status'  then R := DoTsdbStatus(AParams)
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
  AServer.RegisterTool('mcp-prometheus',
    function: IAiMCPTool
    begin
      Result := TPrometheusTool.Create;
    end);
  WriteLn(ErrOutput, '[MCPService]   + mcp-prometheus');
end;

end.
