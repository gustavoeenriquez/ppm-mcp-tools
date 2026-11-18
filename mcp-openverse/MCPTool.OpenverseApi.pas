unit MCPTool.OpenverseApi;

{
  MCPTool.OpenverseApi - mcp-openverse

  Cliente HTTP de https://api.openverse.org/v1:
    - token OAuth2 client_credentials (OPENVERSE_CLIENT_ID / OPENVERSE_CLIENT_SECRET);
      sin ellas va como anonimo (20/min, 200/dia);
    - cache en memoria (LRU, 200 entradas) para no gastar la cuota;
    - guarda las ultimas cabeceras x-ratelimit-* para informar la cuota;
    - un 429 NO se reintenta: se devuelve un error con Retry-After;
    - descarga de archivos con tope de tamano.

  Nunca escribe el client_secret ni el token en errores ni en logs.
}

interface

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.SyncObjs,
  System.Generics.Collections,
  System.Net.HttpClient,
  System.Net.URLClient;

const
  OV_VERSION    = '0.1.0';
  OV_BASE       = 'https://api.openverse.org';
  OV_TTL_SEARCH = 1 / 24;   // 1 hora (en dias)
  OV_TTL_DETAIL = 1;        // 24 horas
  OV_CACHE_MAX  = 200;

type
  EOpenverse = class(Exception);

  TOvCacheEntry = record
    Body: string;
    Expires: TDateTime;
  end;

  TOpenverseApi = class
  private
    FLock: TCriticalSection;
    FCache: TDictionary<string, TOvCacheEntry>;
    FOrder: TList<string>;          // de menos a mas reciente
    FToken: string;
    FTokenExpires: TDateTime;
    FQuota: TJSONObject;
    FClientId: string;
    FClientSecret: string;
    function NewClient: THTTPClient;
    function UserAgent: string;
    function CacheKey(const APathAndQuery: string): string;
    function CacheGet(const AKey: string; out ABody: string): Boolean;
    procedure CachePut(const AKey, ABody: string; AExpires: TDateTime);
    procedure SaveQuota(const AResp: IHTTPResponse);
    function AccessToken(AForce: Boolean): string;
    function Request(const APathAndQuery: string): string;
  public
    constructor Create;
    destructor Destroy; override;
    class function Instance: TOpenverseApi;

    function Authenticated: Boolean;
    // GET a la API; el llamador libera el resultado. ATtl en dias (0 = sin cache).
    function GetJSON(const APathAndQuery: string; ATtl: Double): TJSONValue;
    // Copia de las ultimas cabeceras x-ratelimit-* (el llamador libera)
    function QuotaJSON: TJSONObject;
    // Descarga AUrl (solo https) a ADest. Escribe primero ADest.part y lo
    // renombra al terminar. Devuelve los bytes escritos.
    function DownloadFile(const AUrl, ADest: string; AMaxBytes: Int64): Int64;
  end;

// Percent-encoding RFC 3986 (UTF-8) para valores de query
function OvUrlEncode(const S: string): string;
// 'audio' -> 'audio', 'image' -> 'images'; cualquier otro valor: excepcion
function OvMediaPath(const AMedia: string): string;
// Los ids de Openverse son UUID: se validan antes de meterlos en una URL
function OvValidId(const AId: string): Boolean;

implementation

uses
  System.DateUtils,
  System.IOUtils;

var
  GApi: TOpenverseApi = nil;

function OvUrlEncode(const S: string): string;
const
  HEX = '0123456789ABCDEF';
var
  B: TBytes;
  I: Integer;
  C: Byte;
begin
  Result := '';
  B := TEncoding.UTF8.GetBytes(S);
  for I := 0 to High(B) do
  begin
    C := B[I];
    if (C in [Ord('A')..Ord('Z'), Ord('a')..Ord('z'), Ord('0')..Ord('9')]) or
       (C in [Ord('-'), Ord('_'), Ord('.'), Ord('~')]) then
      Result := Result + Char(C)
    else
      Result := Result + '%' + HEX[(C shr 4) + 1] + HEX[(C and $F) + 1];
  end;
end;

