# `lib/` — Module Detail

Source lives under `lib/noizu/` — the facade at `lib/noizu/notion.ex` and twelve modules
in `lib/noizu/notion/`. One flat module namespace, no supervision tree, no processes
started by the library.

```
lib/noizu/
├── notion.ex                     # Facade: Noizu.Notion.new/1 → Client.new/1
└── notion/
    ├── client.ex                 # Explicit client struct (token, version, base_url, req_options, retry)
    ├── request.ex                # Internal request engine: headers, Req call, bounded retry, decode
    ├── error.ex                  # %Noizu.Notion.Error{} defexception + retry policy predicates
    ├── pagination.ex             # Stream.resource cursor walker + start_cursor helpers
    ├── pages.ex                  # Pages: create/retrieve/update/trash/move, property reads
    ├── databases.ex              # Database containers: create/retrieve/update
    ├── data_sources.ex           # Data sources: schema CRUD, query(+stream), templates(+stream)
    ├── blocks.ex                 # Blocks: retrieve/update/delete/restore, children, append
    ├── users.ex                  # Users: list(+stream)/retrieve/me
    ├── search.ex                 # Workspace search: search(+stream)
    ├── comments.ex               # Comments: create/list(+stream)/retrieve/update/delete
    └── file_uploads.ex           # Uploads: create/send(multipart)/complete/retrieve/list(+stream)
```

## Layer 1 — Facade

| Module | Contents |
|---|---|
| `Noizu.Notion` | Moduledoc quickstart + resource index; `new/1` delegated to `Client`. |

## Layer 2 — Shared machinery

| Module | Contents |
|---|---|
| `Noizu.Notion.Client` | `%Client{token, version, base_url, req_options, retry}` struct; `new/1` merges function opts → app env `:noizu_notion, :client` → defaults; `api_version/0` returns the pinned `"2026-03-11"`. |
| `Noizu.Notion.Request` | `perform/4` — builds the Req call (`authorization: Bearer`, `notion-version`, `retry: false`), decodes bodies, runs the bounded retry loop (429/529 always; 502/503/504 idempotent-only), normalizes failures via `Error`; `encode_segment/1` percent-encodes path segments; list-valued params expand to repeated query keys. |
| `Noizu.Notion.Error` | `defexception` mirroring the Notion error envelope; `known_codes/0` (atoms for documented codes, unknown codes stay strings); `retryable?/2`, `retry_after_ms/2`. |
| `Noizu.Notion.Pagination` | `stream/2` — lazy `Stream.resource/3` walker over `next_cursor`/`has_more`; `with_cursor/2` (query string) and `with_cursor_in_body/2` (POST JSON). Raises `%Error{}` mid-stream on fetch failure. |

## Layer 3 — Resource modules

Uniform shape: every function takes `%Client{}` first, returns `{:ok, map}` or
`{:error, %Noizu.Notion.Error{}}`; paginated endpoints additionally expose a
`*_stream` variant.

| Module | Endpoints (full detail in `docs/API-CONTRACT.md` §4) |
|---|---|
| `Noizu.Notion.Pages` | `POST /v1/pages`, `GET/PATCH /v1/pages/{id}`, `POST /v1/pages/{id}/move`, `GET /v1/pages/{id}/properties/{property_id}` (+ stream) |
| `Noizu.Notion.Databases` | `POST /v1/databases`, `GET/PATCH /v1/databases/{id}` |
| `Noizu.Notion.DataSources` | `POST /v1/data_sources`, `GET/PATCH /v1/data_sources/{id}`, `POST .../query` (+ stream), `GET .../templates` (+ stream, non-standard envelope) |
| `Noizu.Notion.Blocks` | `GET/PATCH/DELETE /v1/blocks/{id}`, `GET/PATCH /v1/blocks/{id}/children` (+ stream on GET); append takes `position: :end \| :start \| {:after_block, id}` |
| `Noizu.Notion.Users` | `GET /v1/users` (+ stream), `GET /v1/users/{id}`, `GET /v1/users/me` |
| `Noizu.Notion.Search` | `POST /v1/search` (+ stream) |
| `Noizu.Notion.Comments` | `POST /v1/comments`, `GET /v1/comments` (+ stream), `GET/PATCH/DELETE /v1/comments/{id}` |
| `Noizu.Notion.FileUploads` | `POST /v1/file_uploads`, `POST .../send` (multipart, `form_multipart`), `POST .../complete`, `GET /v1/file_uploads/{id}`, `GET /v1/file_uploads` (+ stream) |
