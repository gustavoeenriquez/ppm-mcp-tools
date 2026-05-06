unit MCPTool.Kubernetes;

{
  MCPTool.Kubernetes  ·  mcp-kubernetes  (port 8635)
  Kubernetes cluster management via the Kubernetes REST API.

  Auth params: apiServer, token (Bearer), namespace (default: default),
               skipTLS (boolean — accepted but THTTPClient proceeds regardless).

  Operations:
    list_pods         - list pods in a namespace
    get_pod           - get pod details
    delete_pod        - delete a pod
    list_deployments  - list deployments in a namespace
    get_deployment    - get deployment details
    scale_deployment  - scale deployment replicas
    list_services     - list services in a namespace
    list_namespaces   - list all namespaces
    get_events        - list events in a namespace
    apply             - apply a JSON body as a resource (POST)
}

interface

uses
  uMakerAi.MCPServer.Core,
  System.JSON;

type
  TKubernetesParams = class
  private
    FOperation:     string;
    FApiServer:     string;
    FToken:         string;
    FNamespace:     string;
    FSkipTLS:       Boolean;
    FName:          string;
    FBody:          string;
    FReplicas:      Integer;
    FLabelSelector: string;
  public
    constructor Create;

    [AiMCPSchemaDescription('Operation: list_pods, get_pod, delete_pod, list_deployments, get_deployment, scale_deployment, list_services, list_namespaces, get_events, apply')]
    property Operation:     string  read FOperation     write FOperation;

    [AiMCPSchemaDescription('Kubernetes API server URL (e.g. https://k8s.example.com:6443)')]
    property ApiServer:     string  read FApiServer     write FApiServer;

    [AiMCPSchemaDescription('Bearer token for authentication')]
    property Token:         string  read FToken         write FToken;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Namespace to operate in (default: default)')]
    property Namespace:     string  read FNamespace     write FNamespace;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Skip TLS certificate verification (default: false; note: not enforced by THTTPClient)')]
    property SkipTLS:       Boolean read FSkipTLS       write FSkipTLS;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Resource name (for get_pod, delete_pod, get_deployment, scale_deployment)')]
    property Name:          string  read FName          write FName;

    [AiMCPOptional]
    [AiMCPSchemaDescription('JSON body of the resource to apply (for apply operation)')]
    property Body:          string  read FBody          write FBody;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Number of replicas (for scale_deployment)')]
    property Replicas:      Integer read FReplicas      write FReplicas;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Label selector to filter resources (e.g. app=myapp)')]
    property LabelSelector: string  read FLabelSelector write FLabelSelector;
  end;

  TKubernetesTool = class(TAiMCPToolBase<TKubernetesParams>)
  private
    function GetNS(const P: TKubernetesParams): string;
    function GetBase(const P: TKubernetesParams): string;
    function ApiGet(const P: TKubernetesParams; const Path: string): string;
    function ApiDelete(const P: TKubernetesParams; const Path: string): string;
    function ApiPost(const P: TKubernetesParams; const Path, Body: string): string;
    function ApiPatch(const P: TKubernetesParams; const Path, Body: string): string;
    function ParseResponse(const Raw: string): TJSONObject;
    function DoListPods(const P: TKubernetesParams): TJSONObject;
    function DoGetPod(const P: TKubernetesParams): TJSONObject;
    function DoDeletePod(const P: TKubernetesParams): TJSONObject;
    function DoListDeployments(const P: TKubernetesParams): TJSONObject;
    function DoGetDeployment(const P: TKubernetesParams): TJSONObject;
    function DoScaleDeployment(const P: TKubernetesParams): TJSONObject;
    function DoListServices(const P: TKubernetesParams): TJSONObject;
    function DoListNamespaces(const P: TKubernetesParams): TJSONObject;
    function DoGetEvents(const P: TKubernetesParams): TJSONObject;
    function DoApply(const P: TKubernetesParams): TJSONObject;
  protected
    function ExecuteWithParams(const AParams: TKubernetesParams;
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

{ TKubernetesParams }

constructor TKubernetesParams.Create;
begin
  inherited;
  FNamespace := 'default';
  FSkipTLS   := False;
  FReplicas  := -1;
end;

{ TKubernetesTool }

function TKubernetesTool.GetNS(const P: TKubernetesParams): string;
begin
  Result := Trim(P.Namespace);
  if Result = '' then Result := 'default';
end;

function TKubernetesTool.GetBase(const P: TKubernetesParams): string;
begin
  Result := Trim(P.ApiServer);
  if Result = '' then raise Exception.Create('"apiServer" is required');
  if Result.EndsWith('/') then
    Result := Result.Substring(0, Length(Result) - 1);
end;

function TKubernetesTool.ApiGet(const P: TKubernetesParams; const Path: string): string;
var
  HTTP:  THTTPClient;
  Resp:  IHTTPResponse;
  URL:   string;
  Tok:   string;
begin
  URL  := GetBase(P) + Path;
  Tok  := Trim(P.Token);
  HTTP := THTTPClient.Create;
  try
    HTTP.ConnectionTimeout := 10000;
    HTTP.ResponseTimeout   := 30000;
    if Tok <> '' then
      Resp := HTTP.Get(URL, nil,
        [TNameValuePair.Create('Authorization', 'Bearer ' + Tok),
         TNameValuePair.Create('Accept', 'application/json')])
    else
      Resp := HTTP.Get(URL, nil,
        [TNameValuePair.Create('Accept', 'application/json')]);
    Result := Resp.ContentAsString(TEncoding.UTF8);
    if Resp.StatusCode >= 400 then
      raise Exception.CreateFmt('Kubernetes API HTTP %d: %s',
        [Resp.StatusCode, Result.Substring(0, 400)]);
  finally
    HTTP.Free;
  end;
end;

function TKubernetesTool.ApiDelete(const P: TKubernetesParams; const Path: string): string;
var
  HTTP:  THTTPClient;
  Resp:  IHTTPResponse;
  URL:   string;
  Tok:   string;
begin
  URL  := GetBase(P) + Path;
  Tok  := Trim(P.Token);
  HTTP := THTTPClient.Create;
  try
    HTTP.ConnectionTimeout := 10000;
    HTTP.ResponseTimeout   := 30000;
    if Tok <> '' then
      Resp := HTTP.Delete(URL, nil,
        [TNameValuePair.Create('Authorization', 'Bearer ' + Tok),
         TNameValuePair.Create('Accept', 'application/json')])
    else
      Resp := HTTP.Delete(URL, nil,
        [TNameValuePair.Create('Accept', 'application/json')]);
    Result := Resp.ContentAsString(TEncoding.UTF8);
    if Resp.StatusCode >= 400 then
      raise Exception.CreateFmt('Kubernetes API HTTP %d: %s',
        [Resp.StatusCode, Result.Substring(0, 400)]);
  finally
    HTTP.Free;
  end;
end;

function TKubernetesTool.ApiPost(const P: TKubernetesParams; const Path, Body: string): string;
var
  HTTP:   THTTPClient;
  Resp:   IHTTPResponse;
  Stream: TStringStream;
  URL:    string;
  Tok:    string;
begin
  URL    := GetBase(P) + Path;
  Tok    := Trim(P.Token);
  HTTP   := THTTPClient.Create;
  Stream := TStringStream.Create(Body, TEncoding.UTF8);
  try
    HTTP.ConnectionTimeout := 10000;
    HTTP.ResponseTimeout   := 60000;
    if Tok <> '' then
      Resp := HTTP.Post(URL, Stream, nil,
        [TNameValuePair.Create('Authorization', 'Bearer ' + Tok),
         TNameValuePair.Create('Content-Type', 'application/json'),
         TNameValuePair.Create('Accept', 'application/json')])
    else
      Resp := HTTP.Post(URL, Stream, nil,
        [TNameValuePair.Create('Content-Type', 'application/json'),
         TNameValuePair.Create('Accept', 'application/json')]);
    Result := Resp.ContentAsString(TEncoding.UTF8);
    if Resp.StatusCode >= 400 then
      raise Exception.CreateFmt('Kubernetes API HTTP %d: %s',
        [Resp.StatusCode, Result.Substring(0, 400)]);
  finally
    Stream.Free;
    HTTP.Free;
  end;
end;

function TKubernetesTool.ApiPatch(const P: TKubernetesParams; const Path, Body: string): string;
var
  HTTP:   THTTPClient;
  Resp:   IHTTPResponse;
  Stream: TStringStream;
  URL:    string;
  Tok:    string;
begin
  URL    := GetBase(P) + Path;
  Tok    := Trim(P.Token);
  HTTP   := THTTPClient.Create;
  Stream := TStringStream.Create(Body, TEncoding.UTF8);
  try
    HTTP.ConnectionTimeout := 10000;
    HTTP.ResponseTimeout   := 60000;
    if Tok <> '' then
      Resp := HTTP.Patch(URL, Stream, nil,
        [TNameValuePair.Create('Authorization', 'Bearer ' + Tok),
         TNameValuePair.Create('Content-Type', 'application/merge-patch+json'),
         TNameValuePair.Create('Accept', 'application/json')])
    else
      Resp := HTTP.Patch(URL, Stream, nil,
        [TNameValuePair.Create('Content-Type', 'application/merge-patch+json'),
         TNameValuePair.Create('Accept', 'application/json')]);
    Result := Resp.ContentAsString(TEncoding.UTF8);
    if Resp.StatusCode >= 400 then
      raise Exception.CreateFmt('Kubernetes API HTTP %d: %s',
        [Resp.StatusCode, Result.Substring(0, 400)]);
  finally
    Stream.Free;
    HTTP.Free;
  end;
end;

function TKubernetesTool.ParseResponse(const Raw: string): TJSONObject;
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

function TKubernetesTool.DoListPods(const P: TKubernetesParams): TJSONObject;
var
  NS, Path, Sel, Raw: string;
begin
  NS   := GetNS(P);
  Path := '/api/v1/namespaces/' + NS + '/pods';
  Sel  := Trim(P.LabelSelector);
  if Sel <> '' then
    Path := Path + '?labelSelector=' + TNetEncoding.URL.EncodeQuery(Sel);
  Raw    := ApiGet(P, Path);
  Result := ParseResponse(Raw);
end;

function TKubernetesTool.DoGetPod(const P: TKubernetesParams): TJSONObject;
var
  NS, PodName, Raw: string;
begin
  NS      := GetNS(P);
  PodName := Trim(P.Name);
  if PodName = '' then raise Exception.Create('"name" is required for get_pod');
  Raw    := ApiGet(P, '/api/v1/namespaces/' + NS + '/pods/' + PodName);
  Result := ParseResponse(Raw);
end;

function TKubernetesTool.DoDeletePod(const P: TKubernetesParams): TJSONObject;
var
  NS, PodName, Raw: string;
begin
  NS      := GetNS(P);
  PodName := Trim(P.Name);
  if PodName = '' then raise Exception.Create('"name" is required for delete_pod');
  Raw    := ApiDelete(P, '/api/v1/namespaces/' + NS + '/pods/' + PodName);
  Result := ParseResponse(Raw);
end;

function TKubernetesTool.DoListDeployments(const P: TKubernetesParams): TJSONObject;
var
  NS, Path, Sel, Raw: string;
begin
  NS   := GetNS(P);
  Path := '/apis/apps/v1/namespaces/' + NS + '/deployments';
  Sel  := Trim(P.LabelSelector);
  if Sel <> '' then
    Path := Path + '?labelSelector=' + TNetEncoding.URL.EncodeQuery(Sel);
  Raw    := ApiGet(P, Path);
  Result := ParseResponse(Raw);
end;

function TKubernetesTool.DoGetDeployment(const P: TKubernetesParams): TJSONObject;
var
  NS, DepName, Raw: string;
begin
  NS      := GetNS(P);
  DepName := Trim(P.Name);
  if DepName = '' then raise Exception.Create('"name" is required for get_deployment');
  Raw    := ApiGet(P, '/apis/apps/v1/namespaces/' + NS + '/deployments/' + DepName);
  Result := ParseResponse(Raw);
end;

function TKubernetesTool.DoScaleDeployment(const P: TKubernetesParams): TJSONObject;
var
  NS, DepName, PatchBody, Raw: string;
  Rep: Integer;
begin
  NS      := GetNS(P);
  DepName := Trim(P.Name);
  if DepName = '' then raise Exception.Create('"name" is required for scale_deployment');
  Rep := P.Replicas;
  if Rep < 0 then raise Exception.Create('"replicas" must be >= 0 for scale_deployment');
  PatchBody := '{"spec":{"replicas":' + IntToStr(Rep) + '}}';
  Raw    := ApiPatch(P,
    '/apis/apps/v1/namespaces/' + NS + '/deployments/' + DepName + '/scale',
    PatchBody);
  Result := ParseResponse(Raw);
end;

function TKubernetesTool.DoListServices(const P: TKubernetesParams): TJSONObject;
var
  NS, Path, Sel, Raw: string;
begin
  NS   := GetNS(P);
  Path := '/api/v1/namespaces/' + NS + '/services';
  Sel  := Trim(P.LabelSelector);
  if Sel <> '' then
    Path := Path + '?labelSelector=' + TNetEncoding.URL.EncodeQuery(Sel);
  Raw    := ApiGet(P, Path);
  Result := ParseResponse(Raw);
end;

function TKubernetesTool.DoListNamespaces(const P: TKubernetesParams): TJSONObject;
var
  Raw: string;
begin
  Raw    := ApiGet(P, '/api/v1/namespaces');
  Result := ParseResponse(Raw);
end;

function TKubernetesTool.DoGetEvents(const P: TKubernetesParams): TJSONObject;
var
  NS, Path, Sel, Raw: string;
begin
  NS   := GetNS(P);
  Path := '/api/v1/namespaces/' + NS + '/events';
  Sel  := Trim(P.LabelSelector);
  if Sel <> '' then
    Path := Path + '?fieldSelector=' + TNetEncoding.URL.EncodeQuery(Sel);
  Raw    := ApiGet(P, Path);
  Result := ParseResponse(Raw);
end;

function TKubernetesTool.DoApply(const P: TKubernetesParams): TJSONObject;
var
  NS, Body, Raw: string;
  Parsed:        TJSONValue;
  JObj:          TJSONObject;
  ApiVersion:    string;
  Kind:          string;
  Path:          string;
begin
  NS   := GetNS(P);
  Body := Trim(P.Body);
  if Body = '' then raise Exception.Create('"body" is required for apply');

  // Determine endpoint from apiVersion + kind in the JSON body
  ApiVersion := '';
  Kind       := '';
  Parsed := TJSONObject.ParseJSONValue(Body);
  if Assigned(Parsed) then
  begin
    try
      if Parsed is TJSONObject then
      begin
        JObj       := Parsed as TJSONObject;
        ApiVersion := JObj.GetValue<string>('apiVersion', '');
        Kind       := LowerCase(JObj.GetValue<string>('kind', ''));
      end;
    finally
      Parsed.Free;
    end;
  end;

  // Map kind to REST path; default to core/v1 pods if unknown
  if (ApiVersion = 'apps/v1') and (Kind = 'deployment') then
    Path := '/apis/apps/v1/namespaces/' + NS + '/deployments'
  else if (ApiVersion = 'apps/v1') and (Kind = 'replicaset') then
    Path := '/apis/apps/v1/namespaces/' + NS + '/replicasets'
  else if (ApiVersion = 'apps/v1') and (Kind = 'statefulset') then
    Path := '/apis/apps/v1/namespaces/' + NS + '/statefulsets'
  else if (ApiVersion = 'apps/v1') and (Kind = 'daemonset') then
    Path := '/apis/apps/v1/namespaces/' + NS + '/daemonsets'
  else if Kind = 'service' then
    Path := '/api/v1/namespaces/' + NS + '/services'
  else if Kind = 'configmap' then
    Path := '/api/v1/namespaces/' + NS + '/configmaps'
  else if Kind = 'secret' then
    Path := '/api/v1/namespaces/' + NS + '/secrets'
  else if Kind = 'serviceaccount' then
    Path := '/api/v1/namespaces/' + NS + '/serviceaccounts'
  else
    Path := '/api/v1/namespaces/' + NS + '/pods';

  Raw    := ApiPost(P, Path, Body);
  Result := ParseResponse(Raw);
end;

function TKubernetesTool.ExecuteWithParams(const AParams: TKubernetesParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Op: string;
  R:  TJSONObject;
begin
  try
    Op := LowerCase(Trim(AParams.Operation));
    if Op = '' then raise Exception.Create('"operation" is required');

    if      Op = 'list_pods'        then R := DoListPods(AParams)
    else if Op = 'get_pod'          then R := DoGetPod(AParams)
    else if Op = 'delete_pod'       then R := DoDeletePod(AParams)
    else if Op = 'list_deployments' then R := DoListDeployments(AParams)
    else if Op = 'get_deployment'   then R := DoGetDeployment(AParams)
    else if Op = 'scale_deployment' then R := DoScaleDeployment(AParams)
    else if Op = 'list_services'    then R := DoListServices(AParams)
    else if Op = 'list_namespaces'  then R := DoListNamespaces(AParams)
    else if Op = 'get_events'       then R := DoGetEvents(AParams)
    else if Op = 'apply'            then R := DoApply(AParams)
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

constructor TKubernetesTool.Create;
begin
  inherited;
  FName        := 'mcp-kubernetes';
  FDescription :=
    'Kubernetes cluster management via the Kubernetes REST API. ' +
    'Auth params: apiServer (required, e.g. https://k8s.example.com:6443), ' +
    'token (Bearer token), namespace? (default: default), skipTLS? (accepted, not enforced). ' +
    'Operations: ' +
    'list_pods (params: namespace?, labelSelector?), ' +
    'get_pod (params: name, namespace?), ' +
    'delete_pod (params: name, namespace?), ' +
    'list_deployments (params: namespace?, labelSelector?), ' +
    'get_deployment (params: name, namespace?), ' +
    'scale_deployment (params: name, replicas, namespace?), ' +
    'list_services (params: namespace?, labelSelector?), ' +
    'list_namespaces, ' +
    'get_events (params: namespace?, labelSelector?), ' +
    'apply (params: body [JSON resource manifest], namespace?).';
end;

procedure RegisterTools(AServer: TAiMCPServer);
begin
  AServer.RegisterTool('mcp-kubernetes',
    function: IAiMCPTool
    begin
      Result := TKubernetesTool.Create;
    end);
  WriteLn(ErrOutput, '[MCPService]   + mcp-kubernetes');
end;

end.
