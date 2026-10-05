"""Genera MCPTool.Conta.Params.pas: los parametros de cada operacion del
catalogo, sacados del FUENTE del servidor (no de los comentarios).

Uso:
    python gen_params.py [ruta a uConServerMethods.pas]
    (por omision e:\\copilot\\contabilidad\\Server\\uConServerMethods.pas)

Por cada CON_<op> del catalogo (MCPTool.Conta.Catalog.pas) busca la variable
donde el metodo parsea Params (V := TJSONObject.ParseJSONValue(Params)) y
recoge:
  - las llaves que lee de ESA variable: V.GetValue<T>('k'...), V.Values['k'],
    V.TryGetValue / FindValue / Get('k') -> nombre y tipo;
  - cuales son requeridas: GetValue<T>('k') sin default (revienta si falta), o
    la variable que recibe la llave se prueba vacia en un
    "if X = '' [or Y = 0] then Exit(ErrorJson(..." / raise;
  - si la lista es COMPLETA: la variable de Params no se pasa a otra funcion
    (ni Params mismo, salvo a ParseJSONValue). Si no es completa, el MCP no
    rechaza llaves desconocidas: podrian ser leidas por el helper.

Volver a correrlo cuando el servidor cambie lo que lee un metodo. Es
heuristico a proposito por el lado seguro: ante la duda una llave queda
opcional y la lista queda incompleta, y quien valida al final es el servidor.
"""
import os
import re
import sys

AQUI = os.path.dirname(os.path.abspath(__file__))
SRC = sys.argv[1] if len(sys.argv) > 1 else \
    r"e:\copilot\contabilidad\Server\uConServerMethods.pas"
CATALOG = os.path.join(AQUI, "MCPTool.Conta.Catalog.pas")
OUT = os.path.join(AQUI, "MCPTool.Conta.Params.pas")

TIPOS = {"string": "s", "integer": "i", "int64": "i", "cardinal": "i",
         "double": "n", "currency": "n", "extended": "n", "single": "n",
         "boolean": "b", "tjsonarray": "a", "tjsonobject": "o"}

src = open(SRC, encoding="utf-8-sig").read()
impl = src[src.index("\nimplementation"):]

# Cuerpos: desde "function TConServerMethods.CON_X" hasta la siguiente rutina.
cuerpos = {}
inicios = [m for m in re.finditer(
    r"^(?:function|procedure) TConServerMethods\.(\w+)", impl, re.M)]
for i, m in enumerate(inicios):
    fin = inicios[i + 1].start() if i + 1 < len(inicios) else len(impl)
    if m.group(1).startswith("CON_"):
        cuerpos[m.group(1)[4:]] = impl[m.start():fin]

ops = re.findall(r"M\('(\w+)'", open(CATALOG, encoding="utf-8-sig").read())


def analizar(body):
    """-> (lista de (llave, tipo, requerida), completa)"""
    body = body.split("\n", 1)[1] if "\n" in body else ""   # sin la firma
    vars_ = set(re.findall(
        r"(\w+)\s*:=\s*TJSONObject\.ParseJSONValue\(\s*Params\b", body))
    if not vars_:
        # Sin Params, o Params pasado entero a otra rutina.
        return [], not re.search(r"\bParams\b", body)
    completa = True
    # Params mismo pasado a otra cosa que ParseJSONValue.
    for m in re.finditer(r"(\w+)\(\s*Params\b", body):
        if m.group(1) != "ParseJSONValue":
            completa = False

    llaves = {}       # llave -> [tipo, requerida]
    asignada = {}     # variable Delphi -> llave
    vr = "|".join(map(re.escape, vars_))
    pat = re.compile(
        r"(?:(\w+)\s*:=\s*(?:Trim\(\s*)?)?\b(" + vr + r")\."
        r"(GetValue|TryGetValue|FindValue|Get|Values)"
        r"(?:<(\w+)>)?\s*[\(\[]\s*'([^']+)'\s*([,\)\]])")
    for m in pat.finditer(body):
        destino, _, metodo, tipo, llave, sig = m.groups()
        t = TIPOS.get((tipo or "").lower(), "")
        req = metodo == "GetValue" and tipo is not None and sig == ")"
        e = llaves.setdefault(llave, ["", False])
        if t and not e[0]:
            e[0] = t
        e[1] = e[1] or req
        if destino:
            asignada[destino] = llave

    # La variable de Params pasada como argumento a otra rutina (helper que
    # lee mas llaves) -> lista incompleta.
    # Conservador: cualquier uso "suelto" de la variable (argumento, for-in,
    # with, asignacion a otra) que no sea V.Metodo, V := ..., Assigned(V) o
    # FreeAndNil(V) cuenta como fuga.
    cuerpo = body[re.search(r"\bbegin\b", body, re.I).start():]   # sin el var
    limpio = re.sub(r"\b(?:Assigned|FreeAndNil)\(\s*(?:" + vr + r")\s*\)", "", cuerpo)
    limpio = re.sub(r"\b(?:" + vr + r")\s*:=", "", limpio)
    limpio = re.sub(r"//[^\n]*|\{[^}]*\}|'[^'\n]*'", "", limpio)
    if re.search(r"(?<![\w.])(?:" + vr + r")\b(?!\s*\.)", limpio):
        completa = False
    # Recorre las llaves (V.Pairs / V.Count): acepta cualquiera.
    if re.search(r"\b(?:" + vr + r")\.(?:Pairs|Count|GetEnumerator|ToJSON|ToString|Clone)\b", body):
        completa = False
    # Llave no literal: V.GetValue<T>(Variable)
    if re.search(r"\b(?:" + vr + r")\.(?:GetValue|TryGetValue|FindValue|Get|Values)"
                 r"(?:<\w+>)?\s*[\(\[]\s*[^'\s]", body):
        completa = False

    # if <X = '' / X = 0 / X <= 0 / X < 1> [or ...] then Exit(ErrorJson( | raise
    for m in re.finditer(
            r"\bif\s+(.{1,200}?)\s+then\s+(?:begin\s+)?(?:Exit\(\s*ErrorJson|raise\b)",
            body, re.S | re.I):
        cond = m.group(1)
        if re.search(r"\band\b|\bnot\b", cond, re.I):
            continue
        for parte in re.split(r"\bor\b", cond, flags=re.I):
            p = parte.strip().strip("()").strip()
            mm = re.fullmatch(
                r"(?:Trim\(\s*)?(\w+)\)?\s*(?:=\s*''|=\s*0|<=\s*0|<\s*1|=\s*nil)",
                p)
            if mm and mm.group(1) in asignada:
                llaves[asignada[mm.group(1)]][1] = True
    return [(k, v[0], v[1]) for k, v in llaves.items()], completa


