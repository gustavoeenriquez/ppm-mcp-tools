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

### File system & shell
| Tool | Description | Install |
|------|-------------|---------|
| [mcp-fs](./mcp-fs/) | Modern file system operations (read, write, list, copy, move, delete) | `ppm install mcp-fs` |
| [mcp-file-reader](./mcp-file-reader/) | Read local files as text | `ppm install mcp-file-reader` |
| [mcp-ini](./mcp-ini/) | Read and write INI configuration files | `ppm install mcp-ini` |
| [mcp-shell](./mcp-shell/) | Execute shell commands (cmd, PowerShell, bash) and capture output | `ppm install mcp-shell` |

### Document extraction
| Tool | Description | Install |
|------|-------------|---------|
| [mcp-extract](./mcp-extract/) | Convert local files to Markdown — PDF, DOCX, XLSX, PPTX, EPUB, HTML, CSV, JSON, XML, RTF, INI, TXT and more | `ppm install mcp-extract` |

### Web
| Tool | Description | Install |
|------|-------------|---------|
| [mcp-webcrawl](./mcp-webcrawl/) | Fetch URLs and return content as Markdown — static HTTP fetch (`fetch_url`) and JS-rendered pages via headless Chrome (`fetch_url_js`) | `ppm install mcp-webcrawl` |

## Shared
The [`_shared/`](./_shared/) folder contains `MCPTool.FDBase.pas` — the base FireDAC class used by all database tools.

## Building

Requirements:
- Delphi 12 Athens
- FireDAC (included with Delphi) — required by database tools
- [MakerAI](https://github.com/gustavoeenriquez/MakerAI) — MCP server infrastructure (must be in IDE Library path)
- [delphi-libraries](https://github.com/gustavoeenriquez/delphi-libraries) — required by `mcp-extract` and `mcp-webcrawl`

For **mcp-extract** and **mcp-webcrawl**, clone `delphi-libraries` alongside this repo and
add the following paths to the IDE Library path (Win64):

```
...\delphi-libraries\extract\Src
...\delphi-libraries\extract\Src\Converters
...\delphi-libraries\pdf\Src\Core
...\delphi-libraries\webcrawl\Src
```

**mcp-webcrawl** additionally requires `chromedriver.exe` (matching your Chrome version) in
PATH or passed via the `driver_path` parameter at runtime — only needed for `fetch_url_js`.
Download: https://googlechromelabs.github.io/chrome-for-testing/

```bash
# Build all 16 tools at once
msbuild AllMcpGroup.groupproj /t:Build /p:Config=Release /p:Platform=Win64

# Build a single tool
msbuild mcp-postgres/mcp-postgres.dproj /t:Build /p:Config=Release /p:Platform=Win64

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