function OvMediaPath(const AMedia: string): string;
var
  M: string;
begin
  M := LowerCase(Trim(AMedia));
  if M = 'audio' then
    Result := 'audio'
  else if (M = 'image') or (M = 'images') then
    Result := 'images'
  else
    raise EOpenverse.Create('"media" must be "audio" or "image"');
end;

function OvValidId(const AId: string): Boolean;
var
  Ch: Char;
begin
  Result := Length(AId) = 36;
  if not Result then Exit;
  for Ch in AId do
    if not CharInSet(Ch, ['0'..'9', 'a'..'f', 'A'..'F', '-']) then
      Exit(False);
end;

{ TOpenverseApi }

constructor TOpenverseApi.Create;
begin
  inherited Create;
  FLock  := TCriticalSection.Create;
  FCache := TDictionary<string, TOvCacheEntry>.Create;
  FOrder := TList<string>.Create;
  FQuota := TJSONObject.Create;
  FClientId     := Trim(GetEnvironmentVariable('OPENVERSE_CLIENT_ID'));
  FClientSecret := Trim(GetEnvironmentVariable('OPENVERSE_CLIENT_SECRET'));
end;

destructor TOpenverseApi.Destroy;
begin
  FQuota.Free;
  FOrder.Free;
  FCache.Free;
  FLock.Free;
  inherited;
end;

class function TOpenverseApi.Instance: TOpenverseApi;
begin
  Result := GApi;
end;

function TOpenverseApi.Authenticated: Boolean;
begin
  Result := (FClientId <> '') and (FClientSecret <> '');
end;

function TOpenverseApi.UserAgent: string;
begin
  // Generico: sin datos personales (lo pide la politica de Openverse para bots)
  Result := 'mcp-openverse/' + OV_VERSION + ' (+https://registry.pascalai.org)';
end;

function TOpenverseApi.NewClient: THTTPClient;
begin
  Result := THTTPClient.Create;
  Result.ConnectionTimeout := 10000;
  Result.ResponseTimeout   := 30000;
  Result.HandleRedirects   := True;
end;

function TOpenverseApi.CacheKey(const APathAndQuery: string): string;
begin
  if Authenticated then
    Result := FClientId + '|' + APathAndQuery
  else
    Result := 'anon|' + APathAndQuery;
end;

function TOpenverseApi.CacheGet(const AKey: string; out ABody: string): Boolean;
var
  E: TOvCacheEntry;
begin
  Result := False;
  ABody  := '';
  FLock.Enter;
  try
    if FCache.TryGetValue(AKey, E) then
    begin
      if Now < E.Expires then
      begin
        ABody := E.Body;
        FOrder.Remove(AKey);
        FOrder.Add(AKey);
        Result := True;
      end
      else
      begin
        FCache.Remove(AKey);
        FOrder.Remove(AKey);
      end;
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TOpenverseApi.CachePut(const AKey, ABody: string; AExpires: TDateTime);
var
  E: TOvCacheEntry;
begin
  E.Body    := ABody;
  E.Expires := AExpires;
  FLock.Enter;
  try
    if FCache.ContainsKey(AKey) then
      FOrder.Remove(AKey);
    FCache.AddOrSetValue(AKey, E);
    FOrder.Add(AKey);
    while FOrder.Count > OV_CACHE_MAX do
    begin
      FCache.Remove(FOrder[0]);
      FOrder.Delete(0);
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TOpenverseApi.SaveQuota(const AResp: IHTTPResponse);
var
  H: TNameValuePair;
  N: string;
  Old: TJSONPair;
begin
  FLock.Enter;
  try
    for H in AResp.Headers do
    begin
      N := LowerCase(H.Name);
      if N.StartsWith('x-ratelimit-') then
      begin
        N := N.Substring(Length('x-ratelimit-'));
        Old := FQuota.RemovePair(N);
        Old.Free;
        FQuota.AddPair(N, H.Value);
      end;
    end;
  finally
    FLock.Leave;
  end;
end;

function TOpenverseApi.QuotaJSON: TJSONObject;
begin
  FLock.Enter;
  try
    Result := FQuota.Clone as TJSONObject;
  finally
    FLock.Leave;
  end;
