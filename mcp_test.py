#!/usr/bin/env python3
"""
mcp_test.py — Smoke-test MCP tools via stdio protocol.
Usage: python mcp_test.py [tool1 tool2 ...]  or no args = run all defined tests
"""
import subprocess, json, sys, os, time, threading
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

DIST = r"E:\Copilot\spas\ppm-mcp-tools"

def call_tool(name, arguments, timeout=15):
    # Support _tool_name override (for tools whose registered name differs from folder)
    tool_name = arguments.pop("_tool_name", name)
    arguments = {k:v for k,v in arguments.items()}  # copy

    exe = os.path.join(DIST, name, "dist", f"{name}.exe")
    if not os.path.exists(exe):
        exe2 = os.path.join(DIST, name, "dist", f"{name.replace('-','')}.exe")
        if os.path.exists(exe2): exe = exe2
        else: return None, f"exe not found"

    proc = subprocess.Popen(
        [exe, "--protocol", "stdio"],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, bufsize=1, encoding="utf-8", errors="replace"
    )

    def send(msg):
        proc.stdin.write(json.dumps(msg) + "\n")
        proc.stdin.flush()

    def recv():
        line = proc.stdout.readline()
        return json.loads(line) if line.strip() else None

    try:
        send({"jsonrpc":"2.0","id":1,"method":"initialize",
              "params":{"protocolVersion":"2024-11-05","capabilities":{},
                        "clientInfo":{"name":"test","version":"1.0"}}})
        recv()
        send({"jsonrpc":"2.0","method":"notifications/initialized","params":{}})

        send({"jsonrpc":"2.0","id":2,"method":"tools/call",
              "params":{"name":tool_name,"arguments":arguments}})

        result = [None]; err = [None]
        def read_resp():
            try: result[0] = recv()
            except Exception as e: err[0] = str(e)
        th = threading.Thread(target=read_resp, daemon=True)
        th.start(); th.join(timeout)

        if result[0] is None:
            return None, err[0] or "timeout"

        r = result[0]
        if "error" in r:
            return None, r["error"].get("message","error")
        content = r.get("result",{}).get("content",[])
        text = " ".join(c.get("text","") for c in content if c.get("type")=="text")
        return text, None
    finally:
        proc.stdin.close()
        proc.terminate()
        proc.wait(2)

# ── Test definitions ─────────────────────────────────────────────────────────

TESTS = {}

def t(tool, label, args):
    TESTS.setdefault(tool, []).append((label, args))

# mcp-calculator
t("mcp-calculator", "evaluate 2+2",   {"operation":"evaluate","expression":"2+2"})
t("mcp-calculator", "sqrt 144",       {"operation":"evaluate","expression":"sqrt(144)"})
t("mcp-calculator", "add",            {"operation":"add","a":15,"b":27})
t("mcp-calculator", "power",          {"operation":"power","a":2,"b":10})

# mcp-datetime
t("mcp-datetime", "now",             {"operation":"now","timezone":"UTC"})
t("mcp-datetime", "format dt",       {"operation":"format","datetime":"2026-05-07T14:30:00","formatStr":"dd/MM/yyyy HH:mm"})
t("mcp-datetime", "diff dates",      {"operation":"diff","datetime":"2026-01-01T00:00:00","datetimeB":"2026-12-31T00:00:00","timeUnit":"days"})
t("mcp-datetime", "add days",        {"operation":"add","datetime":"2026-05-07T00:00:00","amount":30,"timeUnit":"days"})

# mcp-hash
t("mcp-hash", "md5 string",   {"operation":"hash","algo":"md5","value":"hello world"})
t("mcp-hash", "sha256 string",{"operation":"hash","algo":"sha256","value":"hello world"})
t("mcp-hash", "sha1 string",  {"operation":"hash","algo":"sha1","value":"hello world"})
t("mcp-hash", "compare",      {"operation":"compare","value":"hello","value2":"hello"})

