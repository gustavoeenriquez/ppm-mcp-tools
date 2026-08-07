import subprocess, json, sys, os, threading

DIST = r"E:\Copilot\spas\ppm-mcp-tools"

def list_tools(name):
    # find exe
    for n in [name, name.replace("-","")]:
        exe = os.path.join(DIST, name, "dist", f"{n}.exe")
        if os.path.exists(exe): break
    else:
        return None, "exe not found"

    proc = subprocess.Popen([exe, "--protocol", "stdio"],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, bufsize=1)

    def send(msg): proc.stdin.write(json.dumps(msg)+"\n"); proc.stdin.flush()
    def recv():
        line = proc.stdout.readline()
        return json.loads(line) if line.strip() else None

    try:
        send({"jsonrpc":"2.0","id":1,"method":"initialize",
              "params":{"protocolVersion":"2024-11-05","capabilities":{},
                        "clientInfo":{"name":"t","version":"1"}}})
        recv()
        send({"jsonrpc":"2.0","method":"notifications/initialized","params":{}})
        send({"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}})
        r=[None]
        def rd(): r[0]=recv()
        t=threading.Thread(target=rd,daemon=True); t.start(); t.join(8)
        return r[0], None
    finally:
        proc.stdin.close(); proc.terminate(); proc.wait(2)

tools_to_check = [
    "mcp-calculator","mcp-datetime","mcp-hash","mcp-json-query","mcp-regex",
    "mcp-compress","mcp-xml","mcp-memory","mcp-notes","mcp-sequential-thinking",
    "mcp-workflow","mcp-file-reader","mcp-ini","mcp-csv","mcp-maps",
    "mcp-wikipedia","mcp-currency","mcp-rss"
]

for t in tools_to_check:
    resp, err = list_tools(t)
    if err:
        print(f"\n{t}: ERROR {err}")
        continue
    tools = resp.get("result",{}).get("tools",[]) if resp else []
    for tool in tools:
        name = tool.get("name","?")
        schema = tool.get("inputSchema",{})
        props = schema.get("properties",{})
        req = schema.get("required",[])
        print(f"\n{t} -> tool:{name}")
        for p,v in props.items():
            r_mark = "*" if p in req else " "
            desc = v.get("description","")[:60]
            enum = v.get("enum","")
            if enum: desc = str(enum)
            print(f"  {r_mark} {p}: {desc}")
