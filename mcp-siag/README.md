# mcp-siag / mcp-siag-query

Two MCP servers that expose a **SIAG** analytics backend to AI agents, built on
the same MakerAI stack as the rest of `ppm-mcp-tools`. They are HTTP clients of
the SIAG DataSnap REST server (`/datasnap/rest/TSigServerMethods`).

| Tool | Scope | Default port | Binary |
|------|-------|--------------|--------|
| `mcp-siag-query` | **Read-only** — QUERY / DRILL / NAVIGATE / INSPECT | 8771 | `mcp-siag-query/dist/` |
| `mcp-siag` | **Full** — any DSL (incl. writes) + config CRUD | 8770 | `mcp-siag/dist/` |

Shared client logic lives in `_shared/MCPTool.SiagClient.pas` (login, cached
token, DataSnap envelope handling).

## Why two servers

- **`mcp-siag-query`** rejects every write verb (CREATE/ALTER/DROP/LOAD/DEFINE/
  INSERT/UPDATE/DELETE) **client-side**, before the request is sent. Safe to
  expose to autonomous agents even when the configured user is an admin.
- **`mcp-siag`** is the full surface: run any DSL (writes need `rol=admin`, the
  server enforces it) and manage categories / variables / indicators / library.

## Configuration (environment variables)

Auth is automatic: on the first call each server logs in and caches the JWT
token (tokens last 24h; refreshed after 23h). The model never sees the token.

| Variable | Required | Default | Meaning |
|----------|----------|---------|---------|
| `SIAG_URL` | no | `http://localhost:8080` | Base server URL (no trailing slash) |
| `SIAG_EMAIL` | yes | — | User email |
| `SIAG_PASSWORD` | yes | — | User password |
| `SIAG_TENANT` | yes | — | Tenant slug ("empresa") |

`mcp-siag` may also override credentials per call by passing
`email` + `password` + `tenant` in the tool arguments.

## Build

```bat
:: from ppm-mcp-tools, after loading rsvars.bat
msbuild mcp-siag\mcp-siag.dproj             /t:Build /p:Config=Release /p:Platform=Win64
msbuild mcp-siag-query\mcp-siag-query.dproj /t:Build /p:Config=Release /p:Platform=Win64
```

Requires the **MakerAI** package on the library path (same as every other tool
here). Linux64 is supported via `/p:Platform=Linux64` (output in
`dist-linux-x64/`).

## Register in an MCP client

Transport is **stdio** by default (also `--protocol http|sse --port N`). Example
Claude Desktop / Claude Code config:

```json
{
  "mcpServers": {
    "siag-query": {
      "command": "E:\\Copilot\\spas\\ppm-mcp-tools\\mcp-siag-query\\dist\\mcp-siag-query.exe",
      "env": {
        "SIAG_URL": "http://localhost:8080",
        "SIAG_EMAIL": "admin@empresa.com",
        "SIAG_PASSWORD": "***",
        "SIAG_TENANT": "miempresa"
      }
    },
    "siag": {
      "command": "E:\\Copilot\\spas\\ppm-mcp-tools\\mcp-siag\\dist\\mcp-siag.exe",
      "env": {
        "SIAG_URL": "http://localhost:8080",
        "SIAG_EMAIL": "admin@empresa.com",
        "SIAG_PASSWORD": "***",
        "SIAG_TENANT": "miempresa"
      }
    }
  }
}
```

## Operations

### mcp-siag-query (read-only)

| operation | args | notes |
|-----------|------|-------|
| `health` | — | server health |
| `get_me` | — | authenticated profile |
| `query` | `dsl` | DSL must start with `QUERY` |
| `drill` | `dsl` | DSL must start with `DRILL` |
| `navigate` | `dsl` | DSL must start with `NAVIGATE` |
| `inspect` | `dsl` | DSL must start with `INSPECT` |
| `dsl` | `dsl` | any read verb |

### mcp-siag (full)

`health`, `login`, `get_me`, `execute_dsl` (any DSL), plus config CRUD:
`get_categorias`, `save_categoria`, `delete_categoria`,
`get_variables`, `save_variable`, `delete_variable`,
`get_indicadores`, `save_indicador`, `delete_indicador`,
`get_biblioteca_categorias`, `get_biblioteca_indicadores`. Note the getters are
plural. When `tenantId` is omitted it is resolved from the token via `get_me`.
`save_variable` / `save_indicador` take a JSON object in `data`.

## DSL examples

```
QUERY roi PERIOD 2024 GRANULARITY monthly
DRILL ventas BY DIMENSION region LAST 12 MONTHS
INSPECT INDICATORS
INSPECT INDICATOR roi
INSPECT DIMENSIONS OF ventas
DEFINE INDICATOR roi FORMULA: utilidad / ventas UNIT: %      (write, mcp-siag only)
```