# mcp-text-transform
t("mcp-text-transform", "uppercase",   {"text":"hello world","operation":"uppercase"})
t("mcp-text-transform", "slug",        {"text":"Hello World Test","operation":"slug"})
t("mcp-text-transform", "reverse",     {"text":"abcdef","operation":"reverse"})
t("mcp-text-transform", "trim",        {"text":"  spaces  ","operation":"trim"})

# mcp-json-query
t("mcp-json-query", "format",   {"operation":"format","json":"{\"a\":1,\"b\":2}"})
t("mcp-json-query", "get path", {"operation":"get","json":"{\"user\":{\"name\":\"Ana\"}}","path":"user.name"})
t("mcp-json-query", "validate", {"operation":"validate","json":"{\"ok\":true}"})
t("mcp-json-query", "keys",     {"operation":"keys","json":"{\"a\":1,\"b\":2,\"c\":3}"})

# mcp-regex
t("mcp-regex", "test match", {"operation":"test","pattern":"\\d+","text":"abc123"})
t("mcp-regex", "find all",   {"operation":"find","pattern":"\\d+","text":"a1 b22 c333"})
t("mcp-regex", "replace",    {"operation":"replace","pattern":"\\s+","text":"hello   world","replacement":" "})
t("mcp-regex", "split",      {"operation":"split","pattern":",","text":"a,b,c,d"})

# mcp-tokenizer
t("mcp-tokenizer", "count tokens", {"text":"Hello world, this is a test sentence.","operation":"count"})
t("mcp-tokenizer", "truncate",     {"text":"one two three four five six","maxTokens":3,"operation":"truncate"})
t("mcp-tokenizer", "chunks",       {"text":"word " * 50,"operation":"chunk","maxTokens":10})

# mcp-compress
t("mcp-compress", "create zip", {"operation":"compress","files":r"E:\Copilot\spas\ppm-mcp-tools\README.md","path":r"E:\Temp\test_compress.zip"})
t("mcp-compress", "list zip",   {"operation":"list","path":r"E:\Temp\test_compress.zip"})
t("mcp-compress", "info zip",   {"operation":"info","path":r"E:\Temp\test_compress.zip"})

# mcp-xml
t("mcp-xml", "format",  {"operation":"format","xml":"<root><a>1</a><b>2</b></root>"})
t("mcp-xml", "to_json", {"operation":"to_json","xml":"<root><name>Ana</name><age>30</age></root>"})
t("mcp-xml", "find",    {"operation":"find","xml":"<root><item>A</item><item>B</item></root>","tag":"item"})
t("mcp-xml", "get",     {"operation":"get","xml":"<root><child>hello</child></root>","path":"root/child"})

# mcp-diff
t("mcp-diff", "parse diff",  {"operation":"parse","diff":"--- a/f.txt\n+++ b/f.txt\n@@ -1 +1 @@\n-old\n+new\n"})
t("mcp-diff", "apply diff",  {"operation":"apply","original":"old line","diff":"--- a/f.txt\n+++ b/f.txt\n@@ -1 +1 @@\n-old line\n+new line\n"})

# mcp-memory
t("mcp-memory", "store key",    {"operation":"store","key":"test_key","memValue":"hello_value"})
t("mcp-memory", "retrieve key", {"operation":"retrieve","key":"test_key"})
t("mcp-memory", "list all",     {"operation":"list_all"})
t("mcp-memory", "search",       {"operation":"search","query":"hello"})

# mcp-kv
t("mcp-kv", "set",    {"operation":"set","key":"test","value":"42","namespace":"test_ns"})
t("mcp-kv", "get",    {"operation":"get","key":"test","namespace":"test_ns"})
t("mcp-kv", "list",   {"operation":"list","namespace":"test_ns"})
t("mcp-kv", "count",  {"operation":"count","namespace":"test_ns"})

# mcp-notes
t("mcp-notes", "write note", {"operation":"write","id":"test-note","title":"Test Note","content":"Test content for MCP testing.\nSecond line.","tags":"test,demo"})
t("mcp-notes", "read note",  {"operation":"read","id":"test-note"})
t("mcp-notes", "search",     {"operation":"search","query":"test"})
t("mcp-notes", "list notes", {"operation":"list"})

