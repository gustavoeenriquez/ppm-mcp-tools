# ppm-mcp-tools

Source code for MCP (Model Context Protocol) tools published on [PPM Registry](https://ppm.pascalai.org) — the PascalAI Package Manager.

Built with **Delphi 12 Athens** targeting Win64 and Linux64.

## Tools included

### Databases (FireDAC)
| Tool | Description | Install |
|------|-------------|---------|
| [mcp-postgres](./mcp-postgres/) | Execute SQL queries on PostgreSQL databases | `ppm install mcp-postgres` |
| [mcp-mysql](./mcp-mysql/) | Connect and query MySQL / MariaDB databases | `ppm install mcp-mysql` |
| [mcp-mssql](./mcp-mssql/) | SQL Server queries and schema inspection | `ppm install mcp-mssql` |
| [mcp-sqlite](./mcp-sqlite/) | Work with local SQLite database files | `ppm install mcp-sqlite` |
| [mcp-oracle](./mcp-oracle/) | Connect to Oracle databases via FireDAC | `ppm install mcp-oracle` |
| [mcp-firebird](./mcp-firebird/) | Firebird / InterBase database operations | `ppm install mcp-firebird` |
| [mcp-odbc](./mcp-odbc/) | Generic ODBC datasource access | `ppm install mcp-odbc` |

### Email
| Tool | Description | Install |
|------|-------------|---------|
| [mcp-smtp](./mcp-smtp/) | Send emails via SMTP (HTML/text, attachments, TLS) | `ppm install mcp-smtp` |
| [mcp-imap](./mcp-imap/) | Read and search emails via IMAP | `ppm install mcp-imap` |

### Messaging
| Tool | Description | Install |
|------|-------------|---------|
| [mcp-telegram](./mcp-telegram/) | Send and receive Telegram messages via Bot API | `ppm install mcp-telegram` |

## Shared
The [`_shared/`](./_shared/) folder contains `MCPTool.FDBase.pas` — the base FireDAC class used by all database tools.

## Building

Requirements:
- Delphi 12 Athens
- FireDAC (included with Delphi)
- [Horse](https://github.com/HashLoad/horse) HTTP framework

```bash
# Build a single tool for Linux64
msbuild mcp-postgres/mcp-postgres.dproj /t:Build /p:Config=Release /p:Platform=Linux64

# Install via PPM
ppm install mcp-postgres
```

## Install PPM

```powershell
# Windows
irm https://ppm.pascalai.org/install.ps1 | iex

# Linux
curl -fsSL https://ppm.pascalai.org/install.sh | bash
```

## License

MIT — © 2026 [Gustavo Enriquez](https://github.com/gustavoeenriquez) / [PascalAI](https://ppm.pascalai.org)
