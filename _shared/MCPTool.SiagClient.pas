unit MCPTool.SiagClient;

(*
  MCPTool.SiagClient  -  Shared SIAG backend client for mcp-siag / mcp-siag-query

  SIAG is a Delphi DataSnap REST server. All endpoints hang from:
    <base>/datasnap/rest/TSigServerMethods/<Method>

  Conventions:
    - POST body is always {"_parameters":[ ... ]} in the exact order of the
      Pascal method signature.
    - GET parameters travel as ordered path segments: /Method/<p1>/<p2>
    - Every response is wrapped in {"result":[ <value> ]} - the real payload
      is result[0].
    - Auth: the JWT token is NOT sent as an Authorization header; it is passed
      as an explicit parameter (last path segment on GET, an element of
      _parameters on POST; for ExecuteDSLAuth it is the FIRST parameter).

  Configuration via environment variables:
    SIAG_URL       Base URL of the server (default: http://localhost:8080)
    SIAG_EMAIL     User email for auto-login
    SIAG_PASSWORD  User password for auto-login
    SIAG_TENANT    Tenant slug ("empresa") for auto-login

  The token obtained by auto-login is cached in-process (tokens last 24h;
  we treat the cache as valid for 23h and re-login on expiry or on a
  "No autorizado" response).

  Author: Gustavo Enriquez  -  PascalAI
*)

interface

uses
  System.SysUtils,
  System.JSON;

type
  ESiagError = class(Exception);

/// Base URL from SIAG_URL (no trailing slash), default http://localhost:8080
function SiagBaseUrl: string;

/// Login and return the JWT token. Raises ESiagError on failure.
function SiagLogin(const AEmail, APassword, ATenant: string): string;

/// Return a cached token, logging in via SIAG_EMAIL/SIAG_PASSWORD/SIAG_TENANT
/// if needed. Raises ESiagError if credentials are missing or login fails.
function SiagEnsureToken: string;

/// Drop the cached token so the next call re-logs in.
procedure SiagInvalidateToken;

/// GET Health. Returns result[0] (caller frees).
function SiagHealth: TJSONObject;

/// GET GetMe/<token>. Returns result[0] (caller frees).
function SiagGetMe(const AToken: string): TJSONObject;

/// POST ExecuteDSLAuth with [token, dsl]. Returns result[0] (caller frees).
function SiagExecuteDSL(const AToken, ADSL: string): TJSONObject;

/// Low-level POST helper. AParams ownership is transferred to this function.
/// Returns a clone of result[0] (caller frees). Raises ESiagError on transport
/// or non-JSON error responses.
function SiagDsPost(const AMethod: string; AParams: TJSONArray): TJSONValue;

/// Low-level GET helper. Returns a clone of result[0] (caller frees).
function SiagDsGet(const AMethod: string; const ASegments: array of string): TJSONValue;

implementation

uses
  System.Classes,
  System.Net.HttpClient,
  System.Net.URLClient,
  System.NetEncoding,
  System.DateUtils;

const
  DS_PATH = '/datasnap/rest/TSigServerMethods/';

var
  GCachedToken:   string = '';
  GTokenExpires:  TDateTime = 0;   // 0 = no cached token

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

function SiagBaseUrl: string;
begin
  Result := Trim(GetEnvironmentVariable('SIAG_URL'));
  if Result = '' then
    Result := 'http://localhost:8080';
  while (Result <> '') and (Result[Length(Result)] = '/') do
    Delete(Result, Length(Result), 1);
end;

// ---------------------------------------------------------------------------
// HTTP + response envelope
// ---------------------------------------------------------------------------

// Parses a {"result":[value]} envelope and returns a clone of result[0].
// If the body is not the expected envelope, wraps the raw text in
// {"raw": "..."} so the caller always receives a TJSONValue.
function UnwrapResult(const ARaw: string): TJSONValue;
var
  J:   TJSONValue;
  Obj: TJSONObject;
  Arr: TJSONArray;
  Res: TJSONValue;
begin
  J := TJSONObject.ParseJSONValue(ARaw);
  try
    if (J is TJSONObject) then
    begin
      Obj := J as TJSONObject;
      if Obj.TryGetValue<TJSONArray>('result', Arr) and (Arr.Count > 0) then
      begin
        Res := Arr.Items[0];
        Exit(Res.Clone as TJSONValue);
      end;
      // No "result" wrapper: return the object itself (e.g. some error shapes)
      Exit(Obj.Clone as TJSONValue);
    end;

    // Not a JSON object: surface as raw text
    Result := TJSONObject.Create;
    (Result as TJSONObject).AddPair('raw', TJSONString.Create(ARaw));
  finally
    J.Free;
  end;
end;

function HttpPost(const AUrl, ABody: string): string;
var
  HTTP:   THTTPClient;
  Stream: TStringStream;
  Resp:   IHTTPResponse;
begin
  HTTP   := THTTPClient.Create;
  Stream := TStringStream.Create(ABody, TEncoding.UTF8);
  try
    Resp := HTTP.Post(AUrl, Stream, nil,
      [TNameValuePair.Create('Content-Type', 'application/json')]);
    Result := Resp.ContentAsString(TEncoding.UTF8);
    if (Resp.StatusCode >= 400) and (Trim(Result) = '') then
      raise ESiagError.CreateFmt('SIAG POST %s failed: HTTP %d',
        [AUrl, Resp.StatusCode]);
  finally
    Stream.Free;
    HTTP.Free;
  end;
end;

function HttpGet(const AUrl: string): string;
var
  HTTP: THTTPClient;
  Resp: IHTTPResponse;
begin
  HTTP := THTTPClient.Create;
  try
    Resp := HTTP.Get(AUrl);
    Result := Resp.ContentAsString(TEncoding.UTF8);
    if (Resp.StatusCode >= 400) and (Trim(Result) = '') then
      raise ESiagError.CreateFmt('SIAG GET %s failed: HTTP %d',
        [AUrl, Resp.StatusCode]);
  finally
    HTTP.Free;
  end;
end;

// ---------------------------------------------------------------------------
// Low-level DataSnap helpers
// ---------------------------------------------------------------------------

function SiagDsPost(const AMethod: string; AParams: TJSONArray): TJSONValue;
var
  Body: TJSONObject;
  Raw:  string;
begin
  Body := TJSONObject.Create;
  try
    Body.AddPair('_parameters', AParams);  // takes ownership of AParams
    Raw := HttpPost(SiagBaseUrl + DS_PATH + AMethod, Body.ToJSON);
  finally
    Body.Free;
  end;
  Result := UnwrapResult(Raw);
end;

function SiagDsGet(const AMethod: string; const ASegments: array of string): TJSONValue;
var
  Url: string;
  i:   Integer;
begin
  Url := SiagBaseUrl + DS_PATH + AMethod;
  for i := 0 to High(ASegments) do
    Url := Url + '/' + TNetEncoding.URL.Encode(ASegments[i]);
  Result := UnwrapResult(HttpGet(Url));
end;

// ---------------------------------------------------------------------------
// Typed endpoints
// ---------------------------------------------------------------------------

function AsObject(V: TJSONValue): TJSONObject;
begin
  if V is TJSONObject then
    Result := V as TJSONObject
  else
  begin
    Result := TJSONObject.Create;
    Result.AddPair('value', V);  // adopt V
  end;
end;

function SiagHealth: TJSONObject;
begin
  Result := AsObject(SiagDsGet('Health', []));
end;

function SiagGetMe(const AToken: string): TJSONObject;
begin
  Result := AsObject(SiagDsGet('GetMe', [AToken]));
end;

function SiagExecuteDSL(const AToken, ADSL: string): TJSONObject;
var
  Arr: TJSONArray;
begin
  Arr := TJSONArray.Create;
  Arr.Add(AToken);
  Arr.Add(ADSL);
  Result := AsObject(SiagDsPost('ExecuteDSLAuth', Arr));
end;

function SiagLogin(const AEmail, APassword, ATenant: string): string;
var
  Arr:   TJSONArray;
  V:     TJSONValue;
  Obj:   TJSONObject;
  Tok:   string;
  ErrMsg: string;
begin
  Arr := TJSONArray.Create;
  Arr.Add(AEmail);
  Arr.Add(APassword);
  Arr.Add(ATenant);
  V := SiagDsPost('Login', Arr);
  try
    if not (V is TJSONObject) then
      raise ESiagError.Create('SIAG Login: unexpected response');
    Obj := V as TJSONObject;
    if Obj.TryGetValue<string>('error', ErrMsg) then
      raise ESiagError.Create('SIAG Login failed: ' + ErrMsg);
    if not Obj.TryGetValue<string>('token', Tok) then
      raise ESiagError.Create('SIAG Login: no token in response');
    Result := Tok;
  finally
    V.Free;
  end;
end;

procedure SiagInvalidateToken;
begin
  GCachedToken  := '';
  GTokenExpires := 0;
end;

function SiagEnsureToken: string;
var
  Email, Pass, Tenant: string;
begin
  if (GCachedToken <> '') and (GTokenExpires > Now) then
    Exit(GCachedToken);

  Email  := Trim(GetEnvironmentVariable('SIAG_EMAIL'));
  Pass   := GetEnvironmentVariable('SIAG_PASSWORD');
  Tenant := Trim(GetEnvironmentVariable('SIAG_TENANT'));

  if (Email = '') or (Pass = '') or (Tenant = '') then
    raise ESiagError.Create(
      'Missing credentials: set SIAG_EMAIL, SIAG_PASSWORD and SIAG_TENANT ' +
      'environment variables (and SIAG_URL if the server is not on localhost:8080).');

  GCachedToken  := SiagLogin(Email, Pass, Tenant);
  GTokenExpires := IncHour(Now, 23);  // server tokens live 24h; refresh early
  Result := GCachedToken;
end;

end.
