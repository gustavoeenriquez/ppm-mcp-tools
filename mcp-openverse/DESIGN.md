# mcp-openverse — diseño

> Estado: **código escrito, sin compilar** (2026-11-17). Se compila cuando la máquina esté libre (ver §10).
> Objetivo: que un agente (Claude Code, MakerAI, MKAIServer) encuentre imágenes y audio con licencia abierta,
> sepa si puede usarlos, los descargue con su manifiesto y genere los créditos, sin inventar licencias.

## 1. Contexto

- **Openverse** (openverse.org, de WordPress) indexa 5,2 M de audios (Wikimedia, Jamendo, Freesound) y 915 M de
  imágenes de 52 fuentes. Solo guarda metadatos; el archivo vive en la fuente.
- API pública `https://api.openverse.org/v1` (Django REST, OpenAPI en `/v1/schema/`).
- Este MCP sigue las convenciones de `ppm-mcp-tools`: Delphi 13 (Studio 37.0, como `build_conta.bat`), `TAiMCPToolBase<TParams>` de MakerAI,
  stdio / http / sse con `--protocol` y `--port`, Win64 + Linux64, credenciales con `_shared/MCPTool.Credential.pas`.
- Pareja natural: **earshot** (escucha y elige el audio descargado). El manifiesto que escribe `openverse_download`
  usa el mismo formato que `skills/real-sound/templates/manifest_entry.json` de earshot.

## 2. Datos de la API (verificados el 2026-11-17)

| Endpoint | Uso en el MCP |
|---|---|
| `GET /v1/audio/`, `GET /v1/images/` | búsqueda |
| `GET /v1/{audio,images}/{id}/` | detalle de un ítem |
| `GET /v1/{audio,images}/{id}/related/` | parecidos |
| `GET /v1/{audio,images}/stats/` | fuentes y conteos |
| `GET /v1/audio/{id}/waveform/` | no se expone (muchos tokens, poco valor; earshot mide mejor) |
| `GET /v1/{audio,images}/{id}/thumb/` | miniatura de imágenes |
| `POST /v1/auth_tokens/token/` | token OAuth2 `client_credentials` |
| `GET /v1/rate_limit/` | cuota restante (en `openverse_status`) |

Filtros útiles de la búsqueda: `q`, `license` (cc0, pdm, by, by-sa, by-nd, by-nc, ...), `license_type`
(`commercial`, `modification`, `all-cc`), `source`, `excluded_source`, `creator`, `tags`, `extension`,
`category` (audio: `sound_effect`, `music`, `podcast`, `audiobook`, `news`, `pronunciation`; imágenes:
`photograph`, `illustration`, `digitized_artwork`), `length` (audio: `shortest`, `short`, `medium`, `long`),
`aspect_ratio` y `size` (imágenes), `mature`, `filter_dead`, `page`, `page_size`.

**Límites:**
- Anónimo: 20 por minuto y **200 por día** (cabeceras `x-ratelimit-*`). Páginas pequeñas y una profundidad total
  limitada por consulta.
- Registrado: un poco más; páginas más grandes, misma profundidad total.
- Los términos de servicio **prohíben el scraping**. El MCP no recorre páginas en bucle ni descarga en masa.

## 3. Herramientas

Se proponen **seis herramientas separadas** en vez de una sola con `operation` (como `mcp-wikipedia`), porque
cada operación tiene parámetros distintos y así el modelo ve un esquema claro para cada una.

### 3.1 `openverse_search`
Busca audio o imágenes.

| Parámetro | Tipo | Por defecto | Notas |
|---|---|---|---|
| `media` | `audio` \| `image` | — | obligatorio |
| `query` | string | — | obligatorio; la API busca mejor en inglés (avisarlo en la descripción) |
| `use` | `commercial` \| `modify` \| `commercial_modify` \| `any` | `commercial` | se traduce a `license_type`; **el valor por defecto es el seguro** |
| `licenses` | string | — | lista exacta (`cc0,by`), anula `use` |
| `category`, `length`, `source`, `creator`, `extension`, `aspectRatio`, `size` | string | — | pasan a la API tal cual |
| `limit` | int | 10 | se recorta al máximo que permita la cuenta |
| `page` | int | 1 | — |

Valores fijos: `filter_dead=true`, `mature=false`.

**Respuesta compacta** (sin `waveform`, `tags` recortados a 8, sin `fields_matched`), para no gastar tokens:

```json
{"total": 240, "page": 1, "pages": 12, "results": [
  {"id": "…", "title": "Swipe Whoosh", "creator": "…", "source": "freesound",
   "license": "CC0 1.0", "license_code": "cc0", "license_url": "…",
   "commercial_ok": true, "modify_ok": true, "attribution_required": false,
   "duration_s": 0.45, "filetype": "mp3", "sample_rate": 44100,
   "page_url": "<foreign_landing_url>", "file_url": "<url>", "tags": ["whoosh", "swipe"]}],
 "quota": {"minute_left": 19, "day_left": 199},
 "note": "Licencias según el índice de Openverse; confirmar en page_url antes de publicar."}
```