def pas_str(s):
    return "'" + s.replace("'", "''") + "'"


lineas = []
n_completas = n_con_params = 0
faltan = []
for op in ops:
    body = cuerpos.get(op)
    if body is None:
        faltan.append(op)
        continue
    llaves, completa = analizar(body)
    recibe = bool(re.match(r"function TConServerMethods\.CON_\w+\s*\(\s*Params\b", body))
    # spec: "codigo!:s,nombre:s" (! = requerida; tipo s/i/n/b/a/o, vacio = libre)
    spec = ",".join(k + ("!" if r else "") + (":" + t if t else "")
                    for k, t, r in llaves)
    if llaves:
        n_con_params += 1
    if completa:
        n_completas += 1
    lineas.append(f"  P({pas_str(op)}, {pas_str(spec)}, {str(completa)}, {str(recibe)});")

out = f"""\ufeffunit MCPTool.Conta.Params;

// GENERADO por gen_params.py desde uConServerMethods.pas — no editar a mano.
// Parametros que lee cada operacion, sacados del fuente del servidor.
// Spec: "llave[!][:tipo],..."  ! = requerida; tipo s=string i=entero n=numero
// b=booleano a=arreglo o=objeto (sin tipo = libre). Completa = el metodo no
// lee mas llaves que estas (si es False, el MCP no rechaza llaves extra).

interface

type
  TContaParamDef = record
    Name: string;
    Tipo: Char;        // s i n b a o, o #0 si libre
    Requerida: Boolean;
  end;

  TContaParamSpec = record
    Encontrada: Boolean;
    Completa: Boolean;
    Recibe: Boolean;   // el metodo del servidor tiene argumento Params
    Params: TArray<TContaParamDef>;
  end;

function ContaParamsDe(const AOp: string): TContaParamSpec;

implementation

uses
  System.SysUtils, System.Generics.Collections;

type
  TSpecRaw = record
    Spec: string;
    Completa: Boolean;
    Recibe: Boolean;
  end;

var
  GSpecs: TDictionary<string, TSpecRaw> = nil;

procedure P(const AOp, ASpec: string; ACompleta, ARecibe: Boolean);
var
  R: TSpecRaw;
begin
  R.Spec := ASpec;
  R.Completa := ACompleta;
  R.Recibe := ARecibe;
  GSpecs.AddOrSetValue(LowerCase(AOp), R);
end;

procedure Build;
begin
  GSpecs := TDictionary<string, TSpecRaw>.Create;
{chr(10).join(lineas)}
end;

function ContaParamsDe(const AOp: string): TContaParamSpec;
var
  R: TSpecRaw;
  Partes: TArray<string>;
  i, PColon: Integer;
  S: string;
  D: TContaParamDef;
begin
  Result := Default(TContaParamSpec);
  if GSpecs = nil then
    Build;
  if not GSpecs.TryGetValue(LowerCase(AOp), R) then
    Exit;
  Result.Encontrada := True;
  Result.Completa := R.Completa;
  Result.Recibe := R.Recibe;
  if R.Spec = '' then
    Exit;
  Partes := R.Spec.Split([',']);
  SetLength(Result.Params, Length(Partes));
  for i := 0 to High(Partes) do
  begin
    S := Partes[i];
    D := Default(TContaParamDef);
    PColon := Pos(':', S);
    if PColon > 0 then
    begin
      D.Tipo := S[PColon + 1];
      S := Copy(S, 1, PColon - 1);
    end;
    if S.EndsWith('!') then
    begin
      D.Requerida := True;
      S := Copy(S, 1, Length(S) - 1);
    end;
    D.Name := S;
    Result.Params[i] := D;
  end;
end;

initialization

finalization
  GSpecs.Free;

end.
"""
with open(OUT, "w", encoding="utf-8", newline="\r\n") as f:
    f.write(out)
print(f"{len(lineas)} operaciones; {n_con_params} con parametros; "
      f"{n_completas} con lista completa")
if faltan:
    print("en el catalogo pero no en el servidor:", ", ".join(faltan))
