{
  "name": "mcp-conta",
  "description": "FULL access to the PascalAI accounting system (ConServer, Colombia, multi-tenant by NIT). Exposes 25 MCP tools, one per domain: conta_sistema, conta_empresa, conta_puc, conta_terceros, conta_comprobantes, conta_periodos, conta_retenciones, conta_centros_costo, conta_reportes, conta_activos_fijos, conta_presupuestos, conta_conciliacion, conta_flujo_efectivo, conta_exogena, conta_facturacion_electronica, conta_importacion, conta_nomina, conta_inventario, conta_ventas, conta_compras, conta_cuentas_pagar, conta_tesoreria, conta_cobranza, conta_pos, conta_crm. Every tool takes the same arguments (schema below). operation:\"help\" returns every operation of the module with its documentation and expected params, extracted from the server source. Write operations are marked * in each tool description. For a read-only surface use mcp-conta-query.",
  "version": "1.0.1",
  "category": "accounting",
  "config": [
    { "key": "CONTA_URL", "label": "URL del servidor",
      "default": "https://conta.gustavoenriquez.com",
      "help": "Direccion del servidor de contabilidad, sin / al final" },
    { "key": "CONTA_LOGIN", "label": "Usuario", "required": true,
      "help": "Login del usuario en el sistema contable" },
    { "key": "CONTA_NIT", "label": "NIT de la empresa", "required": true,
      "help": "NIT de la empresa (sin digito de verificacion) sobre la que trabajara el asistente por omision. Si llevas varias empresas, el asistente puede cambiar por llamada con el argumento nit" },
    { "key": "CONTA_PASSWORD", "label": "Contrasena", "secret": true, "required": true,
      "help": "Contrasena del usuario; se guarda cifrada en tu equipo y nunca pasa por el chat" },
    { "key": "CONTA_NIT_STRICT", "label": "Exigir empresa en cada escritura",
      "default": "0",
      "help": "Ponlo en 1 si llevas mas de una empresa: entonces toda operacion que modifique datos debe indicar el nit, para que no se contabilice en la empresa equivocada por omision" }
  ],
  "inputSchema": {
    "type": "object",
    "properties": {
      "operation": {
        "type": "string",
        "description": "Operation to execute (method name without the CON_ prefix, e.g. GetPlanCuentas, SaveComprobante, RPT_BalancePrueba). Use \"help\" to list every operation of the module with docs and params."
      },
      "params": {
        "type": "string",
        "description": "JSON object with the parameters of the operation, e.g. {\"fecha_desde\":\"2026-01-01\",\"fecha_hasta\":\"2026-01-31\"}. Omit for operations without parameters. Dates ISO yyyy-mm-dd; lists usually paginate with page/page_size."
      },
      "nit": {
        "type": "string",
        "description": "Company (nit_empresa / tenant) to operate on. Omit to use CONTA_NIT. It is a scope selector, NOT a credential: the server only accepts a company where the configured user actually has an account, so a foreign NIT gets a 401. List the available ones with conta_sistema operation:\"GetMisEmpresas\". With CONTA_NIT_STRICT=1 it is mandatory on every write operation."
      }
    },
    "required": ["operation"]
  },
  "env": {
    "CONTA_URL": "Base server URL, no trailing slash (default https://conta.gustavoenriquez.com)",
    "CONTA_LOGIN": "User login (required)",
    "CONTA_NIT": "Company NIT / tenant (required)",
    "CONTA_PASSWORD": "Plain password, hashed in-process with SHA-256 (required unless CONTA_PASSWORD_SHA256)",
    "CONTA_PASSWORD_SHA256": "Pre-hashed password, takes precedence over CONTA_PASSWORD",
    "CONTA_NIT_STRICT": "1/true = every write operation must carry an explicit \"nit\" argument (multi-company installs). Default off"
  },
  "examples": [
    {
      "description": "Discover the operations of a module",
      "input": { "tool": "conta_reportes", "operation": "help" },
      "output": { "operations": ["RPT_BalancePrueba", "RPT_LibroDiario", "..."] }
    },
    {
      "description": "Trial balance for a period",
      "input": { "tool": "conta_reportes", "operation": "RPT_BalancePrueba", "params": "{\"anio\":2026,\"mes_desde\":1,\"mes_hasta\":12}" },
      "output": [ { "codigo": "110505", "nombre": "Caja general", "saldo_final_debito": 1071000 } ]
    },
    {
      "description": "Create a draft voucher (double-entry, debits must equal credits)",
      "input": { "tool": "conta_comprobantes", "operation": "SaveComprobante", "params": "{\"tipo_codigo\":\"CG\",\"fecha\":\"2026-07-20\",\"descripcion\":\"Ajuste\",\"movimientos\":[{\"linea\":1,\"cuenta_codigo\":\"110505\",\"debito\":1000,\"credito\":0},{\"linea\":2,\"cuenta_codigo\":\"130505\",\"debito\":0,\"credito\":1000}]}" },
      "output": { "tipo_codigo": "CG", "numero": 15, "estado": "BORRADOR" }
    }
  ],
  "tags": ["contabilidad","accounting","colombia","erp","puc","dian","comprobantes","nomina","ventas","pos","crm","agent","datasnap"],
  "pai_usage": "uses toolslib;\nvar Tool := LoadTool('mcp-conta');\nvar R := Tool.Call(JsonObj(['tool','conta_reportes','operation','RPT_BalancePrueba','params','{\"anio\":2026,\"mes_desde\":1,\"mes_hasta\":12}']));"
}