`commercial_ok`, `modify_ok` y `attribution_required` se calculan en el MCP a partir de `license_code` con una
tabla fija (CC0 y PDM: sin condiciones; BY: atribución; SA: misma licencia; NC: sin uso comercial; ND: sin
modificar). **No se aceptan licencias desconocidas:** un código que no está en la tabla da los tres campos
`false` y una nota. Se enumera lo que se acepta, no lo que se rechaza.

Para imágenes se cambia `duration_s` por `width`/`height`, y `thumb_url` sustituye a los campos de audio.

### 3.2 `openverse_get`
Detalle completo de un ítem: `media` + `id`. Devuelve lo mismo que la búsqueda más `attribution` (el texto de
Openverse), `filesize`, `bit_rate`, `genres` y `alt_files` (otros formatos, p. ej. el WAV original).

### 3.3 `openverse_related`
`media` + `id` + `limit`: parecidos al elegido. Sirve para encontrar variantes de un efecto que ya funciona.

### 3.4 `openverse_download` (solo en modo stdio)
Descarga ítems ya buscados y escribe su manifiesto.

| Parámetro | Notas |
|---|---|
| `media`, `ids` (lista, máx. 10) | el MCP vuelve a pedir el detalle de cada `id` a la API |
| `dir` | carpeta destino; se crea si no existe |
| `category`, `need` | se copian al manifiesto (formato de earshot) |
| `preferOriginal` | si `alt_files` trae WAV/FLAC, se baja ese |

Reglas de seguridad:
- **La URL nunca la da el modelo:** sale del detalle que devuelve la API para ese `id`. Así no hay SSRF ni
  descargas arbitrarias.
- Solo `https`. Tamaño máximo de 100 MB por archivo y de 300 MB por llamada.
- Solo extensiones de audio e imagen conocidas (`mp3 ogg wav flac m4a aac opus jpg jpeg png webp gif tif tiff`).
  El nombre de archivo lo genera el MCP: `ov-<id8>_<titulo-saneado>.<ext>`.
- Antes de escribir, comprueba que la ruta final quede dentro de `dir` (nada de `..`).
- Si una licencia no es apta para el `use` pedido, **no la descarga** y lo dice, salvo que se pase
  `allowRestricted=true`.
- En **modo servidor** (http/sse en MKAIServer) esta herramienta no se registra, como manda
  `MCPTool.Credential`: un proceso compartido no escribe en disco por orden del modelo.

Escribe y actualiza `<dir>/openverse_manifest.json` (una lista con el formato de `manifest_entry.json` de
earshot):
`id`, `category`, `file`, `title`, `author`, `source`, `page_url`, `download_url`, `license`, `license_url`,
`attribution` y `need`, más `openverse_id`, `license_code`, `licence_checked_on_page` (false hasta que alguien
lea la licencia en la página) y `retrieved_at`. `file` es el nombre del archivo, relativo a la carpeta del manifiesto. Los campos `analysis` y `earshot` quedan para que los
rellene earshot.

### 3.5 `openverse_credits`
Genera los créditos de una lista de ítems, a partir de `ids` o de la ruta de un manifiesto.
- `format`: `youtube` (texto plano para la descripción), `markdown`, `html` o `json`.
- Omite CC0 y PDM salvo que se pida `includeCc0=true` (cortesía). `lang`: `en` (por defecto) o `es`.
- Cada línea lleva título, autor, página de origen y licencia con su URL (TASL).
- Al final, advierte de cualquier ítem NC o ND, y de que la licencia se debe confirmar en la página de origen.

### 3.6 `openverse_status`
Devuelve las fuentes disponibles y sus conteos (`stats`, cacheado 24 h), la cuota restante (`/v1/rate_limit/`) y si
el MCP está autenticado o va como anónimo. Ayuda a que el agente decida si gastar consultas.

## 4. Autenticación y credenciales

1. **Registro (una vez, lo hace Gustavo):** `POST /v1/auth_tokens/register/` con nombre, descripción y correo
   (llega un correo de verificación). Devuelve `client_id` y `client_secret`. No se automatiza: el correo es
   personal.
2. **Modo stdio:** variables `OPENVERSE_CLIENT_ID` y `OPENVERSE_CLIENT_SECRET`. Si faltan, funciona como
   anónimo (200 consultas al día) y `openverse_status` lo dice.
3. **Modo servidor:** `Cred(AuthContext, 'OPENVERSE_CLIENT_ID')` y equivalentes, desde la cabecera, como el
   resto de MCP alojados. En MKAIServer: `client_mcp_configs` o `MKAI_MCP_KEY_OPENVERSE`.
