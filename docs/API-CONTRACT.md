# Noizu.Notion — API Contract

Elixir client contract for the **Notion API**, derived from the official docs at
developers.notion.com (fetched 2026-10-17; reference pages pinned to the current version).

Contract-first notes follow the api-designer method: the surface below is the promise;
implementation, tests, and future changes are reviewed against it.

---

## 1. Versioning

| Item | Value |
|---|---|
| Header | `Notion-Version` — **required on every request** |
| Pinned version | **`2026-03-11`** (current latest per developers.notion.com/reference/intro and /reference/versioning) |
| Format | Date string, `YYYY-MM-DD` |
| Release rule | New versions appear **only for backwards-incompatible changes**; additive changes (new endpoints, optional params, new response fields) reach all versions at once |
| Tolerant-reader rule | Clients **must ignore unrecognized response fields** (Notion's own guidance) — this client returns raw maps, never strict structs |
| Beta opt-in | `Notion-Beta` header (`<name>-<YYYY-MM-DD>` flags) — intentionally not sent by this client |
| `/v1` path segment | Unrelated to the date-based versioning scheme |

**Client behavior:** `Noizu.Notion.Client` carries `:version` (default `"2026-03-11"`) and
sends it on every request. Unknown/missing version is a server-side 400 (`missing_version`).

### What changed in 2026-03-11 (affects this client)

- Block-append positioning: `after` param removed → **`position` object**
  (`{"type": "end" | "start"}`, `{"type": "after_block", "after_block": {"id": ...}}`).
- `archived` removed everywhere → **`in_trash`** (request and response).
- Block type `transcription` renamed → `meeting_notes`.

### What changed in 2025-09-03 (carried into the pin)

- **Data sources split from databases**: `/v1/data_sources` = the table/schema inside a
  database (has its own ID; needed for property management and queries);
  `/v1/databases` = the container. Database IDs are unchanged; data source IDs are new.
  Legacy `POST /v1/databases/{id}/query` and the databases list endpoint are superseded.

---

## 2. Auth

| Scheme | Token form | Notes |
|---|---|---|
| Internal connection (integration) | static integration token (`Authorization: Bearer <token>`) | single workspace; access granted to the connection, actions attributed to its bot |
| Public connection (OAuth 2.0) | bearer token from the OAuth flow | acts for the authorizing user |
| Personal access token (PAT) | static bearer token | acts as its creator; cannot list workspace users |

Header: `Authorization: Bearer <token>` on every request. This client accepts a
**pre-obtained bearer token only** — the OAuth dance itself is out of scope (§7).
No token is stored globally: `Client` structs are passed explicitly; `:noizu_notion`
app-env `:client` (a keyword list) may supply defaults, and is only a convenience.

Capabilities (read/update/insert content, read comments, …) gate endpoints server-side;
violations surface as `403 restricted_resource` / `401 unauthorized`.

---

## 3. Base URL and headers

- Base URL: `https://api.notion.com` (paths below are `/v1/...`).
- Every request: `Authorization: Bearer <token>`, `Notion-Version: 2026-03-11`.
- JSON requests: `Content-Type: application/json` (Req sets it via `json:` option).
- The **only** multipart endpoint is file-upload send (`multipart/form-data`, §4.8).
- `filter_properties` query params are emitted as repeated `filter_properties=<v>` keys
  (documented form: `?filter_properties=title&filter_properties=Status`).

---

## 4. Covered resources and endpoints

Methods and paths verified against the 2026-03-11 reference pages. All calls return
`{:ok, map}` (the decoded JSON body, keys as binaries) or `{:error, %Noizu.Notion.Error{}}`.
Pagination-capable endpoints also get a `*_stream/2` (or `/3`) variant returning a lazy
`Stream` of results that transparently walks `next_cursor` (§5).

### 4.1 Pages (`Noizu.Notion.Pages`)

| Function | Endpoint | Notes |
|---|---|---|
| `create/2` | `POST /v1/pages` | body: `parent` (`page_id` \| `data_source_id` \| `database_id` \| `workspace`), `properties`, `icon`, `cover`, `content`/`children` (≤100, mutually exclusive with `markdown`), `markdown` + `markdown_version` (`v1`\|`v2`), `allow_async` (→ 202 async task), `template`, `position`, `notifications`; query: `filter_properties` |
| `retrieve/3` | `GET /v1/pages/{page_id}` | query: `filter_properties` (≤100) |
| `update/3` (+`trash/3` convenience → `in_trash`) | `PATCH /v1/pages/{page_id}` | body: `properties`, `icon`, `cover`, `in_trash`, `is_locked`, `template`, `erase_content`, `notifications`; parent cannot change; query: `filter_properties` |
| `move/3` | `POST /v1/pages/{page_id}/move` | body: `parent` as `{type: "page_id", page_id}` or `{type: "data_source_id", data_source_id}` (data source form required for data-source parents); ordinary pages only |
| `property/4` | `GET /v1/pages/{page_id}/properties/{property_id}` | property_id may be ID or URL-encoded name; **paginated** for `title`/`rich_text`/`people`/`relation`/rollup (returns list envelope), single `property_item` otherwise |
| `property_stream/3` | same | streams `results` when the property item is a list |

No permanent page deletion exists in the API — trash/restore only (`in_trash`).

### 4.2 Databases (`Noizu.Notion.Databases`)

| Function | Endpoint | Notes |
|---|---|---|
| `create/2` | `POST /v1/databases` | body: `parent` (`page_id` or `workspace`), `title` (≤100 rich text), `description`, `icon`, `cover`, `is_inline`, `initial_data_source.properties` (schema lives here, not top-level), or `database_type` (`tasks`\|`projects`\|`skills`, exclusive with `initial_data_source`); one call creates database + first data source + table view |
| `retrieve/2` | `GET /v1/databases/{database_id}` | response includes `data_sources: [%{id, name}]` |
| `update/3` | `PATCH /v1/databases/{database_id}` | body: `title`, `description`, `icon`, `cover`, `in_trash`, `parent`, `is_inline`, `is_locked`; property schema changes go through Update a data source |

### 4.3 Data sources (`Noizu.Notion.DataSources`)

| Function | Endpoint | Notes |
|---|---|---|
| `create/2` | `POST /v1/data_sources` | body: `parent.database_id` (required), `properties` (required), `title`, `icon` |
| `retrieve/2` | `GET /v1/data_sources/{data_source_id}` | returns the column schema (`properties`) |
| `update/3` | `PATCH /v1/data_sources/{data_source_id}` | body: `title`, `icon`, `in_trash`, `properties` (full config, rename `{name}`, or `null` to remove), `parent` (move between databases); `title` property cannot be removed/converted |
| `query/3` | `POST /v1/data_sources/{data_source_id}/query` | body: `filter`, `sorts`, `start_cursor`, `page_size`, `is_archived`, `result_type` (`page`\|`data_source`, wiki only); **`in_trash` is not accepted here**; query string: `filter_properties`; stops at 10 000 results → `has_more: false` + `request_status.type: "incomplete"` |
| `query_stream/3` | same | streams result rows across cursors |
| `list_templates/2,3` (+`_stream`) | `GET /v1/data_sources/{data_source_id}/templates` | query: `start_cursor`, `page_size`, `name` (substring). **Non-standard envelope**: `{templates, has_more, next_cursor}` (no `object: "list"`) — results extracted from `"templates"` |

### 4.4 Blocks (`Noizu.Notion.Blocks`)

| Function | Endpoint | Notes |
|---|---|---|
| `retrieve/2` | `GET /v1/blocks/{block_id}` | full/partial block; `has_children` gates children fetch |
| `update/3` (+`restore/2` → `in_trash: false`) | `PATCH /v1/blocks/{block_id}` | body: a type-content key (`paragraph`, `heading_1`, `to_do`, `code`, `callout`, `image`, `table_row`, …) and/or `in_trash`; fields replaced in full; children NOT updatable here; `child_page`/`child_database` need page/database endpoints |
| `delete/2` | `DELETE /v1/blocks/{block_id}` | soft delete → `in_trash: true`; restore via `update` |
| `children/3` (+`children_stream/3`) | `GET /v1/blocks/{block_id}/children` | query: `start_cursor`, `page_size`; first level only |
| `append_children/3,4` | `PATCH /v1/blocks/{block_id}/children` | body: `children` (≤100, ≤2 nesting levels), `position` (`%{"type" => "end"}` default, `%{"type" => "start"}`, `%{"type" => "after_block", "after_block" => %{"id" => id}}`), `notifications`; option `position: :end \| :start \| {:after_block, block_id}`; `after` param is GONE in 2026-03-11 |

### 4.5 Users (`Noizu.Notion.Users`)

| Function | Endpoint | Notes |
|---|---|---|
| `list/2` (+`list_stream/2`) | `GET /v1/users` | query: `start_cursor`, `page_size`; guests excluded, order not guaranteed; PATs cannot list users |
| `retrieve/2` | `GET /v1/users/{user_id}` | |
| `me/1` | `GET /v1/users/me` | bot user for the token |

### 4.6 Search (`Noizu.Notion.Search`)

| Function | Endpoint | Notes |
|---|---|---|
| `search/2` (+`search_stream/2`) | `POST /v1/search` | body: `query`, `filter` (`{property: "object", value: "page"\|"data_source", in_trash?}` or `{in_trash}`), `sort` (`{timestamp: "last_edited_time", direction}` or `{property: "relevance"}`), `start_cursor`, `page_size`; query string: `filter_properties`; results are page/data_source objects; excludes duplicated linked databases |

### 4.7 Comments (`Noizu.Notion.Comments`)

| Function | Endpoint | Notes |
|---|---|---|
| `create/2` | `POST /v1/comments` | **exactly one** of `parent.page_id`, `parent.block_id`, `discussion_id`; **exactly one** of `rich_text` (≤100 items, 2000 chars each) and `markdown` (+`markdown_version`); optional `attachments` (≤3 `{type: "file_upload", file_upload_id}`), `display_name` |
| `list/3` (+`list_stream/3`) | `GET /v1/comments` | query: `block_id` (required), `start_cursor`, `page_size`; unresolved comments only |
| `retrieve/2` | `GET /v1/comments/{comment_id}` | |
| `update/3` | `PATCH /v1/comments/{comment_id}` | own comments only (others → 404); `rich_text` \| `markdown` exactly one |
| `delete/2` | `DELETE /v1/comments/{comment_id}` | own comments only; no body |

### 4.8 File uploads (`Noizu.Notion.FileUploads`)

Lifecycle: create → send parts → (multi-part) complete → attach via a
`{type: "file_upload", file_upload_id}` file object on page/block/database payloads.

| Function | Endpoint | Notes |
|---|---|---|
| `create/2` | `POST /v1/file_uploads` | body: `mode` (`single_part` default \| `multi_part` (>20 MiB) \| `external_url`), `filename` (≤900 bytes incl. extension), `content_type`, `number_of_parts` (1–10 000, multi-part), `external_url` |
| `send/3` | `POST /v1/file_uploads/{file_upload_id}/send` | **multipart/form-data**, `file` part; `part_number` form field (string integer) for multi-part; only multipart endpoint in the API; upload while `status: "pending"` via `upload_url` |
| `complete/2` | `POST /v1/file_uploads/{file_upload_id}/complete` | multi-part finalize, no body |
| `retrieve/2` | `GET /v1/file_uploads/{file_upload_id}` | `file_upload` object: `status` = `pending`\|`uploaded`\|`expired`\|`failed`, `expiry_time`, `number_of_parts {total, sent}`, `file_import_result` |
| `list/2` (+`list_stream/2`) | `GET /v1/file_uploads` | query: `status`, `start_cursor`, `page_size`; newest first |

---

## 5. Pagination contract

List envelopes (all paginated endpoints except data-source templates):

```json
{
  "object": "list",
  "type": "block | page | user | page_or_database | comment | file_upload | property_item",
  "<type>": {},
  "results": [],
  "has_more": true,
  "next_cursor": "<opaque> | null",
  "request_status": {"type": "complete | incomplete"}
}
```

- Cursor flow: pass `next_cursor` back as **`start_cursor`** — query string on GET
  endpoints, JSON body on POST endpoints (query, search). Cursors are opaque.
- `page_size`: default 100, max 100 (docs note pages may return fewer; the intro text's
  "ten items" remark contradicts the parameter table — **set `page_size` explicitly**).
- `*_stream/2` helpers wrap `Stream.resource/3`: each element is one `results` entry;
  fetching is lazy and stops when `has_more: false` (or the envelope has no cursor).
- Data-source query hard cap: 10 000 results, then `has_more: false` +
  `request_status.type: "incomplete"`, `incomplete_reason: "query_result_limit_reached"`.
  Streams end silently at the cap; detecting truncation requires inspecting the raw
  `query/3` envelope (`request_status`) — the stream helper is documented lossy there.

---

## 6. Errors

### 6.1 Envelope

```json
{
  "object": "error",
  "status": 404,
  "code": "object_not_found",
  "message": "…",
  "request_id": "…",
  "additional_data": {}
}
```

Client shape: `%Noizu.Notion.Error{status, code, message, request_id, additional_data}`.
`code` is an atom for all documented codes below (existing atoms only — unknown codes are
kept as strings, never `String.to_atom/1`). Transport/decoding failures map to
`%Error{status: nil, code: :request_failed | :invalid_response}`. Every call returns
`{:error, %Error{}}` — the library does not raise on HTTP errors.

### 6.2 Status → code map (2026-03-11 reference)

| Status | Codes | Retryable? |
|---|---|---|
| 400 | `invalid_json`, `invalid_request_url`, `invalid_request`, `invalid_grant`, `validation_error`, `missing_version`, `invalid_beta` | no |
| 401 | `unauthorized` | no |
| 403 | `restricted_resource` | no |
| 404 | `object_not_found` | no |
| 406 | `row_limit_exceeded` | no |
| 409 | `conflict_error` | yes — refresh params, retry |
| 429 | `rate_limited` | yes — honor `Retry-After` |
| 500 | `internal_server_error` | not recommended (contact support) |
| 502 | `bad_gateway` | yes (idempotent requests) |
| 503 | `service_unavailable`, `database_connection_unavailable` | careful with writes — check `additional_data.retry_guidance`; a write may already have applied |
| 504 | `gateway_timeout` | yes (idempotent requests) |
| 529 | `service_overload` | yes — handle like 429 |

### 6.3 Retry policy (client)

- **429/529**: bounded retry (default max 3 attempts) sleeping `Retry-After` seconds
  (header, falling back to body `additional_data.retry_after`; header may also be absent).
  Disable per client with `retry: [max_attempts: n]` (`max_attempts: 0` = never retry).
- **5xx (502/503/504)**: retried only for idempotent methods (`GET`, `HEAD`, `DELETE`),
  fixed short backoff, same attempt budget. Writes that 5xx return the error untouched
  (per Notion: the change may have applied).
- **409 `conflict_error`**: returned to the caller (retry semantics need refreshed
  parameters; automatic blind retries would repeat the conflict).
- Req's built-in retry is disabled (`retry: false`) so this policy is the single owner.

### 6.4 Rate limits (server behavior)

- Per connection: **600 req/min** (Business/Enterprise) or **180 req/min** (~3 rps, other
  plans); a **shared per-workspace budget** can throttle a connection under its own cap.
- 429 body carries `additional_data.rate_limit_reason` (connection | workspace budget |
  endpoint-specific | MCP tool | upstream query throttling). Exception: code
  `public_api_request_blocked` — access restricted, retrying is useless.
- `Retry-After`: integer seconds (≤60 for the connection window; possibly longer for the
  workspace budget); mirrored in `additional_data.retry_after`.
- Payload limits (400 `validation_error`): 1000 blocks / 500 KB per request; rich text
  2000 chars; equations 1000 chars; block arrays, multi-select options, relations, people
  ≤ 100 items per request.

---

## 7. Intentionally NOT covered (v0.1)

- **OAuth flow** — no authorization-URL building, code exchange, or token refresh; bring a
  bearer token (integration, OAuth result, or PAT).
- **Views API** (`/v1/views` create/retrieve/update/delete/list + view-query) — new in the
  2026 docs; deferred until it stabilizes.
- **Markdown page endpoints** `GET/PATCH /v1/pages/{id}/markdown` — note this does *not*
  exclude the `markdown` body param on create/update page/comment, which **is** covered.
- **Webhooks** (receiving deliveries, configuring endpoints).
- **Notion-Beta** opt-in header and beta-flagged surfaces.
- **Admin API** (`openapi-adminApi.json` surfaces; user management/scim).
- **Legacy database endpoints** — `POST /v1/databases/{id}/query`, `GET /v1/databases`
  list, and the pre-2025-09-03 create/update-property-schema variants; superseded by
  data sources (§1). Data-source `retrieve/query/create/update` is the covered path.
- **Async task polling** (`202` + `status_url` responses from markdown page creation) —
  the 202 body is returned as a normal `{:ok, map}`; no poll helper yet.
- **Object hydration** — responses stay raw maps by design (tolerant reader, §1);
  no typed structs per Notion object.

---

## 8. Client contract (`Noizu.Notion.Client`)

```elixir
%Noizu.Notion.Client{
  token: binary | nil,          # bearer token; required at request time
  version: "2026-03-11",        # Notion-Version header
  base_url: "https://api.notion.com",
  req_options: [],              # merged into every Req.new/1 (plug:, headers:, …)
  retry: [max_attempts: 3],     # 429/529 + idempotent-5xx budget (0 disables)
}
```

- `Client.new(opts)` precedence: opts → app env `:noizu_notion, :client` (keyword list)
  → defaults. App env is an optional convenience; nothing global is required.
- Missing token at request time → `{:error, %Error{code: :unauthorized, status: 401}}`
  without hitting the network.
- Request results: `{:ok, map}` | `{:error, %Noizu.Notion.Error{}}` — no raising, no
  bang variants in v0.1.
