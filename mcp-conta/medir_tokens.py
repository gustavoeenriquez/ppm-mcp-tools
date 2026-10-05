"""Mide cuanto ocupa en tokens la superficie de mcp-conta / mcp-conta-query.

Uso:
    python medir_tokens.py <exe> [args del exe...]
    python medir_tokens.py dist/mcp-conta.exe --tools compact

Levanta el MCP por stdio, pide tools/list y cuenta los tokens con la API
messages.count_tokens de Anthropic (ANTHROPIC_API_KEY del entorno; nunca se
escribe aqui). Lo que se reporta es el costo de DECLARAR las herramientas en un
turno: tokens(con tools) - tokens(sin tools), para la lista completa y para
cada herramienta sola.

En modo compacto ademas llama conta_modulos sin argumento y con cada modulo, y
cuenta lo que esas respuestas le cuestan al modelo cuando las lee (como
tool_result). No hace falta credencial: conta_modulos no toca el servidor.
"""
import json
import os
import subprocess
import sys

import anthropic

MODEL = os.environ.get("MEDIR_MODEL", "claude-sonnet-5-5")
CMD = sys.argv[1:]
if not CMD:
    sys.exit(__doc__)

p = subprocess.Popen(CMD, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                     stderr=subprocess.DEVNULL, text=True, encoding="utf-8", bufsize=1)
_id = 0


def rpc(method, params=None):
    global _id
    _id += 1
    msg = {"jsonrpc": "2.0", "id": _id, "method": method}
    if params is not None:
        msg["params"] = params
    p.stdin.write(json.dumps(msg) + "\n")
    p.stdin.flush()
    while True:
        line = p.stdout.readline()
        if not line:
            raise SystemExit("el MCP cerro stdout")
        line = line.strip()
        if not line.startswith("{"):
            continue
        r = json.loads(line)
        if r.get("id") == _id:
            return r.get("result", r)


rpc("initialize", {"protocolVersion": "2025-06-18", "capabilities": {},
                   "clientInfo": {"name": "medir_tokens", "version": "1"}})
p.stdin.write(json.dumps({"jsonrpc": "2.0", "method": "notifications/initialized"}) + "\n")
p.stdin.flush()
tools = rpc("tools/list")["tools"]

client = anthropic.Anthropic()
MSG = [{"role": "user", "content": "hola"}]


def contar(tool_list=None, messages=MSG):
    kw = {"model": MODEL, "messages": messages}
    if tool_list:
        kw["tools"] = tool_list
    return client.messages.count_tokens(**kw).input_tokens


def a_anthropic(t):
    return {"name": t["name"], "description": t.get("description", ""),
            "input_schema": t.get("inputSchema") or {"type": "object"}}


base = contar()
atools = [a_anthropic(t) for t in tools]
total = contar(atools) - base
print(f"modelo: {MODEL}")
print(f"tools/list: {len(tools)} herramientas, {len(json.dumps(tools))} bytes JSON")
print(f"TOTAL declarar todas: {total} tokens")
for t in atools:
    print(f"  {t['name']:<34} {contar([t]) - base:>6}")

nombres = {t["name"] for t in tools}
if "conta_modulos" in nombres:
    def costo_resultado(args):
        r = rpc("tools/call", {"name": "conta_modulos", "arguments": args})
        texto = "".join(c.get("text", "") for c in r.get("content", []))
        msgs = MSG + [
            {"role": "assistant", "content": [{"type": "tool_use", "id": "t1",
                                               "name": "conta_modulos", "input": args}]},
            {"role": "user", "content": [{"type": "tool_result", "tool_use_id": "t1",
                                          "content": texto}]}]
        sin = MSG + [
            {"role": "assistant", "content": [{"type": "tool_use", "id": "t1",
                                               "name": "conta_modulos", "input": args}]},
            {"role": "user", "content": [{"type": "tool_result", "tool_use_id": "t1",
                                          "content": ""}]}]
        return contar(atools, msgs) - contar(atools, sin), texto

    n, texto = costo_resultado({})
    print(f"\nconta_modulos() -> {n} tokens al leerlo")
    mods = [m["modulo"] for m in json.loads(texto)["modulos"]]
    for m in mods:
        n, _ = costo_resultado({"modulo": m})
        print(f"  conta_modulos({m!r:<26}) {n:>6}")

p.terminate()
