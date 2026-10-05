"""Genera MCPTool.Conta.Catalog.pas desde el codigo del servidor.

    python gen_catalog.py [ruta\\al\\Server]     (default e:\\copilot\\contabilidad\\Server)

- Que metodos hay: los `function CON_*` de la interfaz de uConServerMethods.pas.
- A que modulo va cada uno: catalogo_modulos.json (lo unico que se mantiene a mano).
  Si el servidor tiene un metodo que el JSON no asigna, o el JSON nombra uno que
  ya no existe, el script falla y los lista: se agregan al JSON y se repite.
- Doc: el comentario `//` pegado encima de la declaracion, tal cual (es lo que
  el modelo lee en help / conta_modulos).
- Escritura: el cuerpo del metodo, o alguna rutina que llame (transitivo, en
  todas las unidades del Server), tiene un INSERT/UPDATE/DELETE en un literal
  SQL, o manda un mensaje (uTwilio/uMailSender). Las demas llamadas HTTP no
  cuentan (consultar FEVS o Wompi es leer).
  Las excepciones van en el JSON con su porque.

Despues de regenerar el catalogo hay que regenerar los parametros:
`python gen_params.py`.
"""
import glob
import io
import json
import os
import re
import sys

AQUI = os.path.dirname(os.path.abspath(__file__))
SRV = sys.argv[1] if len(sys.argv) > 1 else r'e:\copilot\contabilidad\Server'
OUT = os.path.join(AQUI, 'MCPTool.Conta.Catalog.pas')
CFG = json.load(io.open(os.path.join(AQUI, 'catalogo_modulos.json'), encoding='utf-8'))

srcs = {os.path.basename(f): io.open(f, encoding='utf-8-sig', errors='replace').read()
        for f in glob.glob(os.path.join(SRV, '*.pas'))}
main = srcs['uConServerMethods.pas']
intf = main[:main.index('\nimplementation')].split('\n')

# --- metodos publicos y su doc ---------------------------------------------
SEP = re.compile(r'[─═=\-]{6,}')
metodos, docs = [], {}
for i, l in enumerate(intf):
    m = re.match(r'\s*function\s+CON_(\w+)\s*[(:;]', l)
    if not m:
        continue
    c, j = [], i - 1
    while j >= 0 and re.match(r'\s*//', intf[j]):
        c.insert(0, re.sub(r'^\s*//\s?', '', intf[j]).strip())
        j -= 1
    metodos.append(m.group(1))
    docs[m.group(1)] = re.sub(r'\s+', ' ', ' '.join(x for x in c if x and not SEP.search(x))).strip()

# --- deteccion de escritura (transitiva) -----------------------------------
bodies = {}
envia = set()  # rutinas de uTwilio/uMailSender: mandar un mensaje tambien es escribir
HDR = re.compile(r'^(?:class\s+)?(?:function|procedure)\s+(?:\w+\.)?(\w+)', re.M)
for fn, s in srcs.items():
    impl = s[s.find('\nimplementation'):]
    ms = list(HDR.finditer(impl))
    for k, m in enumerate(ms):
        end = ms[k + 1].start() if k + 1 < len(ms) else len(impl)
        if fn in ('uTwilio.pas', 'uMailSender.pas'):
            envia.add(m.group(1))
        bodies[m.group(1)] = bodies.get(m.group(1), '') + re.sub(r'//[^\n]*', '', impl[m.start():end])
SQLW = re.compile(r"(?i)'[^']*(?<!FOR )\b(INSERT\s+INTO|UPDATE\s+\w|DELETE\s+FROM)")
CALL = re.compile(r'\b([A-Za-z_]\w*)\s*\(')
memo = {}


def escribe(n, pila=()):
    if n in memo:
        return memo[n]
    if n in pila:
        return False
    b = bodies.get(n, '')
    r = n in envia or bool(SQLW.search(b)) or any(escribe(c, pila + (n,)) for c in set(CALL.findall(b))
                                    if c != n and c in bodies)
    memo[n] = r
    return r


lect = CFG['lectura_aunque_escribe']
escr = CFG['escritura_aunque_no_se_detecte']
es_escritura = {}
for n in metodos:
    w = escribe('CON_' + n)
    es_escritura[n] = (w or n in escr) and n not in lect

