# Changelog

All notable changes to this project are documented in this file.

## 0.1.0 — 2026-10-17

Initial release. Contract-first client for the Notion API, pinned to `Notion-Version: 2026-03-11`
(contract: [`docs/API-CONTRACT.md`](docs/API-CONTRACT.md)).

### Added

- `Noizu.Notion.Client` — explicit, dependency-injected client struct (token, version,
  base URL, Req options, retry policy); app env `:noizu_notion, :client` as optional default.
- `Noizu.Notion.Error` — documented error envelope as a struct (`status`, `code`, `message`,
  `request_id`, `additional_data`); known codes as atoms, unknown codes kept as strings.
- Pages: create, retrieve (filter_properties), update, trash/restore, move, per-property
  reads (paginated for list-valued properties) + `property_stream/4`.
- Databases: create, retrieve, update (container endpoints).
- Data sources: create, retrieve, update (property schema), `query/4` + `query_stream/4`,
  `list_templates/3` + `list_templates_stream/3` (non-standard envelope handled).
- Blocks: retrieve, update, delete/restore, `children/3` + `children_stream/3`,
  `append_children/4` with the 2026-03-11 `position` object (`:end`, `:start`,
  `{:after_block, id}`).
- Users: list + `list_stream/2`, retrieve, me.
- Search: `search/3` + `search_stream/3`.
- Comments: create, list + `list_stream/3`, retrieve, update, delete.
- File uploads: create, `send_file/3` (multipart), complete, retrieve, list +
  `list_stream/2`.
- Bounded 429/529 retry honoring `Retry-After` (header, falling back to
  `additional_data.retry_after`); idempotent-5xx retry for GET/HEAD/DELETE only;
  Req's built-in retry disabled.
- `filter_properties` options always encode as repeated `filter_properties=<v>` query
  keys (`filter_properties=a&filter_properties=b`), never `filter_properties[]=` —
  asserted byte-exact in the test suite for page, data-source query, and search.
- Req constrained to `~> 0.7`: file-upload send uses Req's `form_multipart`, which does
  not exist in 0.5/0.6.
- Test suite fully stubbed via `Req.Test` (no network, no real tokens).
