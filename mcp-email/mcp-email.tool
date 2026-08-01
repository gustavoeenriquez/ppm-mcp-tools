{
  "name": "mcp-email",
  "description": "Correo completo en un solo conector: lee y gestiona el buzón por IMAP (carpetas, listar, buscar, leer, mover, borrar, marcar) y envía por SMTP (texto, HTML, CC/BCC, adjuntos). Compatible con Gmail (contraseña de aplicación), Outlook, Zoho y cualquier proveedor IMAP/SMTP estándar.",
  "version": "1.0.1",
  "category": "communication",
  "config": [
    { "key": "MAIL_USER", "label": "Correo (usuario)", "required": true,
      "help": "Tu dirección de correo, p.ej. tu@gmail.com" },
    { "key": "MAIL_PASS", "label": "Contraseña de aplicación", "secret": true, "required": true,
      "help": "Para Gmail se genera una contraseña de aplicación (requiere verificación en 2 pasos). No es tu contraseña normal.",
      "help_url": "https://myaccount.google.com/apppasswords" },
    { "key": "MAIL_IMAP_HOST", "label": "Servidor IMAP (lectura)", "default": "imap.gmail.com",
      "help": "Gmail: imap.gmail.com · Outlook: outlook.office365.com · Zoho: imap.zoho.com" },
    { "key": "MAIL_SMTP_HOST", "label": "Servidor SMTP (envío)", "default": "smtp.gmail.com",
      "help": "Gmail: smtp.gmail.com · Outlook: smtp.office365.com · Zoho: smtp.zoho.com" },
    { "key": "MAIL_FROM_NAME", "label": "Nombre del remitente",
      "help": "Nombre visible en los correos que envíes (opcional)" }
  ],
  "tools": {
    "mcp-imap": "folders, list, get, search, move, delete, mark — operaciones por UID, más recientes primero",
    "mcp-smtp": "envío con texto plano, HTML, CC/BCC y adjuntos"
  },
  "defaults": "IMAP: puerto 993 ssl. SMTP: puerto 587 starttls. Ajustables con MAIL_IMAP_PORT/MAIL_IMAP_SSL/MAIL_SMTP_PORT/MAIL_SMTP_SSL.",
  "tags": ["email","imap","smtp","mail","gmail","outlook","zoho","connector","agent"]
}
