{
  "name": "mcp-conta-query",
  "description": "READ-ONLY access to the PascalAI accounting system (ConServer, Colombia, multi-tenant by NIT). Same 25 domain tools as mcp-conta (conta_sistema, conta_puc, conta_terceros, conta_comprobantes, conta_reportes, conta_nomina, conta_ventas, conta_pos, conta_crm, ...) but every write operation (Save/Delete/Contabilizar/Anular/Cerrar/Importar/...) is hidden from the tool descriptions and rejected client-side before any request is sent. Safe to expose to autonomous agents even when the configured user is an admin. operation:\"help\" returns every available operation of the module with its documentation and expected params. For writes use mcp-conta.",
  "version": "1.0.1",
  "category": "accounting",
  "config": [
    {
      "key": "CONTA_URL",
      "label": "URL del servidor",
      "default": "https://conta.gustavoenriquez.com",
      "help": "Direccion del servidor de contabilidad, sin / al final"
    },
    {
      "key": "CONTA_LOGIN",
      "label": "Usuario",
      "required": true,
      "help": "Login del usuario en el sistema contable"
    },
    {
      "key": "CONTA_NIT",
      "label": "NIT de la empresa",
      "required": true,
      "help": "NIT de la empresa (sin digito de verificacion) que se consultara por omision. Si llevas varias empresas, el asistente puede cambiar por llamada con el argumento nit"
    },
    {
      "key": "CONTA_PASSWORD",
      "label": "Contrasena",
      "secret": true,
      "required": true,
      "help": "Contrasena del usuario; se guarda cifrada en tu equipo y nunca pasa por el chat"
    }
  ],
  "inputSchema": {
    "type": "object",
    "properties": {
      "operation": {
        "type": "string",
        "description": "Read operation to execute (method name without the CON_ prefix, e.g. GetPlanCuentas, GetComprobantes, RPT_BalancePrueba). Use \"help\" to list every operation of the module with docs and params."
      },
      "params": {
        "type": "string",
        "description": "JSON object with the parameters of the operation, e.g. {\"fecha_desde\":\"2026-01-01\",\"fecha_hasta\":\"2026-01-31\"}. Omit for operations without parameters. Dates ISO yyyy-mm-dd; lists usually paginate with page/page_size."
      },
      "nit": {
        "type": "string",
        "description": "Company (nit_empresa / tenant) to query. Omit to use CONTA_NIT. It is a scope selector, NOT a credential: the server only accepts a company where the configured user actually has an account, so a foreign NIT gets a 401. List the available ones with conta_sistema operation:\"GetMisEmpresas\"."
      }
    },
    "required": [
      "operation"
    ]
  },
  "env": {
    "CONTA_URL": "Base server URL, no trailing slash (default https://conta.gustavoenriquez.com)",
    "CONTA_LOGIN": "User login (required)",
    "CONTA_NIT": "Company NIT / tenant (required)",
    "CONTA_PASSWORD": "Plain password, hashed in-process with SHA-256 (required unless CONTA_PASSWORD_SHA256)",
    "CONTA_PASSWORD_SHA256": "Pre-hashed password, takes precedence over CONTA_PASSWORD"
  },
  "examples": [
    {
      "description": "Chart of accounts of the company",
      "input": {
        "tool": "conta_puc",
        "operation": "GetPlanCuentas",
        "params": "{}"
      },
      "output": [
        {
          "codigo": "110505",
          "nombre": "Caja general"
        }
      ]
    },
    {
      "description": "Vouchers of a date range",
      "input": {
        "tool": "conta_comprobantes",
        "operation": "GetComprobantes",
        "params": "{\"fecha_desde\":\"2026-01-01\",\"fecha_hasta\":\"2026-12-31\"}"
      },
      "output": [
        {
          "tipo_codigo": "FV",
          "numero": 14,
          "estado": "CONTABILIZADO"
        }
      ]
    },
    {
      "description": "A write operation is rejected client-side",
      "input": {
        "tool": "conta_puc",
        "operation": "SaveCuenta",
        "params": "{}"
      },
      "output": {
        "ok": false,
        "error": "\"SaveCuenta\" modifica datos y este servidor es de solo lectura."
      }
    }
  ],
  "tags": [
    "contabilidad",
    "accounting",
    "colombia",
    "erp",
    "reportes",
    "consultas",
    "readonly",
    "query",
    "safe",
    "agent",
    "datasnap"
  ],
  "pai_usage": "uses toolslib;\nvar Tool := LoadTool('mcp-conta-query');\nvar R := Tool.Call(JsonObj(['tool','conta_reportes','operation','RPT_EstadoResultados','params','{\"anio\":2026}']));"
}
