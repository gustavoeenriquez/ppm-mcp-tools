unit MCPTool.ContaClient;

(*
  MCPTool.ContaClient  -  Shared ConServer client for mcp-conta / mcp-conta-query

  ConServer is the Delphi DataSnap REST server of the PascalAI accounting
  system (Colombia). All endpoints hang from:
    <base>/datasnap/rest/TConServerMethods/CON_<Method>

  Conventions:
    - Every public method has the uniform signature (Params: String): String,
      where both sides are JSON. Some catalog methods take no parameter.
    - GET: the JSON travels URL-encoded as a single path segment:
        GET /CON_GetPlanCuentas/%7B%22incluir_inactivas%22%3Afalse%7D
    - For large payloads (URL > ~4000 chars) we switch to POST with the
      DataSnap body convention {"_parameters":["<json>"]}.
    - Every response is wrapped in {"result":[ <value> ]}; result[0] is a
      JSON-encoded string that we parse into the real payload.
    - Auth: HTTP Basic on every request. The credential is
        base64("login,nit_empresa:sha256hex(password)")
      i.e. user = "login,nit" and password = the SHA-256 hex of the plain
      password. Stateless: no login endpoint, no token.

  Credential:
    - stdio  -> the CONTA_* environment variables below.
    - http/sse -> the caller's Authorization header, relayed verbatim.
    The model never supplies it: it is not a tool parameter.

  Tenant (nit_empresa) vs credential — no son lo mismo:
    El nit viaja DENTRO del usuario de Basic ("login,nit"), asi que a primera
    vista parece credencial. No lo es: es un SELECTOR DE ALCANCE. ConServer
    autentica exigiendo una fila de con_usuarios con ese nit_empresa exacto
    (DSAuthenticationManager1UserAuthenticate), cuya PK es (nit_empresa, login).
    Pedir otro nit solo funciona si el usuario TIENE cuenta en ese tenant; con
    cualquier otro la peticion vuelve 401. Por eso ANitOverride si puede venir
    del modelo — hace falta para llevar dos empresas — mientras el login y la
    contrasena siguen siendo cosa del transporte: una clave en un argumento de
    tool acabaria en la conversacion, en la sesion en disco y en el historial.

  Configuration via environment variables:
    CONTA_URL              Base URL (default: https://conta.gustavoenriquez.com)
    CONTA_LOGIN            User login
    CONTA_NIT              Company NIT (tenant)
    CONTA_PASSWORD         Plain password (hashed in-process with SHA-256)
    CONTA_PASSWORD_SHA256  Already-hashed password (takes precedence)

  Author: Gustavo Enriquez  -  PascalAI
*)

interface

uses
  System.SysUtils,
  System.JSON;

type
  EContaError = class(Exception);

/// Base URL from CONTA_URL (no trailing slash).
function ContaBaseUrl: string;

/// Basic auth header value built from the CONTA_* environment variables.
/// Used only in stdio mode (one developer, one machine, own credentials).
///
/// ANitOverride, cuando no esta vacio, reemplaza a CONTA_NIT: es como se
/// trabajan varias empresas con una sola credencial. El login y el hash NO se
/// pueden sustituir por aqui a proposito (ver la nota del encabezado).
function ContaAuthValue(const ANitOverride: string = ''): string;

/// Invoke CON_<AMethod> with AParamsJson ('' = method without parameters).
///
/// AAuthHeader, when not empty, is used VERBATIM as the Authorization header.
/// That is the http/sse path: the MCP server relays the caller's credential
/// without parsing, storing or logging it. Empty -> falls back to the env vars.
///
/// There is deliberately no way for the model to supply a credential: it is a
/// transport concern, set by the runtime, invisible to the model.
///
/// ANitOverride si puede venir del modelo (empresa sobre la que operar) y solo
/// tiene efecto en el camino stdio: si llega un AAuthHeader, ese header manda
/// entero — el nit ya viene dentro y reescribirlo seria alterar la credencial
/// del llamante.
/// Returns the parsed payload (caller frees).
function ContaCall(const AMethod, AParamsJson: string;
  const AAuthHeader: string = ''; const ANitOverride: string = ''): TJSONValue;

implementation

uses
  System.Classes,
  System.Hash,
  System.Net.HttpClient,
  System.Net.URLClient,
  System.NetEncoding;

const
  DS_PATH = '/datasnap/rest/TConServerMethods/';
  MAX_GET_URL = 4000;

function ContaBaseUrl: string;
begin
  Result := Trim(GetEnvironmentVariable('CONTA_URL'));
  if Result = '' then
    Result := 'https://conta.gustavoenriquez.com';
  while (Result <> '') and (Result[Length(Result)] = '/') do
    Delete(Result, Length(Result), 1);
end;

function ContaAuthValue(const ANitOverride: string): string;
var
  Login, Nit, Hash: string;
begin
  Login := Trim(GetEnvironmentVariable('CONTA_LOGIN'));
  Nit   := Trim(ANitOverride);
  if Nit = '' then
    Nit := Trim(GetEnvironmentVariable('CONTA_NIT'));
  Hash  := LowerCase(Trim(GetEnvironmentVariable('CONTA_PASSWORD_SHA256')));

  if Hash = '' then
  begin
    if GetEnvironmentVariable('CONTA_PASSWORD') = '' then
      raise EContaError.Create(
        'Missing credentials. In stdio mode set CONTA_LOGIN, CONTA_NIT and ' +
        'CONTA_PASSWORD (or CONTA_PASSWORD_SHA256). In http/sse mode the ' +
        'caller must send an Authorization header.');
    Hash := LowerCase(THashSHA2.GetHashString(
      GetEnvironmentVariable('CONTA_PASSWORD'), THashSHA2.TSHA2Version.SHA256));
  end;

  if (Login = '') or (Nit = '') then
    raise EContaError.Create(
      'Missing credentials: set CONTA_LOGIN and CONTA_NIT environment ' +
      'variables (CONTA_NIT can be replaced per call with the "nit" argument, ' +
      'but the login always comes from the environment).');

  Result := 'Basic ' + TNetEncoding.Base64.Encode(Login + ',' + Nit + ':' + Hash)
    .Replace(#13, '').Replace(#10, '');
end;

// Parses {"result":[<value>]}; result[0] is normally a JSON-encoded string.
function UnwrapResult(const ARaw: string): TJSONValue;
var
  J, Res, Inner: TJSONValue;
  Arr: TJSONArray;
begin
  J := TJSONObject.ParseJSONValue(ARaw);
  try
    if (J is TJSONObject) and
       TJSONObject(J).TryGetValue<TJSONArray>('result', Arr) and (Arr.Count > 0) then
    begin
      Res := Arr.Items[0];
      if Res is TJSONString then
      begin
        Inner := TJSONObject.ParseJSONValue(TJSONString(Res).Value);
        if Inner <> nil then
          Exit(Inner);
        // not JSON: surface the raw string
        Result := TJSONObject.Create;
        TJSONObject(Result).AddPair('raw', TJSONString.Create(TJSONString(Res).Value));
        Exit;
      end;
      Exit(Res.Clone as TJSONValue);
    end;

    if J is TJSONObject then
      Exit(J.Clone as TJSONValue);

    Result := TJSONObject.Create;
    TJSONObject(Result).AddPair('raw', TJSONString.Create(ARaw));
  finally
    J.Free;
  end;
end;

function ContaCall(const AMethod, AParamsJson, AAuthHeader,
  ANitOverride: string): TJSONValue;
var
  HTTP:   THTTPClient;
  Stream: TStringStream;
  Resp:   IHTTPResponse;
  Url, Raw, Auth: string;
  Body:   TJSONObject;
  Params: TJSONArray;
begin
  // El header del llamante gana. El MCP no lo interpreta ni lo guarda: lo
  // reenvia tal cual, porque el formato que espera ConServer es el mismo.
  // Ahi el nit ya viaja dentro del header, asi que ANitOverride se ignora: no
  // se reescribe la credencial de nadie.
  if Trim(AAuthHeader) <> '' then
    Auth := Trim(AAuthHeader)
  else
    Auth := ContaAuthValue(ANitOverride);
  Url  := ContaBaseUrl + DS_PATH + AMethod;
  if Trim(AParamsJson) <> '' then
    Url := Url + '/' + TNetEncoding.URL.Encode(Trim(AParamsJson));

  HTTP := THTTPClient.Create;
  try
    HTTP.ConnectionTimeout := 15000;
    HTTP.ResponseTimeout   := 120000;

    if Length(Url) <= MAX_GET_URL then
    begin
      Resp := HTTP.Get(Url, nil, [TNameValuePair.Create('Authorization', Auth)]);
      Raw  := Resp.ContentAsString(TEncoding.UTF8);
    end
    else
    begin
      // large payload: DataSnap POST convention {"_parameters":[<json-string>]}
      Body := TJSONObject.Create;
      try
        Params := TJSONArray.Create;
        Params.Add(Trim(AParamsJson));
        Body.AddPair('_parameters', Params);
        Stream := TStringStream.Create(Body.ToJSON, TEncoding.UTF8);
        try
          Resp := HTTP.Post(ContaBaseUrl + DS_PATH + AMethod, Stream, nil,
            [TNameValuePair.Create('Authorization', Auth),
             TNameValuePair.Create('Content-Type', 'application/json')]);
          Raw := Resp.ContentAsString(TEncoding.UTF8);
        finally
          Stream.Free;
        end;
      finally
        Body.Free;
      end;
    end;

    if (Resp.StatusCode = 401) or (Resp.StatusCode = 403) then
      raise EContaError.CreateFmt(
        'ConServer rechazo la credencial (HTTP %d). En stdio revise ' +
        'CONTA_LOGIN / CONTA_NIT / CONTA_PASSWORD; en http/sse el token ' +
        'puede estar vencido, revocado o sin alcance para esta operacion.',
        [Resp.StatusCode]);
    if (Resp.StatusCode >= 400) and (Trim(Raw) = '') then
      raise EContaError.CreateFmt('ConServer %s failed: HTTP %d',
        [AMethod, Resp.StatusCode]);
  finally
    HTTP.Free;
  end;

  Result := UnwrapResult(Raw);
end;

end.
