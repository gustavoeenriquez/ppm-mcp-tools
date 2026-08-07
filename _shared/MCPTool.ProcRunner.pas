unit MCPTool.ProcRunner;

{
  MCPTool.ProcRunner

  Ejecuta un comando por el shell del sistema y captura su salida combinada
  (stdout + stderr), con timeout. Es lo unico que ataba a Windows a media
  docena de mcp-tools: todos repetian el mismo CreateProcess + CreatePipe.

  Windows: cmd.exe /c, con pipe heredado y CREATE_NO_WINDOW.
  POSIX:   popen, que ya lanza /bin/sh -c; el timeout lo pone el comando
           `timeout` de coreutils, que devuelve 124 al matar al hijo.

  El comando que se pasa es una linea de shell, no un argv: cada tool ya
  construye la suya (con sus comillas) y aqui no se reinterpreta.
}

interface

{ Ejecuta ACommand en AWorkdir (vacio = directorio actual) y devuelve en
  AOutput la salida combinada. Result=False si no se pudo ni lanzar el
  proceso; ATimedOut indica que se agoto ATimeoutSec (<=0 => 300 s). }
function RunCaptured(const ACommand, AWorkdir: string; ATimeoutSec: Integer;
  out AOutput: string; out AExitCode: Integer; out ATimedOut: Boolean): Boolean;

implementation

uses
  System.SysUtils
{$IFDEF MSWINDOWS}
  , Winapi.Windows
{$ENDIF}
{$IFDEF POSIX}
  , Posix.Base
{$ENDIF};

{$IFDEF POSIX}
{ El RTL Posix de Delphi no expone popen/pclose/fgets (Posix.Stdio solo trae
  tipos), asi que se declaran contra libc. FILE* se maneja como puntero opaco:
  no se toca su contenido. }
type
  PCFile = Pointer;

function popen(const ACommand, AMode: PAnsiChar): PCFile; cdecl;
  external libc name _PU + 'popen';
function pclose(AStream: PCFile): Integer; cdecl;
  external libc name _PU + 'pclose';
function fgets(ABuf: PAnsiChar; ASize: Integer; AStream: PCFile): PAnsiChar; cdecl;
  external libc name _PU + 'fgets';
{$ENDIF}

function EffectiveTimeout(ATimeoutSec: Integer): Integer;
begin
  Result := ATimeoutSec;
  if Result <= 0 then Result := 300;
end;

{$IFDEF MSWINDOWS}
function RunCaptured(const ACommand, AWorkdir: string; ATimeoutSec: Integer;
  out AOutput: string; out AExitCode: Integer; out ATimedOut: Boolean): Boolean;
var
  SA:                  TSecurityAttributes;
  PipeRead, PipeWrite: THandle;
  PI:                  TProcessInformation;
  SI:                  TStartupInfo;
  Cmd:                 string;
  Code, WaitResult:    DWORD;
  Buffer:              array[0..4095] of AnsiChar;
  BytesRead:           DWORD;
  WorkdirPtr:          PChar;
begin
  AOutput   := '';
  AExitCode := -1;
  ATimedOut := False;

  SA.nLength              := SizeOf(SA);
  SA.lpSecurityDescriptor := nil;
  SA.bInheritHandle       := True;
  if not CreatePipe(PipeRead, PipeWrite, @SA, 0) then
    Exit(False);
  // El extremo de lectura es nuestro: que no lo herede el hijo.
  SetHandleInformation(PipeRead, HANDLE_FLAG_INHERIT, 0);

  FillChar(SI, SizeOf(SI), 0);
  SI.cb         := SizeOf(SI);
  SI.dwFlags    := STARTF_USESTDHANDLES;
  SI.hStdOutput := PipeWrite;
  SI.hStdError  := PipeWrite;
  SI.hStdInput  := INVALID_HANDLE_VALUE;

  Cmd := 'cmd.exe /c ' + ACommand + ' 2>&1';
  if AWorkdir <> '' then
    WorkdirPtr := PChar(AWorkdir)
  else
    WorkdirPtr := nil;

  FillChar(PI, SizeOf(PI), 0);
  if not CreateProcess(nil, PChar(Cmd), nil, nil, True,
                       CREATE_NO_WINDOW, nil, WorkdirPtr, SI, PI) then
  begin
    CloseHandle(PipeWrite);
    CloseHandle(PipeRead);
    Exit(False);
  end;

  // Nuestro extremo de escritura se cierra o el ReadFile no ve nunca el EOF.
  CloseHandle(PipeWrite);

  repeat
    if not ReadFile(PipeRead, Buffer, SizeOf(Buffer) - 1, BytesRead, nil) then Break;
    if BytesRead = 0 then Break;
    Buffer[BytesRead] := #0;
    AOutput := AOutput + string(AnsiString(PChar(@Buffer[0])));
  until False;

  WaitResult := WaitForSingleObject(PI.hProcess, EffectiveTimeout(ATimeoutSec) * 1000);
  ATimedOut  := WaitResult = WAIT_TIMEOUT;
  if GetExitCodeProcess(PI.hProcess, Code) then
    AExitCode := Integer(Code);
  CloseHandle(PI.hProcess);
  CloseHandle(PI.hThread);
  CloseHandle(PipeRead);
  Result := True;
end;
{$ENDIF}

{$IFDEF POSIX}
{ Envuelve en comillas simples para /bin/sh: dentro de ellas no se expande
  nada, y la propia comilla se escapa cerrando y reabriendo. }
function ShQuote(const S: string): string;
begin
  Result := '''' + S.Replace('''', '''\''''', [rfReplaceAll]) + '''';
end;

function RunCaptured(const ACommand, AWorkdir: string; ATimeoutSec: Integer;
  out AOutput: string; out AExitCode: Integer; out ATimedOut: Boolean): Boolean;
const
  TIMEOUT_EXIT = 124;   // lo que devuelve coreutils `timeout` al matar al hijo
var
  Inner, Full: string;
  Pipe:        PCFile;
  Buffer:      array[0..4095] of AnsiChar;
  Status:      Integer;
begin
  AOutput   := '';
  AExitCode := -1;
  ATimedOut := False;

  Inner := ACommand + ' 2>&1';
  if AWorkdir <> '' then
    Inner := 'cd ' + ShQuote(AWorkdir) + ' && ' + Inner;

  Full := Format('timeout %d /bin/sh -c %s',
                 [EffectiveTimeout(ATimeoutSec), ShQuote(Inner)]);

  Pipe := popen(PAnsiChar(AnsiString(Full)), 'r');
  if Pipe = nil then
    Exit(False);

  while fgets(@Buffer[0], SizeOf(Buffer), Pipe) <> nil do
    AOutput := AOutput + string(AnsiString(PAnsiChar(@Buffer[0])));

  Status := pclose(Pipe);
  if Status = -1 then
    Exit(False);

  // pclose devuelve el status de wait(): el codigo de salida esta en el byte alto.
  AExitCode := (Status and $FF00) shr 8;
  ATimedOut := AExitCode = TIMEOUT_EXIT;
  Result    := True;
end;
{$ENDIF}

end.
