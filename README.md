# ppm-mcp-tools

Source code for **98 MCP (Model Context Protocol) tools** published on [registry.pascalai.org](https://registry.pascalai.org) — the PascalAI Package Manager.

Built with **Delphi 12 Athens** targeting Win64 (and Linux64 where noted).

---

## Tools

### Databases — Relational (FireDAC)
| Tool | Description | Platform | Install |
|------|-------------|----------|---------|
| [mcp-postgres](./mcp-postgres/) | Execute SQL queries on PostgreSQL databases | Win64 | `ppm install mcp-postgres` |
| [mcp-mysql](./mcp-mysql/) | Connect and query MySQL / MariaDB databases | Win64 | `ppm install mcp-mysql` |
| [mcp-mssql](./mcp-mssql/) | SQL Server queries and schema inspection | Win64 | `ppm install mcp-mssql` |
| [mcp-sqlite](./mcp-sqlite/) | Work with local SQLite database files | Win64 | `ppm install mcp-sqlite` |
| [mcp-oracle](./mcp-oracle/) | Connect to Oracle databases via FireDAC | Win64 | `ppm install mcp-oracle` |
| [mcp-firebird](./mcp-firebird/) | Firebird / InterBase database operations | Win64 | `ppm install mcp-firebird` |
| [mcp-odbc](./mcp-odbc/) | Generic ODBC datasource access | Win64 | `ppm install mcp-odbc` |
| [mcp-db2](./mcp-db2/) | IBM DB2 database access via FireDAC | Win64 | `ppm install mcp-db2` |
| [mcp-sybase](./mcp-sybase/) | Sybase ASA / SAP SQL Anywhere via FireDAC | Win64 | `ppm install mcp-sybase` |
| [mcp-informix](./mcp-informix/) | IBM Informix database via FireDAC | Win64 | `ppm install mcp-informix` |
| [mcp-ads](./mcp-ads/) | Advantage Database Server via FireDAC | Win64 | `ppm install mcp-ads` |
| [mcp-access](./mcp-access/) | Microsoft Access (.accdb/.mdb) via FireDAC DAO driver. Requires Access Database Engine 2016+ (64-bit) | Win64 | `ppm install mcp-access` |

### Databases — NoSQL & Caching
| Tool | Description | Platform | Install |
|------|-------------|----------|---------|
| [mcp-redis](./mcp-redis/) | Redis client using RESP protocol (no external DLL) | Win64 | `ppm install mcp-redis` |
| [mcp-mongodb](./mcp-mongodb/) | MongoDB via FireDAC — query, insert, update, delete, aggregate | Win64 | `ppm install mcp-mongodb` |

### Vector Databases
| Tool | Description | Platform | Install |
|------|-------------|----------|---------|
| [mcp-qdrant](./mcp-qdrant/) | Qdrant vector database via REST API — collections, upsert, search, scroll | Win64 | `ppm install mcp-qdrant` |
| [mcp-chroma](./mcp-chroma/) | ChromaDB vector store via REST API v1 — add, upsert, query, metadata filtering | Win64 | `ppm install mcp-chroma` |
| [mcp-pinecone](./mcp-pinecone/) | Pinecone vector database — query, upsert, fetch, delete, index management | Win64 | `ppm install mcp-pinecone` |

### Cloud Storage
| Tool | Description | Platform | Install |
|------|-------------|----------|---------|
| [mcp-s3](./mcp-s3/) | Amazon S3 — list buckets/objects, upload, download, delete, presigned URLs | Win64 | `ppm install mcp-s3` |
| [mcp-dynamodb](./mcp-dynamodb/) | Amazon DynamoDB — get, put, update, delete, query, scan | Win64 | `ppm install mcp-dynamodb` |
| [mcp-gcs](./mcp-gcs/) | Google Cloud Storage — list, upload, download, delete objects | Win64 | `ppm install mcp-gcs` |
| [mcp-bigquery](./mcp-bigquery/) | Google BigQuery — run queries, list datasets/tables, get schema | Win64 | `ppm install mcp-bigquery` |
| [mcp-azure-blob](./mcp-azure-blob/) | Azure Blob Storage — list containers/blobs, upload, download, delete | Win64 | `ppm install mcp-azure-blob` |

### AI — LLM & Model APIs
| Tool | Description | Platform | Install |
|------|-------------|----------|---------|
| [mcp-azure-openai](./mcp-azure-openai/) | Azure OpenAI — chat completions, embeddings, via Azure endpoint | Win64 | `ppm install mcp-azure-openai` |
| [mcp-ollama](./mcp-ollama/) | Ollama local LLM server — generate, chat, list models, embeddings | Win64 | `ppm install mcp-ollama` |
| [mcp-perplexity](./mcp-perplexity/) | Perplexity AI — search-augmented chat completions | Win64 | `ppm install mcp-perplexity` |
| [mcp-replicate](./mcp-replicate/) | Replicate — run open-source AI models (image, text, audio) | Win64 | `ppm install mcp-replicate` |
| [mcp-huggingface](./mcp-huggingface/) | HuggingFace Inference API — text generation, classification, embeddings | Win64 | `ppm install mcp-huggingface` |

### AI — Search & Retrieval
| Tool | Description | Platform | Install |
|------|-------------|----------|---------|
| [mcp-brave-search](./mcp-brave-search/) | Brave Search API — web, news and image search | Win64 | `ppm install mcp-brave-search` |
| [mcp-exa](./mcp-exa/) | Exa AI semantic search — search, get contents, find similar | Win64 | `ppm install mcp-exa` |
| [mcp-serper](./mcp-serper/) | Serper Google Search API — web, news, images, places | Win64 | `ppm install mcp-serper` |
| [mcp-firecrawl](./mcp-firecrawl/) | FireCrawl — scrape pages as Markdown, crawl sites, extract structured data | Win64 | `ppm install mcp-firecrawl` |
| [mcp-jina](./mcp-jina/) | Jina AI — Reader API (URL to Markdown), embeddings, reranking | Win64 | `ppm install mcp-jina` |

### Finance & Crypto
| Tool | Description | Platform | Install |
|------|-------------|----------|---------|
| [mcp-alphavantage](./mcp-alphavantage/) | Alpha Vantage — stock quotes, OHLCV history, forex, crypto, indicators | Win64 | `ppm install mcp-alphavantage` |
| [mcp-coingecko](./mcp-coingecko/) | CoinGecko — crypto prices, market data, trending, coin details (free API) | Win64 | `ppm install mcp-coingecko` |
| [mcp-paypal](./mcp-paypal/) | PayPal REST API — orders, payouts, invoices, subscriptions | Win64 | `ppm install mcp-paypal` |

### CRM & SaaS
| Tool | Description | Platform | Install |
|------|-------------|----------|---------|
| [mcp-salesforce](./mcp-salesforce/) | Salesforce REST API — SOQL queries, CRUD on any sObject | Win64 | `ppm install mcp-salesforce` |
| [mcp-zendesk](./mcp-zendesk/) | Zendesk — tickets, users, organizations, comments | Win64 | `ppm install mcp-zendesk` |
| [mcp-freshdesk](./mcp-freshdesk/) | Freshdesk — tickets, contacts, agents, notes | Win64 | `ppm install mcp-freshdesk` |
| [mcp-shopify](./mcp-shopify/) | Shopify Admin API — products, orders, customers, inventory | Win64 | `ppm install mcp-shopify` |
| [mcp-mailchimp](./mcp-mailchimp/) | Mailchimp — lists, members, campaigns, stats | Win64 | `ppm install mcp-mailchimp` |
| [mcp-sendgrid](./mcp-sendgrid/) | SendGrid — send email, templates, contacts, delivery stats | Win64 | `ppm install mcp-sendgrid` |
| [mcp-linear](./mcp-linear/) | Linear issue tracker — teams, issues, projects, states via GraphQL API | Win64 | `ppm install mcp-linear` |
| [mcp-gitlab](./mcp-gitlab/) | GitLab REST API — projects, issues, merge requests, branches, commits, files | Win64 | `ppm install mcp-gitlab` |
| [mcp-zoom](./mcp-zoom/) | Zoom — meetings, participants, recordings, webinars | Win64 | `ppm install mcp-zoom` |

### Infrastructure & DevOps
| Tool | Description | Platform | Install |
|------|-------------|----------|---------|
| [mcp-docker](./mcp-docker/) | Docker — containers, images, volumes, networks via Docker Engine API | Win64 | `ppm install mcp-docker` |
| [mcp-kubernetes](./mcp-kubernetes/) | Kubernetes — pods, deployments, services, namespaces via kubectl/API | Win64 | `ppm install mcp-kubernetes` |
| [mcp-terraform](./mcp-terraform/) | Terraform — plan, apply, destroy, output, state via CLI | Win64 | `ppm install mcp-terraform` |
| [mcp-ansible](./mcp-ansible/) | Ansible — run playbooks, ad-hoc commands, inventory | Win64 | `ppm install mcp-ansible` |
| [mcp-prometheus](./mcp-prometheus/) | Prometheus — instant queries, range queries, metadata via HTTP API | Win64 | `ppm install mcp-prometheus` |

### Messaging & Streaming
| Tool | Description | Platform | Install |
|------|-------------|----------|---------|
| [mcp-kafka](./mcp-kafka/) | Apache Kafka — produce, consume, list topics, consumer groups | Win64 | `ppm install mcp-kafka` |
| [mcp-rabbitmq](./mcp-rabbitmq/) | RabbitMQ — publish, consume, queue management via Management API | Win64 | `ppm install mcp-rabbitmq` |
| [mcp-mqtt](./mcp-mqtt/) | MQTT — publish and subscribe to topics via broker | Win64 | `ppm install mcp-mqtt` |

### Protocols & APIs
| Tool | Description | Platform | Install |
|------|-------------|----------|---------|
| [mcp-graphql](./mcp-graphql/) | GraphQL client — execute queries and mutations against any GraphQL endpoint | Win64 | `ppm install mcp-graphql` |
| [mcp-grpc](./mcp-grpc/) | gRPC client — call remote procedures via reflection or descriptor | Win64 | `ppm install mcp-grpc` |
| [mcp-websocket](./mcp-websocket/) | WebSocket and HTTP client — ws_connect, http_get, http_post | Win64 | `ppm install mcp-websocket` |

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
| [mcp-ssh](./mcp-ssh/) | SSH client — exec remote commands, SFTP file operations, upload/download | Win64 | `ppm install mcp-ssh` |

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
| [mcp-webcrawl](./mcp-webcrawl/) | Fetch URLs as Markdown — static HTTP and JS-rendered pages via headless Chrome | Win64 + Linux64 | `ppm install mcp-webcrawl` |
| [mcp-fetch](./mcp-fetch/) | General-purpose HTTP client — GET, POST, PUT, PATCH, DELETE, HEAD | Win64 | `ppm install mcp-fetch` |
| [mcp-network](./mcp-network/) | Network diagnostics — ping, traceroute, DNS lookup, port scan | Win64 | `ppm install mcp-network` |
| [mcp-browser](./mcp-browser/) | Headless browser automation — navigate, get_text, screenshot, click, fill, execute_js | Win64 | `ppm install mcp-browser` |

### Text & Data Processing
| Tool | Description | Platform | Install |
|------|-------------|----------|---------|
| [mcp-json-query](./mcp-json-query/) | JSON — validate, format, minify, get by path, list keys/values, flatten, merge | Win64 + Linux64 | `ppm install mcp-json-query` |
| [mcp-text-transform](./mcp-text-transform/) | Text transformation — case conversion, trim, reverse, replace, truncate, encode/decode, slug | Win64 + Linux64 | `ppm install mcp-text-transform` |
| [mcp-regex](./mcp-regex/) | Regular expressions — test, find all matches, extract groups, replace, split | Win64 + Linux64 | `ppm install mcp-regex` |
| [mcp-tokenizer](./mcp-tokenizer/) | Token utilities — count tokens, encode, truncate, split into chunks with overlap | Win64 + Linux64 | `ppm install mcp-tokenizer` |
| [mcp-hash](./mcp-hash/) | Cryptographic hashing — MD5, SHA1, SHA256, SHA512, CRC32; hash strings or files | Win64 | `ppm install mcp-hash` |
| [mcp-compress](./mcp-compress/) | ZIP compression — list, info, compress, extract, add entries | Win64 | `ppm install mcp-compress` |
| [mcp-diff](./mcp-diff/) | Apply unified diffs to files and parse diff structure | Win64 | `ppm install mcp-diff` |
| [mcp-diffeditor](./mcp-diffeditor/) | File editor with fuzzy unified diff — view (line numbers), apply_diff, replace, replace_lines, insert_lines | Win64 | `ppm install mcp-diffeditor` |

### Storage & Memory
| Tool | Description | Platform | Install |
|------|-------------|----------|---------|
| [mcp-kv](./mcp-kv/) | Persistent key-value store with namespace isolation — set, get, delete, list, search, count | Win64 | `ppm install mcp-kv` |
| [mcp-memory](./mcp-memory/) | In-memory key-value store with JSON file persistence | Win64 | `ppm install mcp-memory` |

### Agent Utilities
| Tool | Description | Platform | Install |
|------|-------------|----------|---------|
| [mcp-notes](./mcp-notes/) | Markdown note store with BM25 full-text search — write, read, search, list, tag | Win64 | `ppm install mcp-notes` |
| [mcp-rag](./mcp-rag/) | Local RAG pipeline — ingest files/text, chunk+embed+store, search by query | Win64 | `ppm install mcp-rag` |
| [mcp-sequential-thinking](./mcp-sequential-thinking/) | Structured sequential thinking — create sessions, add thoughts, conclude | Win64 | `ppm install mcp-sequential-thinking` |
| [mcp-workflow](./mcp-workflow/) | Workflow management — define, start, track multi-step workflows with step status | Win64 | `ppm install mcp-workflow` |
| [mcp-code-exec](./mcp-code-exec/) | Execute code snippets via local runtime (Python, JS, Lua, shell) | Win64 | `ppm install mcp-code-exec` |

### System
| Tool | Description | Platform | Install |
|------|-------------|----------|---------|
| [mcp-git](./mcp-git/) | Git repository inspection — status, log, diff, branches, remote info | Win64 | `ppm install mcp-git` |
| [mcp-process](./mcp-process/) | Windows process management — list, kill, start, get info | Win64 | `ppm install mcp-process` |
| [mcp-screen](./mcp-screen/) | Capture the Windows desktop (full screen or area) as PNG, JPEG or BMP | Win64 | `ppm install mcp-screen` |
| [mcp-registry](./mcp-registry/) | Windows Registry access — read, write, list keys/values, delete | Win64 | `ppm install mcp-registry` |
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

The [`_shared/`](./_shared/) folder contains `MCPTool.FDBase.pas` — the base FireDAC class used by all relational database tools.

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

**mcp-webcrawl** additionally requires `chromedriver.exe` (matching your Chrome version) in PATH or passed via the `driverPath` parameter.  
Download: https://googlechromelabs.github.io/chrome-for-testing/

```bash
# Build all tools at once
msbuild AllMcpGroup.groupproj /t:Build /p:Config=Release /p:Platform=Win64

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
ppm install mcp-postgres
ppm install mcp-qdrant
ppm install mcp-salesforce
ppm install mcp-ssh
```

---

## License

MIT — © 2026 [Gustavo Enriquez](https://github.com/gustavoeenriquez) / [PascalAI](https://registry.pascalai.org)