4. **Token:** `POST /v1/auth_tokens/token/` (`grant_type=client_credentials`). Se cachea en memoria por
   `client_id` y se renueva 5 minutos antes de `expires_in`. Si una llamada devuelve 401, se renueva una vez y
   se reintenta.
5. Nunca se escriben ni el secreto ni el token en logs, respuestas o archivos.

## 5. Uso cuidadoso de la cuota

- **Caché en memoria** (LRU de 200 entradas): búsquedas 1 h y detalles 24 h, con clave = URL normalizada + modo
  (anónimo o el `client_id`). Las descargas consultan el detalle desde esta caché.
- **429:** no reintenta en bucle. Devuelve un error claro con `Retry-After` y la cuota, para que el agente espere
  o avise.
- Nunca recorre páginas por su cuenta: cada página la pide el agente (términos de servicio).
- `User-Agent: mcp-openverse/<versión> (+https://registry.pascalai.org)`, genérico, sin datos personales.

## 6. Estructura

```
mcp-openverse/
  mcp-openverse.dpr        stdio | http | sse, puerto por defecto 8862
  mcp-openverse.dproj      Win64 + Linux64 (Delphi 12)
  MCPTool.Openverse.pas    las 6 herramientas y su registro
  MCPTool.OpenverseApi.pas cliente HTTP: token, caché, cuota, errores
  MCPTool.Licenses.pas     tabla de licencias → commercial_ok / modify_ok / attribution_required
  DESIGN.md                este documento
```

En `ppm/pkgs/mcp-openverse/`: `pai.package` (type = mcp, runtime binary, windows + linux) y `mcp-openverse.tool`
(las variables `OPENVERSE_CLIENT_ID` y `OPENVERSE_CLIENT_SECRET`, opcionales).

## 7. Pruebas

1. Unitarias de `MCPTool.Licenses`: cada código conocido, uno desconocido y las versiones (`by 2.0`, `by 4.0`).
2. `mcp_smoke.py` con el `.exe`: `tools/list`, una búsqueda de audio, una de imágenes, `get`, `related`,
   `credits` y `status`. Pocas llamadas, para no gastar la cuota.
3. Descarga a una carpeta temporal:
   - el manifiesto se valida contra la plantilla de earshot;
   - un ítem BY-NC con `use=commercial` debe rechazarse;
   - un `dir` con `..` debe rechazarse.
4. Modo http: `openverse_download` no debe aparecer en `tools/list`.
5. Linux64 con `dbuild.sh` en mkai-c25, sin compilar en paralelo.

## 8. Flujo previsto con earshot (skills de videos)

```
openverse_search(media=audio, query="soft ui click", category=sound_effect, length=shortest)
  → openverse_download(ids=[top 8], dir=audio/assets/ui, need=ui_click)
  → earshot rank "a soft ui click" audio/assets/ui/ ; earshot find / realness sobre el ganador
  → montaje ffmpeg → earshot measure / timeline (control de calidad)
  → openverse_credits(manifest=audio/assets/ui/openverse_manifest.json, format=youtube) → descripción de YouTube
```

## 9. Fuera de alcance en la v1

- Subir o reportar contenido (`/report/`).
- Waveform y oEmbed.
- Descargar desde la fuente original cuando hace falta iniciar sesión (los WAV originales de Freesound). Se usa lo
  que da Openverse.
- Comprobar la licencia leyendo la página de origen. Podría venir en la v2 para Freesound y Wikimedia, que tienen
  API propia.

## 10. Estado y pasos siguientes

Decidido con Gustavo el 2026-11-17: seis herramientas separadas, solo stdio en la v1 (en http/sse no se registra
`openverse_download` y `openverse_credits` no lee manifiestos), anónimo hasta que él haga el registro OAuth.

Notas de implementación:
- Los nombres de parámetro salen en camelCase (el núcleo MCP de MakerAI pone en minúscula la primera letra de la
  propiedad).
- Los valores permitidos van en las descripciones, no con `AiMCPSchemaEnum`: ningún MCP lo usa todavía y no está
  probado que el compilador acepte arreglos en atributos.
- `use` se traduce a una lista explícita de licencias (`license=cc0,pdm,by,...`) a partir de la tabla propia, y cada
  resultado se vuelve a comprobar contra esa tabla (`dropped_by_licence_check`).

Pendiente:
1. Compilar Win64 (`msbuild mcp-openverse.dproj /p:Config=Release /p:Platform=Win64`) y Linux64.
2. Pruebas de §7 con `mcp_smoke.py`.
3. Registro OAuth (lo hace Gustavo) y prueba autenticada.
4. Publicar en PPM firmado (`firmar_paquete.py`) y añadirlo al README de ppm-mcp-tools.