# mcp-sequential-thinking
t("mcp-sequential-thinking", "create session", {"operation":"create_session","problem":"How to solve X?","sessionId":"test-sess-1"})
t("mcp-sequential-thinking", "add thought",    {"operation":"add_thought","sessionId":"test-sess-1","thought":"First analysis step","stepType":"analysis"})
t("mcp-sequential-thinking", "get session",    {"operation":"get_session","sessionId":"test-sess-1"})
t("mcp-sequential-thinking", "list sessions",  {"operation":"list_sessions"})

# mcp-workflow
t("mcp-workflow", "create",   {"operation":"create_workflow","workflowName":"TestFlow","workflowId":"wf-test-1","steps":"[{\"id\":\"s1\",\"name\":\"Step 1\",\"description\":\"First step\"},{\"id\":\"s2\",\"name\":\"Step 2\",\"description\":\"Second step\"}]"})
t("mcp-workflow", "get",      {"operation":"get_workflow","workflowId":"wf-test-1"})
t("mcp-workflow", "list",     {"operation":"list_workflows"})
t("mcp-workflow", "start",    {"operation":"start_workflow","workflowId":"wf-test-1","runId":"run-test-1"})

# mcp-file-reader (internal tool name is "mcp-files")
import tempfile, pathlib
_tmp = r"E:\Temp\mcp_test_file.txt"
os.makedirs(r"E:\Temp", exist_ok=True)
with open(_tmp, "w") as f: f.write("line1\nline2\nline3\n")
# Override tool name via special key in args dict (handled below in call_tool)
_fr_args = {"_tool_name":"mcp-files"}
t("mcp-file-reader", "write file", {**_fr_args,"operation":"write","path":r"E:\Temp\mcp_test_write.txt","content":"Hello from test"})
t("mcp-file-reader", "read file",  {**_fr_args,"operation":"read","path":_tmp})
t("mcp-file-reader", "list dir",   {**_fr_args,"operation":"list","path":r"E:\Temp","pattern":"*.txt"})
t("mcp-file-reader", "exists",     {**_fr_args,"operation":"exists","path":_tmp})
t("mcp-file-reader", "info",       {**_fr_args,"operation":"info","path":_tmp})
t("mcp-file-reader", "mkdir",      {**_fr_args,"operation":"mkdir","path":r"E:\Temp\mcp_test_dir"})

# mcp-ini
_ini = r"E:\Temp\mcp_test.ini"
with open(_ini, "w") as f: f.write("[section1]\nkey1=value1\nkey2=42\n\n[section2]\nname=test\n")
t("mcp-ini", "read key",       {"operation":"read","filePath":_ini,"section":"section1","key":"key1"})
t("mcp-ini", "read_section",   {"operation":"read_section","filePath":_ini,"section":"section1"})
t("mcp-ini", "write key",      {"operation":"write","filePath":_ini,"section":"section1","key":"newkey","value":"newval"})
t("mcp-ini", "list_sections",  {"operation":"list_sections","filePath":_ini})
t("mcp-ini", "list_keys",      {"operation":"list_keys","filePath":_ini,"section":"section1"})

# mcp-csv
_csv = r"E:\Temp\mcp_test.csv"
with open(_csv, "w") as f: f.write("name,age,city\nAna,30,Madrid\nBob,25,London\nCarla,35,Paris\n")
t("mcp-csv", "read",    {"operation":"read","filePath":_csv,"hasHeader":True})
t("mcp-csv", "filter",  {"operation":"filter","filePath":_csv,"hasHeader":True,"column":"age","value":"30","filterOp":"eq"})
t("mcp-csv", "stats",   {"operation":"stats","filePath":_csv,"hasHeader":True,"column":"age"})
t("mcp-csv", "sort",    {"operation":"sort","filePath":_csv,"hasHeader":True,"column":"name"})

# mcp-shell
t("mcp-shell", "echo cmd",   {"command":"echo hello from shell","shell":"cmd"})
t("mcp-shell", "dir list",   {"command":"dir /b E:\\Temp","shell":"cmd"})
t("mcp-shell", "ps version", {"command":"$PSVersionTable.PSVersion.ToString()","shell":"powershell"})

