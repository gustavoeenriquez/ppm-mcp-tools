unit MCPTool.MailAutoconfig;

{
  MCPTool.MailAutoconfig  ·  servidores IMAP/SMTP a partir de la direccion

  Como Thunderbird: el usuario solo escribe su correo y su clave; el servidor,
  el puerto y el cifrado se deducen del dominio. Orden:
    1. ISPDB de Mozilla  https://autoconfig.thunderbird.net/v1.1/<dominio>
    2. autoconfig del propio dominio (cPanel/Plesk lo publican)
       https://autoconfig.<dominio>/mail/config-v1.1.xml?emailaddress=<correo>
    3. https://<dominio>/.well-known/autoconfig/mail/config-v1.1.xml
    4. Convencion de hosting: mail.<dominio>, IMAP 993 SSL, SMTP 465 SSL.
  Cache en memoria por dominio. Las consultas salen de ESTE proceso, que en el
  servidor corre como mcpnet: el filtro de salida del kernel impide que un
  dominio apunte a la red interna.
}

interface

type
  TMailEndpoint = record
    Host: string;
    Port: Integer;
    SSL : string;   // ssl | starttls
  end;

// Resuelve IMAP y SMTP para la direccion. Nunca falla: en el peor caso
// devuelve la convencion mail.<dominio> (ASource = 'guess').
procedure AutoconfigMail(const AEmail: string; out AImap, ASmtp: TMailEndpoint;
  out ASource: string);

// Mensaje util cuando falla la conexion o el login (Microsoft y Gmail ya no
// aceptan la contrasena normal).
function MailLoginHint(const AHost, AError: string): string;

implementation

uses
  System.SysUtils, System.Classes, System.SyncObjs, System.StrUtils,
  System.Generics.Collections, System.Net.HttpClient, System.NetEncoding;

type
  TCached = record
    Imap, Smtp: TMailEndpoint;
    Source: string;
    At: TDateTime;
  end;

var
  GLock : TCriticalSection;
  GCache: TDictionary<string, TCached>;

function TagValue(const ABlock, ATag: string): string;
var
  P1, P2: Integer;
begin
  Result := '';
  P1 := Pos('<' + ATag + '>', ABlock);
  if P1 = 0 then Exit;
  Inc(P1, Length(ATag) + 2);
  P2 := PosEx('</' + ATag + '>', ABlock, P1);
  if P2 = 0 then Exit;
  Result := Trim(Copy(ABlock, P1, P2 - P1));
end;

// Primer bloque <ATag type="AType"> ... </ATag> del XML de autoconfig.
function ParseServer(const AXml, ATag, AType, ADomain, AEmail: string;
  out AEp: TMailEndpoint): Boolean;
var
  P, PEnd: Integer;
  Block, Sock: string;
begin
  Result := False;
  AEp := Default(TMailEndpoint);
  P := 1;
  while True do
  begin
    P := PosEx('<' + ATag, AXml, P);
    if P = 0 then Exit;
    PEnd := PosEx('</' + ATag + '>', AXml, P);
    if PEnd = 0 then Exit;
    Block := Copy(AXml, P, PEnd - P);
    P := PEnd;
    if not ContainsText(Copy(Block, 1, Pos('>', Block)), 'type="' + AType + '"') then
      Continue;
    AEp.Host := TagValue(Block, 'hostname')
      .Replace('%EMAILDOMAIN%', ADomain, [rfReplaceAll, rfIgnoreCase]);
    AEp.Port := StrToIntDef(TagValue(Block, 'port'), 0);
    Sock := UpperCase(TagValue(Block, 'socketType'));
    if Sock = 'SSL' then AEp.SSL := 'ssl'
    else if Sock = 'STARTTLS' then AEp.SSL := 'starttls'
    else Continue;   // sin cifrado: no se usa
    if (AEp.Host <> '') and (AEp.Port > 0) and not AEp.Host.Contains('%') then
      Exit(True);
  end;
end;

function Fetch(const AUrl: string): string;
var
  C: THTTPClient;
  R: IHTTPResponse;