# --- validacion contra el JSON ----------------------------------------------
asignados = [n for mod in CFG['modulos'] for n in mod['metodos']]
dup = sorted({n for n in asignados if asignados.count(n) > 1})
sin = [n for n in metodos if n not in asignados]
fantasmas = [n for n in asignados if n not in docs]
for n in list(lect) + list(escr):
    if n not in docs:
        fantasmas.append(n + ' (excepciones)')
if dup or sin or fantasmas:
    if dup:
        print('Asignados a mas de un modulo:', ', '.join(dup))
    if sin:
        print('Metodos del servidor sin modulo (agregarlos a catalogo_modulos.json):', ', '.join(sin))
    if fantasmas:
        print('En catalogo_modulos.json pero no en el servidor:', ', '.join(fantasmas))
    sys.exit(1)

# --- salida -----------------------------------------------------------------
orden = {n: i for i, n in enumerate(metodos)}


def lit(s):
    return "'" + s.replace("'", "''") + "'"


o = ['unit MCPTool.Conta.Catalog;', '',
     '// GENERADO por gen_catalog.py desde uConServerMethods.pas + catalogo_modulos.json — no editar a mano.',
     '// Catalogo de metodos publicos de ConServer agrupados en tools por dominio.', '',
     'interface', '', 'type', '  TContaMethodDef = record',
     '    Name: string;      // operation (sin prefijo CON_)',
     '    Doc: string;       // descripcion y params, tomados del fuente del servidor',
     '    IsWrite: Boolean;  // True = modifica datos', '  end;', '',
     '  TContaModuleDef = record', '    Tool: string;      // nombre del tool MCP',
     '    Title: string;', '    Desc: string;', '    Methods: TArray<TContaMethodDef>;', '  end;', '',
     'function ContaModules: TArray<TContaModuleDef>;', '', 'implementation', '',
     'function M(const AName, ADoc: string; AWrite: Boolean): TContaMethodDef;', 'begin',
     '  Result.Name := AName;', '  Result.Doc := ADoc;', '  Result.IsWrite := AWrite;', 'end;', '',
     'var', '  GModules: TArray<TContaModuleDef>;', '', 'procedure BuildModules;', 'begin',
     f"  SetLength(GModules, {len(CFG['modulos'])});"]
for k, mod in enumerate(CFG['modulos']):
    ms = sorted(mod['metodos'], key=orden.get)
    o += ['', f"  // {mod['title']} ({len(ms)} ops)",
          f"  GModules[{k}].Tool := {lit(mod['tool'])};",
          f"  GModules[{k}].Title := {lit(mod['title'])};",
          f"  GModules[{k}].Desc := {lit(mod['desc'])};",
          f'  GModules[{k}].Methods := [']
    o += [f"    M({lit(n)}, {lit(docs[n])}, {str(es_escritura[n])})" + (',' if i < len(ms) - 1 else '')
          for i, n in enumerate(ms)]
    o += ['  ];']
o += ['end;', '', 'function ContaModules: TArray<TContaModuleDef>;', 'begin',
      '  if Length(GModules) = 0 then', '    BuildModules;', '  Result := GModules;', 'end;', '', 'end.', '']

viejo = {}
if os.path.exists(OUT):
    viejo = {n: w == 'True' for n, w in re.findall(
        r"M\('(\w+)',\s*'(?:[^']|'')*',\s*(True|False)\)", io.open(OUT, encoding='utf-8-sig').read())}
io.open(OUT, 'w', encoding='utf-8-sig', newline='\n').write('\n'.join(o))

nuevos = [n for n in metodos if n not in viejo]
cambia = [n for n in metodos if n in viejo and viejo[n] != es_escritura[n]]
print(f'{len(metodos)} metodos en {len(CFG["modulos"])} modulos, '
      f'{sum(es_escritura.values())} escriben -> {os.path.basename(OUT)}')
if nuevos:
    print(f'Nuevos ({len(nuevos)}):', ', '.join(n + ('*' if es_escritura[n] else '') for n in nuevos))
if cambia:
    print('Cambia la marca:', ', '.join(f"{n} -> {'escribe' if es_escritura[n] else 'lee'}" for n in cambia))
