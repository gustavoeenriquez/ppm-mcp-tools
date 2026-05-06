# ppm-mcp-tools

Source code for **45 MCP (Model Context Protocol) tools** published on [registry.pascalai.org](https://registry.pascalai.org) — the PascalAI Package Manager.

Built with **Delphi 12 Athens** targeting Win64 and Linux64 (where noted).

---

## Tools

### Databases (FireDAC)
| Tool | Description | Platform | Install |
|------|-------------|----------|---------|
| [mcp-postgres](./mcp-postgres/) | Execute SQL queries on PostgreSQL databases | Win64 | `ppm install mcp-postgres` |
| [mcp-mysql](./mcp-mysql/) | Connect and query MySQL / MariaDB databases | Win64 | `ppm install mcp-mysql` |
| [mcp-mssql](./mcp-mssql/) | SQL Server queries and schema inspection | Win64 | `ppm install mcp-mssql` |
| [mcp-sqlite](./mcp-sqlite/) | Work with local SQLite database files | Win64 | `ppm install mcp-sqlite` |
| [mcp-oracle](./mcp-oracle/) | Connect to Oracle databases via FireDAC | Win64 | `ppm install mcp-oracle` |
| [mcp-firebird](./mcp-firebird/) | Firebird / InterBase database operations | Win64 | `ppm install mcp-firebird` |
| [mcp-odbc](./mcp-odbc/) | Generic ODBC datasource access | Win64 | `ppm install mcp-odbc` |
| [mcp-redis](./mcp-redis/) | Redis client using RESP protocol (no external DLL) | Win64 | `ppm install mcp-redis` |

### Email & Messaging
| Tool | Description | Platform | Install |
|------|-------------|----------|---------|
| [mcp-smtp](./mcp-smtp/) | Send emails via SMTP — HTML/text, attachments, TLS | Win64 | `ppm install mcp-smtp` |
| [mcp-imap](./mcp-imap/) | Read and search emails via IMAP | Win64 | `ppm install mcp-imap` |
| [mcp-telegram](./mcp-telegram/) | Send and receive Telegram messages via Bot API | Win64 | `ppm install mcp-telegram` |

### File System & Shell
| Tool | Description | Platform | Install |
|------|-------------|----------|---------|
| [mcp-fs](./mcp-fs/) | File system operations — read, write, list, copy, move, delete, watch | Win64 + Linux64 | `ppm install mcp-fs` |
| [mcp-file-reader](./mcp-file-reader/) | Read local files as text with encoding detection | Win64 + Linux64 | `ppm install mcp-file-reader` |
| [mcp-ini](./mcp-ini/) | Read and write INI configuration files | Win64 + Linux64 | `ppm install mcp-ini` |
| [mcp-shell](./mcp-shell/) | Execute shell commands (cmd / PowerShell / bash) and capture output | Win64 + Linux64 | `ppm install mcp-shell` |
| [mcp-ftp](./mcp-ftp/) | FTP client — list, upload, download, delete, rename | Win64 | `ppm install mcp-ftp` |

### Documents & Data Files
| Tool | Description | Platform | Install |
|------|-------------|----------|---------|
| [mcp-pdf](./mcp-pdf/) | Read PDF files — extract text, metadata, search, split, merge, rotate, watermark, fill forms | Win64 + Linux64 | `ppm install mcp-pdf` |
| [mcp-excel](./mcp-excel/) | Excel (.xlsx) — list sheets, read/write ranges | Win64 + Linux64 | `ppm install mcp-excel` |
| [mcp-csv](./mcp-csv/) | CSV — read, write, filter, sort, column stats, head/tail | Win64 + Linux64 | `ppm install mcp-csv` |
| [mcp-xml](./mcp-xml/) | XML — parse, query by path/tag, format, minify, convert to JSON | Win64 + Linux64 | `ppm install mcp-xml` |
| [mcp-extract](./mcp-extract/) | Convert local files to Markdown — PDF, DOCX, XLSX, PPTX, EPUB, HTML, CSV, JSON, XML, RTF and more | Win64 + Linux64 | `ppm install mcp-extract` |

### Web & Network
| Tool | Description | Platform | Install |
|------|-------------|----------|---------|
| [mcp-webcrawl](./mcp-webcrawl/) | Fetch URLs as Markdown — static HTTP (`fetch_url`) and JS-rendered pages via headless Chrome (`fetch_url_js`) | Win64 + Linux64 | `ppm install mcp-webcrawl` |
| [mcp-fetch](./mcp-fetch/) | General-purpose HTTP client — GET, POST, PUT, PATCH, DELETE, HEAD; custom headers, timeout, body | Win64 | `ppm install mcp-fetch` |
| [mcp-network](./mcp-network/) | Network diagnostics — ping, traceroute, DNS lookup, port scan | Win64 | `ppm install mcp-network` |

### Text & Data Processing
| Tool | Description | Platform | Install |
|------|-------------|----------|---------|
| [mcp-json-query](./mcp-json-query/) | JSON — validate, format, minify, get by path, list keys/values, flatten, merge | Win64 + Linux64 | `ppm install mcp-json-query` |
| [mcp-text-transform](./mcp-text-transform/) | Text transformation — case conversion, trim, reverse, replace, truncate, pad, encode/decode Base64/URL, slug, word-wrap | Win64 + Linux64 | `ppm install mcp-text-transform` |
| [mcp-regex](./mcp-regex/) | Regular expressions — test, find all matches, extract groups, replace, split, validate patterns | Win64 + Linux64 | `ppm install mcp-regex` |
| [mcp-tokenizer](./mcp-tokenizer/) | Token utilities — count tokens, encode, truncate to limit, split into chunks with overlap, estimate cost | Win64 + Linux64 | `ppm install mcp-tokenizer` |
| [mcp-hash](./mcp-hash/) | Cryptographic hashing — MD5, SHA1, SHA256, SHA384, SHA512, CRC32; hash strings or files, compare | Win64 | `ppm install mcp-hash` |
| [mcp-compress](./mcp-compress/) | ZIP compression — list, info, compress (files or folder), extract, add entries | Win64 | `ppm install mcp-compress` |
| [mcp-diff](./mcp-diff/) | Apply unified diffs to files and parse diff structure | Win64 | `ppm install mcp-diff` |

### Storage & Memory
| Tool | Description | Platform | Install |
|------|-------------|----------|---------|
| [mcp-kv](./mcp-kv/) | Persistent key-value store with namespace isolation — set, get, delete, list, search, append, count | Win64 | `ppm install mcp-kv` |
| [mcp-memory](./mcp-memory/) | In-memory key-value store with JSON file persistence | Win64 | `ppm install mcp-memory` |

### System
| Tool | Description | Platform | Install |
|------|-------------|----------|---------|
| [mcp-git](./mcp-git/) | Git repository inspection — status, log, diff, branches, remote info | Win64 | `ppm install mcp-git` |
| [mcp-process](./mcp-process/) | Windows process management — list, kill, start, get info | Win64 | `ppm install mcp-process` |
| [mcp-screen](./mcp-screen/) | Capture the Windows desktop (full screen or area) as PNG, JPEG or BMP | Win64 | `ppm install mcp-screen` |
| [mcp-registry](./mcp-registry/) | Windows Registry access — read, write, list keys/values, delete, exists | Win64 | `ppm install mcp-registry` |
| [mcp-audio](./mcp-audio/) | Audio file info, WAV conversion, waveform amplitude data | Win64 + Linux64 | `ppm install mcp-audio` |

### Web Services & APIs
| Tool | Description | Platform | Install |
|------|-------------|----------|---------|
| [mcp-weather](./mcp-weather/) | Current weather and 3-day forecast via wttr.in (free, no API key) | Win64 | `ppm install mcp-weather` |
| [mcp-maps](./mcp-maps/) | Geocoding and place search via OpenStreetMap Nominatim (free, no API key) | Win64 | `ppm install mcp-maps` |
| [mcp-rss](./mcp-rss/) | RSS 2.0 and Atom feed reader — fetch, latest N items, search | Win64 | `ppm install mcp-rss` |
| [mcp-wikipedia](./mcp-wikipedia/) | Wikipedia article search and retrieval via REST API (free, no API key) | Win64 | `ppm install mcp-wikipedia` |
| [mcp-currency](./mcp-currency/) | Currency exchange rates and conversion via open.er-api.com (free, no API key) | Win64 | `ppm install mcp-currency` |
| [mcp-calculator](./mcp-calculator/) | Evaluate mathematical expressions — arithmetic, exponentiation, common functions | Win64 | `ppm install mcp-calculator` |
| [mcp-datetime](./mcp-datetime/) | Parse and reformat datetime strings across timezones and formats | Win64 | `ppm install mcp-datetime` |

---

## Shared
The [`_shared/`](./_shared/) folder contains `MCPTool.FDBase.pas` — the base FireDAC class used by all database tools.

---

## Building

**Requirements:**
- Delphi 12 Athens
- FireDAC (included with Delphi) — required by database tools
- [MakerAI](https://github.com/gustavoeenriquez/MakerAI) — MCP server infrastructure (must be in IDE Library path)
- [delphi-libraries](https://github.com/gustavoeenriquez/delphi-libraries) — required by `mcp-extract` and `mcp-webcrawl`

For **mcp-extract** and **mcp-webcrawl**, clone `delphi-libraries` alongside this repo and add the following to the IDE Library path (Win64 and Linux64):

```
...\delphi-libraries\extract\Src
...\delphi-libraries\extract\Src\Converters
...\delphi-libraries\pdf\Src\Core
...\delphi-libraries\webcrawl\Src
```

**mcp-webcrawl** additionally requires `chromedriver.exe` (matching your Chrome version) in PATH or passed via the `driverPath` parameter — only needed for `fetch_url_js`.  
Download: https://googlechromelabs.github.io/chrome-for-testing/

```bash
# Build all tools at once
msbuild AllMcpGroup.groupproj /t:Build /p:Config=Release /p:Platform=Win64

# Build for Linux64
msbuild AllMcpGroup.groupproj /t:Build /p:Config=Release /p:Platform=Linux64

# Build a single tool
msbuild mcp-hash/mcp-hash.dproj /t:Build /p:Config=Release /p:Platform=Win64
```

---

## Install via PPM

```powershell
# Windows
irm https://registry.pascalai.org/install.ps1 | iex

# Linux
curl -fsSL https://registry.pascalai.org/install.sh | bash
```

Then install any tool:

```bash
ppm install mcp-hash
ppm install mcp-pdf
ppm install mcp-kv
```

---

## License

MIT — © 2026 [Gustavo Enriquez](https://github.com/gustavoeenriquez) / [PascalAI](https://registry.pascalai.org)