begin
  Result := '';
  C := THTTPClient.Create;
  try
    C.ConnectionTimeout := 5000;
    C.ResponseTimeout   := 5000;
    try
      R := C.Get(AUrl);
      if R.StatusCode = 200 then
        Result := R.ContentAsString(TEncoding.UTF8);
    except
      // certificado inválido, DNS, timeout: se prueba la siguiente fuente
    end;
  finally
    C.Free;
  end;
end;

function DomainOk(const D: string): Boolean;
begin
  Result := (D <> '') and (Length(D) <= 253) and D.Contains('.');
  if Result then
    for var Ch in D do
      if not CharInSet(Ch, ['a'..'z', '0'..'9', '.', '-']) then Exit(False);
end;

procedure AutoconfigMail(const AEmail: string; out AImap, ASmtp: TMailEndpoint;
  out ASource: string);
var
  Domain, Xml: string;
  C: TCached;
  Urls: TArray<string>;
begin
  Domain := LowerCase(Trim(Copy(AEmail, Pos('@', AEmail) + 1, MaxInt)));
  if not DomainOk(Domain) then
    raise Exception.Create('La direccion de correo no tiene un dominio valido.');

  GLock.Enter;
  try
    if GCache.TryGetValue(Domain, C) and (Now - C.At < 1) then
    begin
      AImap := C.Imap; ASmtp := C.Smtp; ASource := C.Source;
      Exit;
    end;
  finally
    GLock.Leave;
  end;

  Urls := ['https://autoconfig.thunderbird.net/v1.1/' + Domain,
           'https://autoconfig.' + Domain + '/mail/config-v1.1.xml?emailaddress=' +
             TNetEncoding.URL.Encode(AEmail),
           'https://' + Domain + '/.well-known/autoconfig/mail/config-v1.1.xml'];
  ASource := '';
  for var U in Urls do
  begin
    Xml := Fetch(U);
    if (Xml <> '') and
       ParseServer(Xml, 'incomingServer', 'imap', Domain, AEmail, AImap) and
       ParseServer(Xml, 'outgoingServer', 'smtp', Domain, AEmail, ASmtp) then
    begin
      ASource := U;
      Break;
    end;
  end;
  if ASource = '' then
  begin
    AImap.Host := 'mail.' + Domain; AImap.Port := 993; AImap.SSL := 'ssl';
    ASmtp.Host := 'mail.' + Domain; ASmtp.Port := 465; ASmtp.SSL := 'ssl';
    ASource := 'guess';
  end;

  C.Imap := AImap; C.Smtp := ASmtp; C.Source := ASource; C.At := Now;
  GLock.Enter;
  try
    if GCache.Count > 5000 then GCache.Clear;
    GCache.AddOrSetValue(Domain, C);
  finally
    GLock.Leave;
  end;
end;

function MailLoginHint(const AHost, AError: string): string;
var
  H, E: string;
begin
  H := LowerCase(AHost);
  E := LowerCase(AError);
  if H.Contains('office365') or H.Contains('outlook') or H.Contains('hotmail') then
    Result := 'Microsoft no permite entrar al correo con la contrasena: esa cuenta ' +
      'necesitara "Conectar con Microsoft" (aun no disponible). Detalle: ' + AError
  else if H.Contains('gmail') or H.Contains('google') then
    Result := 'Gmail no acepta la contrasena normal: usa una contrasena de ' +
      'aplicacion (myaccount.google.com/apppasswords). Detalle: ' + AError
  else if E.Contains('auth') or E.Contains('login') or E.Contains('credential') or
          E.Contains('password') or E.Contains('535') then
    Result := 'El servidor de correo ' + AHost + ' rechazo el usuario o la ' +
      'contrasena. Revisa la cuenta en Conexiones. Detalle: ' + AError
  else
    Result := 'No se pudo conectar con el servidor de correo ' + AHost + ': ' + AError;
end;

initialization
  GLock  := TCriticalSection.Create;
  GCache := TDictionary<string, TCached>.Create;

finalization
  GCache.Free;
  GLock.Free;

end.
