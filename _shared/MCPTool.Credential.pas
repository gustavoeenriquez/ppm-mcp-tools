unit MCPTool.Credential;

{
  MCPTool.Credential  ·  credencial por peticion para MCP alojados en un servidor

  El mismo binario sirve en dos lados:
    - stdio (PC del programador, MakerCLI): la cuenta sale de las variables de
      entorno (MAIL_USER, TELEGRAM_BOT_TOKEN...) como siempre.
    - http/sse en un servidor (MKAIServer, docs/conexiones/DESIGN.md): el broker
      manda la cuenta de QUIEN llama en la cabecera Authorization de cada
      peticion — "Bearer base64(JSON con los mismos campos del .tool)" — y el
      MCP no guarda nada. Ese es el "modo servidor".

  En modo servidor las tools ademas:
    - IGNORAN host/usuario/clave que mande el modelo (solo vale la cabecera);
    - NO leen ni escriben disco (adjuntos, fotos por ruta): el proceso es
      compartido y una ruta elegida por el modelo podria sacar ficheros del
      servidor por correo;
    - limitan puertos (ver cada tool).
}

interface

uses
  uMakerAi.MCPServer.Core;

// Llamar SOLO en modo http/sse: la cabecera Authorization de cada peticion
// llega a las tools en AuthContext.UserID y activa el modo servidor.
procedure UseHeaderCredential(AServer: TAiMCPServer);

// True si la cuenta llega por cabecera (proceso alojado en un servidor).
function ServerMode: Boolean;

// Valor de un campo de la cuenta. Modo servidor: del JSON de la cabecera
// (sin cabecera -> excepcion clara). Si no: variable de entorno.
function Cred(const AuthContext: TAiAuthContext; const AKey: string): string;

implementation

uses
  System.SysUtils, System.JSON, System.NetEncoding;

type
  // Aloja el manejador del evento de validacion (es 'of object').
  TCredRelay = class
  public
    procedure Validate(Sender: TObject; const AAuthHeader, ARemoteIP: string;
      out AAuthContext: TAiAuthContext; out AIsValid: Boolean);
  end;

var
  GRelay: TCredRelay = nil;
  GServerMode: Boolean = False;

procedure TCredRelay.Validate(Sender: TObject; const AAuthHeader, ARemoteIP: string;
  out AAuthContext: TAiAuthContext; out AIsValid: Boolean);
begin
  AAuthContext := Default(TAiAuthContext);
  AAuthContext.UserID := Trim(AAuthHeader);
  AAuthContext.IsAuthenticated := AAuthContext.UserID <> '';
  // Siempre pasa: quien autoriza es el proveedor (IMAP, Telegram...). El
  // proceso escucha solo en 127.0.0.1 (MCP_BIND_ADDRESS).
  AIsValid := True;
end;

procedure UseHeaderCredential(AServer: TAiMCPServer);
begin
  if GRelay = nil then
    GRelay := TCredRelay.Create;
  AServer.OnValidateRequest := GRelay.Validate;
  GServerMode := True;
end;

function ServerMode: Boolean;
begin
  Result := GServerMode;
end;

function Cred(const AuthContext: TAiAuthContext; const AKey: string): string;
var
  H, Plain: string;
  J: TJSONValue;
begin
  if not GServerMode then
    Exit(GetEnvironmentVariable(AKey));

  H := Trim(AuthContext.UserID);
  if H.StartsWith('Bearer ', True) then
    H := Trim(Copy(H, 8, MaxInt));
  if H = '' then
    raise Exception.Create('Esta herramienta necesita una cuenta conectada ' +
      '(Conexiones) y no llego ninguna.');
  try
    Plain := TEncoding.UTF8.GetString(TNetEncoding.Base64.DecodeStringToBytes(H));
  except
    raise Exception.Create('La cuenta conectada llego ilegible.');
  end;
  J := TJSONObject.ParseJSONValue(Plain);
  try
    if not (J is TJSONObject) then
      raise Exception.Create('La cuenta conectada llego ilegible.');
    Result := Trim(TJSONObject(J).GetValue<string>(AKey, ''));
  finally
    J.Free;
  end;
end;

initialization

finalization
  GRelay.Free;

end.
