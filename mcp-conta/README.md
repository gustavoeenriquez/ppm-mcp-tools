# mcp-conta / mcp-conta-query

Two MCP servers that expose the **PascalAI accounting system** (ConServer,
Colombia) to AI agents, built on the same MakerAI stack as the rest of
`ppm-mcp-tools`. They are HTTP clients of the ConServer DataSnap REST server
(`/datasnap/rest/TConServerMethods`), the backend at
`e:\copilot\contabilidad\`.

| Tool | Scope | Default port | Binary |
|------|-------|--------------|--------|
| `mcp-conta-query` | **Read-only** — only `Get*`/`RPT_*` style reads | 8781 | `mcp-conta-query/dist/` |
| `mcp-conta` | **Full** — all 337 operations incl. writes | 8780 | `mcp-conta/dist/` |

Shared pieces:

- `_shared/MCPTool.ContaClient.pas` — HTTP client (Basic auth, DataSnap
  envelope, GET with POST fallback for large payloads).
- `mcp-conta/MCPTool.Conta.Catalog.pas` — **generated** catalog: 338 public
  methods of `uConServerMethods.pas` grouped into 25 domain modules.
  Regenerate with `gen_catalog_pas.py` (extract via `extract_catalog.py`)
  whenever the server adds methods. NOTE: those two scripts are no longer in
  the repo (2026-09-06); until they are recovered, a new method has to be added
  to the catalog by hand — the doc string is the interface comment of
  `uConServerMethods.pas` verbatim, and that comment IS what the model reads in
  `operation:"help"`, so a stale comment is worse than none.
- `mcp-conta/MCPTool.Conta.pas` — one generic tool class instantiated per
  module; the read-only flag hides/rejects write operations client-side.

## Tool surface (25 tools, one per domain)

`conta_sistema`, `conta_empresa`, `conta_puc`, `conta_terceros`,
`conta_comprobantes`, `conta_periodos`, `conta_retenciones`,
`conta_centros_costo`, `conta_reportes`, `conta_activos_fijos`,
`conta_presupuestos`, `conta_conciliacion`, `conta_flujo_efectivo`,
`conta_exogena`, `conta_facturacion_electronica`, `conta_importacion`,
`conta_nomina`, `conta_inventario`, `conta_ventas`, `conta_compras`,
`conta_cuentas_pagar`, `conta_tesoreria`, `conta_cobranza`, `conta_pos`,
`conta_crm`.

Every tool takes the same arguments:

| arg | required | meaning |
|-----|----------|---------|
| `operation` | yes | Method name (without the `CON_` prefix), or `help` |
| `params` | no | JSON object with the method parameters |
| `login`, `nit`, `password` | no | Per-call credential override |

`operation:"help"` returns every operation of the module with the
documentation extracted from the server source (including expected params)
and its write flag. **Agents should call `help` before using an unfamiliar
module** — write operations are marked `*` in the tool description.

## Configuration (environment variables)

Auth is HTTP Basic on every request (stateless, no login endpoint):
`base64("login,nit_empresa:sha256hex(password)")`.

| Variable | Required | Default | Meaning |
|----------|----------|---------|---------|
| `CONTA_URL` | no | `https://conta.gustavoenriquez.com` | Base server URL |
| `CONTA_LOGIN` | yes | — | User login |
| `CONTA_NIT` | yes | — | Company NIT (tenant) |
| `CONTA_PASSWORD` | yes* | — | Plain password (hashed in-process) |
| `CONTA_PASSWORD_SHA256` | yes* | — | Pre-hashed password (takes precedence) |

\* one of the two.

## Build

```bat
:: from ppm-mcp-tools, after loading rsvars.bat (Studio 37.0)
msbuild mcp-conta\mcp-conta.dproj             /t:Build /p:Config=Release /p:Platform=Win64
msbuild mcp-conta-query\mcp-conta-query.dproj /t:Build /p:Config=Release /p:Platform=Win64
```

Or run `build_conta.bat` at the `ppm-mcp-tools` root. Requires the MakerAI
package on the library path. Linux64 via `/p:Platform=Linux64` (output in
`dist-linux-x64/`).

## Register in an MCP client

Transport is **stdio** by default (also `--protocol http|sse --port N`):

```json
{
  "mcpServers": {
    "conta-query": {
      "command": "E:\\Copilot\\spas\\ppm-mcp-tools\\mcp-conta-query\\dist\\mcp-conta-query.exe",
      "env": {
        "CONTA_URL": "https://conta.gustavoenriquez.com",
        "CONTA_LOGIN": "admin",
        "CONTA_NIT": "900000001",
        "CONTA_PASSWORD": "***"
      }
    },
    "conta": {
      "command": "E:\\Copilot\\spas\\ppm-mcp-tools\\mcp-conta\\dist\\mcp-conta.exe",
      "env": {
        "CONTA_URL": "https://conta.gustavoenriquez.com",
        "CONTA_LOGIN": "admin",
        "CONTA_NIT": "900000001",
        "CONTA_PASSWORD": "***"
      }
    }
  }
}
```

Give autonomous agents `conta-query`; reserve `conta` (full) for supervised
sessions.

## Typical agent flow

```
conta_reportes  operation:"help"
conta_reportes  operation:"RPT_BalancePrueba"
                params:"{\"fecha_desde\":\"2026-01-01\",\"fecha_hasta\":\"2026-12-31\"}"
conta_comprobantes operation:"GetComprobantes" params:"{...}"
```

Verified 2026-07-20 against the production VPS: tools/list (25 tools),
help, GetVersion, GetMiPerfil, GetPlanCuentas (425 cuentas), GetTerceros,
GetComprobantes, RPT_BalancePrueba; write ops correctly rejected by
mcp-conta-query.