end;

function TOpenverseApi.AccessToken(AForce: Boolean): string;
var
  HTTP: THTTPClient;
  Resp: IHTTPResponse;
  Body: TStringStream;
  V: TJSONValue;
  Tok: string;
  Secs: Integer;
begin
  FLock.Enter;
  try
    if (not AForce) and (FToken <> '') and (Now < FTokenExpires) then
      Exit(FToken);
  finally
    FLock.Leave;
  end;

  HTTP := NewClient;
  Body := TStringStream.Create(
    'grant_type=client_credentials' +
    '&client_id=' + OvUrlEncode(FClientId) +
    '&client_secret=' + OvUrlEncode(FClientSecret), TEncoding.UTF8);
  try
    Resp := HTTP.Post(OV_BASE + '/v1/auth_tokens/token/', Body, nil,
      [TNameValuePair.Create('User-Agent', UserAgent),
       TNameValuePair.Create('Content-Type', 'application/x-www-form-urlencoded'),
       TNameValuePair.Create('Accept', 'application/json')]);
    if Resp.StatusCode <> 200 then
      raise EOpenverse.CreateFmt(
        'Openverse: could not get an access token (HTTP %d). Check OPENVERSE_CLIENT_ID / ' +
        'OPENVERSE_CLIENT_SECRET and that the registration e-mail was verified.', [Resp.StatusCode]);
    V := TJSONObject.ParseJSONValue(Resp.ContentAsString(TEncoding.UTF8));
    try
      if not (V is TJSONObject) then
        raise EOpenverse.Create('Openverse: unexpected token response');
      Tok  := TJSONObject(V).GetValue<string>('access_token', '');
      Secs := TJSONObject(V).GetValue<Integer>('expires_in', 3600);
    finally
      V.Free;
    end;
    if Tok = '' then
      raise EOpenverse.Create('Openverse: the token response has no access_token');
  finally
    Body.Free;
    HTTP.Free;
  end;

  // Renovar 5 minutos antes de que caduque
  if Secs > 600 then Dec(Secs, 300) else Secs := Secs div 2;
  FLock.Enter;
  try
    FToken        := Tok;
    FTokenExpires := IncSecond(Now, Secs);
  finally
    FLock.Leave;
  end;
  Result := Tok;
end;

function DetailOf(const ABody: string): string;
var
  V: TJSONValue;
begin
  Result := '';
  V := TJSONObject.ParseJSONValue(ABody);
  try
    if V is TJSONObject then
      Result := TJSONObject(V).GetValue<string>('detail', '');
    if (Result = '') and ABody.TrimLeft.StartsWith('<') then
      Result := '(HTML error page from the server; try again later)'
    else if Result = '' then
      Result := Copy(ABody, 1, 200);
  finally
    V.Free;
  end;
end;

function TOpenverseApi.Request(const APathAndQuery: string): string;
var
  Attempt: Integer;
  HTTP: THTTPClient;
  Resp: IHTTPResponse;
  Headers: TNetHeaders;
  Tok, Retry, Body: string;
begin
  Result := '';
  for Attempt := 1 to 2 do
  begin
    Tok := '';
    if Authenticated then
      Tok := AccessToken(Attempt = 2);   // en el reintento, token nuevo
    HTTP := NewClient;
    try
      Headers := [TNameValuePair.Create('User-Agent', UserAgent),
                  TNameValuePair.Create('Accept', 'application/json')];
      if Tok <> '' then
        Headers := Headers + [TNameValuePair.Create('Authorization', 'Bearer ' + Tok)];
      Resp := HTTP.Get(OV_BASE + APathAndQuery, nil, Headers);
      SaveQuota(Resp);
      Body := Resp.ContentAsString(TEncoding.UTF8);

      if Resp.StatusCode = 200 then
        Exit(Body);

      if (Resp.StatusCode = 401) and (Tok <> '') and (Attempt = 1) then
        Continue;

      // Openverse devuelve 500 intermitentes (verificado 2026-11-18: la misma
      // URL da 500 y luego 200). Es GET idempotente: un solo reintento.
      if (Resp.StatusCode >= 500) and (Attempt = 1) then
      begin
        Sleep(1500);
        Continue;
      end;

      if Resp.StatusCode = 429 then
      begin
        Retry := Resp.HeaderValue['Retry-After'];
        if Retry = '' then Retry := 'unknown';
        raise EOpenverse.CreateFmt(
          'Openverse rate limit reached (429). Retry after %s s. Do not loop: wait or tell the user. ' +
          'Anonymous use allows 20 requests/min and 200/day; set OPENVERSE_CLIENT_ID / ' +
          'OPENVERSE_CLIENT_SECRET for more.', [Retry]);
      end;

      if Resp.StatusCode = 404 then
        raise EOpenverse.Create('Openverse: not found (check media and id)');

      raise EOpenverse.CreateFmt('Openverse HTTP %d: %s', [Resp.StatusCode, DetailOf(Body)]);
    finally
      HTTP.Free;
    end;
  end;
