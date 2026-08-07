"""Smoke test de un MCP stdio: initialize -> tools/list -> N x tools/call.

Uso:
    python mcp_smoke.py <ruta-al-exe> '[{"name":"tool","arguments":{...}}, ...]'

Las credenciales que necesite el MCP bajo prueba se toman del entorno; este
script solo las hereda. Para el de SIAG, por ejemplo:

    SIAG_URL=http://localhost:8080 SIAG_EMAIL=... SIAG_PASSWORD=... \
    SIAG_TENANT=gea python mcp_smoke.py .../mcp-siag-query.exe '[...]'
"""
import json
import os
import subprocess
import sys

EXE = sys.argv[1]
CALLS = json.loads(sys.argv[2]) if len(sys.argv) > 2 else []

# Se hereda el entorno tal cual: nunca hardcodear credenciales aqui, este
# archivo vive en un repo git.
env = dict(os.environ)

p = subprocess.Popen(
    [EXE], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    env=env, text=True, encoding="utf-8", bufsize=1,
)


def send(obj):
    p.stdin.write(json.dumps(obj) + "\n")
    p.stdin.flush()


def read_reply():
    while True:
        line = p.stdout.readline()
        if not line:
            return None
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except json.JSONDecodeError:
            continue
        if "id" in msg:
            return msg


send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
    "protocolVersion": "2024-11-05",
    "capabilities": {},
    "clientInfo": {"name": "smoke", "version": "1.0"}}})
init = read_reply()
print("INITIALIZE:", json.dumps(init.get("result", init), ensure_ascii=False)[:400])

send({"jsonrpc": "2.0", "method": "notifications/initialized"})

send({"jsonrpc": "2.0", "id": 2, "method": "tools/list"})
tl = read_reply()
tools = tl.get("result", {}).get("tools", [])
print("TOOLS:", [t["name"] for t in tools])

for i, call in enumerate(CALLS, start=3):
    send({"jsonrpc": "2.0", "id": i, "method": "tools/call", "params": call})
    r = read_reply()
    res = r.get("result", r.get("error"))
    txt = ""
    if isinstance(res, dict) and "content" in res:
        txt = "".join(c.get("text", "") for c in res["content"])
    else:
        txt = json.dumps(res, ensure_ascii=False)
    print(f"\n--- CALL {json.dumps(call.get('arguments'), ensure_ascii=False)} ---")
    print(txt[:1500])

p.stdin.close()
try:
    p.wait(timeout=5)
except subprocess.TimeoutExpired:
    p.kill()
err = p.stderr.read()
if err.strip():
    print("\n[stderr]", err[:800])
