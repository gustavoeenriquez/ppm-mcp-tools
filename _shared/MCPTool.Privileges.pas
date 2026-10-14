unit MCPTool.Privileges;

(*
  MCPTool.Privileges — alcance de las tools que tocan la maquina, definido
  por el DUEÑO de la maquina (nunca por la tool).

  Si la variable de entorno MCP_ALLOWED_ROOTS existe y no esta vacia, es una
  lista de directorios separados por ';' y TODA ruta que la tool toque (leer,
  escribir, listar, workdir, archivo a ejecutar...) tiene que caer dentro de
  alguno. Si no existe, no hay limite: la tool se comporta exactamente como
  antes de esta unidad, asi que ningun cliente que no la defina nota nada.

  Lo honesto sobre lo que acota: en mcp-fs acota TODO, porque cada operacion
  recibe la ruta. En mcp-shell, mcp-python y mcp-code-exec solo acota lo que
  la tool ve (workdir, file_path, database_path): el codigo o el comando que
  ejecutan puede abrir cualquier ruta. Para impedir ESO la unica palanca es no
  cargar la tool (en MakerCLI: local_privileges.exec = false).

  Quien la inyecta: MakerCLI (uMakerCLI.Toolset.ImportProjectMcp) desde el
  bloque local_privileges de .makercli.json, que escribe el usuario.
*)

interface

const
  ENV_ALLOWED_ROOTS = 'MCP_ALLOWED_ROOTS';

// ¿El dueño definio raices? (variable presente y con al menos un directorio)
function RootsDefined: Boolean;
function AllowedRoots: TArray<string>;
// ¿Esta ruta cae dentro de alguna raiz? Sin raices definidas, siempre True.
// Resuelve relativas y '..' contra el directorio actual antes de comparar.
function PathAllowed(const APath: string): Boolean;
// Lanza una excepcion con un mensaje claro si la ruta queda fuera.
procedure CheckPathAllowed(const APath, AWhat: string);
// Frase para la descripcion de la tool (vacia si no hay raices)
function PrivilegesNote: string;

implementation

uses
  System.SysUtils, System.IOUtils, System.StrUtils;

function NormDir(const P: string): string;
begin
  Result := IncludeTrailingPathDelimiter(TPath.GetFullPath(Trim(P)));
  {$IFDEF MSWINDOWS}
  Result := Result.Replace('/', '\');
  {$ENDIF}
end;

function AllowedRoots: TArray<string>;
var
  Raw, Part: string;
begin
  Result := [];
  Raw := GetEnvironmentVariable(ENV_ALLOWED_ROOTS);
  for Part in Raw.Split([';']) do
    if Trim(Part) <> '' then
      try
        Result := Result + [NormDir(Part)];
      except
        // una raiz mal escrita no vale como raiz, pero no rompe las demas
      end;
end;

function RootsDefined: Boolean;
begin
  Result := Length(AllowedRoots) > 0;
end;

function PathAllowed(const APath: string): Boolean;
var
  Roots: TArray<string>;
  Full, R: string;
begin
  Roots := AllowedRoots;
  if Length(Roots) = 0 then Exit(True);
  try
    Full := TPath.GetFullPath(Trim(APath));
    {$IFDEF MSWINDOWS}
    Full := Full.Replace('/', '\');
    {$ENDIF}
  except
    Exit(False);   // ruta que ni se puede normalizar: fuera
  end;
  // Un archivo dentro de la raiz empieza por la raiz con su barra final; el
  // propio directorio raiz (sin barra) tambien vale.
  for R in Roots do
    if StartsText(R, IncludeTrailingPathDelimiter(Full)) then
      Exit(True);
  Result := False;
end;

procedure CheckPathAllowed(const APath, AWhat: string);
begin
  if not PathAllowed(APath) then
    raise Exception.CreateFmt(
      '%s "%s" is outside %s (%s): the owner of this machine limited this tool to those directories',
      [AWhat, APath, ENV_ALLOWED_ROOTS, string.Join('; ', AllowedRoots)]);
end;

function PrivilegesNote: string;
begin
  if RootsDefined then
    Result := ' RESTRICTED by the owner to these directories (any path outside fails): ' +
              string.Join('; ', AllowedRoots) + '.'
  else
    Result := '';
end;

end.