end;

function TOpenverseApi.GetJSON(const APathAndQuery: string; ATtl: Double): TJSONValue;
var
  Key, Body: string;
begin
  Key := CacheKey(APathAndQuery);
  if not ((ATtl > 0) and CacheGet(Key, Body)) then
  begin
    Body := Request(APathAndQuery);
    if ATtl > 0 then
      CachePut(Key, Body, Now + ATtl);
  end;
  Result := TJSONObject.ParseJSONValue(Body);
  if Result = nil then
    raise EOpenverse.Create('Openverse: the response is not JSON');
end;

{ Descarga con tope de tamano }

type
  TSizeGuard = class
  public
    MaxBytes: Int64;
    Exceeded: Boolean;
    procedure OnData(const Sender: TObject; AContentLength: Int64;
      AReadCount: Int64; var AAbort: Boolean);
  end;

procedure TSizeGuard.OnData(const Sender: TObject; AContentLength: Int64;
  AReadCount: Int64; var AAbort: Boolean);
begin
  if (AReadCount > MaxBytes) or (AContentLength > MaxBytes) then
  begin
    Exceeded := True;
    AAbort   := True;
  end;
end;

function TOpenverseApi.DownloadFile(const AUrl, ADest: string; AMaxBytes: Int64): Int64;
var
  HTTP: THTTPClient;
  Resp: IHTTPResponse;
  FS: TFileStream;
  Guard: TSizeGuard;
  Part: string;
  Ok: Boolean;
begin
  if not AUrl.ToLower.StartsWith('https://') then
    raise EOpenverse.Create('only https downloads are allowed');

  Part  := ADest + '.part';
  Ok    := False;
  Result := 0;
  Guard := TSizeGuard.Create;
  HTTP  := NewClient;
  try
    Guard.MaxBytes := AMaxBytes;
    HTTP.ResponseTimeout := 120000;
    HTTP.OnReceiveData := Guard.OnData;
    FS := TFileStream.Create(Part, fmCreate);
    try
      try
        Resp := HTTP.Get(AUrl, FS, [TNameValuePair.Create('User-Agent', UserAgent)]);
      except
        on E: Exception do
          if not Guard.Exceeded then raise;
      end;
      Result := FS.Size;
    finally
      FS.Free;
    end;

    if Guard.Exceeded or (Result > AMaxBytes) then
      raise EOpenverse.CreateFmt('file larger than %d MB', [AMaxBytes div (1024 * 1024)]);
    if Resp = nil then
      raise EOpenverse.Create('download failed (no response)');
    if Resp.StatusCode <> 200 then
      raise EOpenverse.CreateFmt('download failed (HTTP %d)', [Resp.StatusCode]);
    if Result = 0 then
      raise EOpenverse.Create('download returned an empty file');

    if TFile.Exists(ADest) then
      TFile.Delete(ADest);
    TFile.Move(Part, ADest);
    Ok := True;
  finally
    HTTP.Free;
    Guard.Free;
    if (not Ok) and TFile.Exists(Part) then
      TFile.Delete(Part);
  end;
end;

initialization
  GApi := TOpenverseApi.Create;

finalization
  FreeAndNil(GApi);

end.