# mcp-git
t("mcp-git", "status",   {"operation":"status","path":r"E:\Copilot\spas\ppm-mcp-tools"})
t("mcp-git", "log",      {"operation":"log","path":r"E:\Copilot\spas\ppm-mcp-tools","limit":3})
t("mcp-git", "branches", {"operation":"branches","path":r"E:\Copilot\spas\ppm-mcp-tools"})

# mcp-process
t("mcp-process", "list", {"operation":"list"})

# Free APIs (no key needed)
t("mcp-openmeteo", "forecast BA",   {"location":"Buenos Aires","mode":"forecast","days":3})
t("mcp-openmeteo", "hourly Madrid", {"location":"Madrid, Spain","mode":"hourly","days":1})
t("mcp-openmeteo", "historical NY", {"location":"New York","mode":"historical","startDate":"2025-01-01","endDate":"2025-01-03"})

t("mcp-weather",  "weather Buenos Aires", {"location":"Buenos Aires"})
t("mcp-weather",  "weather London",       {"location":"London"})

t("mcp-maps", "geocode city",    {"operation":"geocode","address":"Madrid, Spain"})
t("mcp-maps", "reverse geocode", {"operation":"reverse_geocode","lat":40.4168,"lon":-3.7038})
t("mcp-maps", "search place",    {"operation":"search","query":"Eiffel Tower","lat":48.8566,"lon":2.3522})

t("mcp-wikipedia", "search",   {"operation":"search","query":"Delphi programming language"})
t("mcp-wikipedia", "summary", {"operation":"summary","title":"Pascal (programming language)"})
t("mcp-wikipedia", "content", {"operation":"content","title":"Delphi (software)"})

t("mcp-currency", "latest",   {"operation":"latest","base":"USD"})
t("mcp-currency", "convert",  {"operation":"convert","amount":100,"base":"USD","target":"EUR"})
t("mcp-currency", "list",     {"operation":"list"})

t("mcp-rss", "latest", {"operation":"latest","url":"https://feeds.bbci.co.uk/news/rss.xml","count":3})
t("mcp-rss", "search", {"operation":"search","url":"https://feeds.bbci.co.uk/news/rss.xml","keyword":"AI"})

t("mcp-fetch", "get url",    {"method":"GET","url":"https://httpbin.org/get"})
t("mcp-fetch", "post json",  {"method":"POST","url":"https://httpbin.org/post","body":"{\"test\":1}","headers":{"Content-Type":"application/json"}})

t("mcp-network", "ping",        {"operation":"ping","host":"8.8.8.8"})
t("mcp-network", "dns lookup",  {"operation":"dns","host":"google.com"})

t("mcp-calculator", "modulo",    {"operation":"modulo","a":17,"b":5})
t("mcp-calculator", "divide",    {"operation":"divide","a":22,"b":7,"precision":6})

# ── Runner ────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    target_tools = sys.argv[1:] if len(sys.argv) > 1 else sorted(TESTS.keys())
    
    ok = fail = 0
    results = {}

    for tool in target_tools:
        if tool not in TESTS:
            print(f"[SKIP ] {tool} — no tests defined")
            continue
        cases = TESTS[tool]
        tool_ok = True
        labels = []
        for label, args in cases:
            text, err = call_tool(tool, args)
            if err:
                print(f"  [FAIL] {tool} / {label}: {err}")
                tool_ok = False; fail += 1
            else:
                preview = text[:80].replace("\n"," ") if text else "(empty)"
                print(f"  [OK  ] {tool} / {label}: {preview}")
                ok += 1
                labels.append(label)
        results[tool] = (tool_ok, labels)

    print(f"\n=== Win64 results: OK={ok}  FAIL={fail} ===")
    print("\nPassed tools:")
    for tn, (passed, labels) in sorted(results.items()):
        mark = "[OK]" if passed else "[FAIL]"
        print(f"  {mark} {tn}: {', '.join(labels)}")
