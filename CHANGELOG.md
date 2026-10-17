# Changelog

All notable changes to this project are documented in this file.

## Unreleased

### Fixed

- **T-001 (High):** `%Noizu.Notion.Client{}` implements `Inspect` so the bearer token
  renders as `token: "[REDACTED]"` — logging, crash reports, and REPL dumps of a client
  can no longer leak the credential. Error structs/messages verified token-free; Req's
  own auth-header inspect redaction covered by a tripwire test.
  (`test/noizu/notion/client_test.exs`)
- **T-002 (Medium):** server-supplied `Retry-After` — both the response header and
  `additional_data.retry_after` — is clamped to 30 s; negative or non-numeric values
  fall back to the client's `base_backoff_ms` backoff instead of sleeping negative or
  hanging the caller. (`Noizu.Notion.ErrorTest`, `Noizu.Notion.RequestTest`)
- **T-005 (Low):** pagination failure messages no longer embed response fragments
  (`inspect(other, limit: 5)`); they describe the shape of the unexpected value
  (kind + size) so workspace content cannot reach host logs via raised exceptions.
  (`Noizu.Notion.PaginationTest`)

### Added

- `retry: [sleep_fn:]` client option (default `&Process.sleep/1`) — lets tests observe
  retry delays without sleeping.
- **CI** (`.github/workflows/ci.yml`): on push and PR for develop/stage/main —
  `mix deps.get`, `mix format --check-formatted`, `mix compile --warnings-as-errors`,
  `mix test`, `mix hex.audit`; matrix over Elixir 1.15.8/OTP 26 (floor), 1.18.4/OTP 27
  (middle) and 1.20.4/OTP 29 (current); deps/_build cached. (T-003/T-004)

### Changed

- **Repository moved to the `noizu-labs-sdks` GitHub org** — `@source_url` in
  `mix.exs` (Hex metadata links: GitHub) now points at
  `github.com/noizu-labs-sdks/noizu_notion`; no other old-org references remained
  in the tree.
- **Elixir floor lowered from `~> 1.20` to `~> 1.15`** — every locked dependency
  (req 0.7.5, plug 1.20.3, finch 0.24.0, hpax 1.1.0, ex_doc 0.40.4) already
  declares `~> 1.15`, and the codebase uses no post-1.15 syntax or stdlib APIs,
  so most Elixir users can consume the package; CI matrix now runs the 1.15.8/OTP 26
  floor plus 1.18.4/OTP 27 and 1.20.4/OTP 29.

### Docs

- Threat model updated: T-001/T-002/T-005 and the CI findings (T-003/T-004) read
  **Mitigated** with the covering tests as evidence
  (`docs/THREAT-MODEL.md`, `docs/THREAT-MODEL.summary.md`, `docs/threats/*.md`).

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

### Docs

- House documentation: project layout (`docs/PROJ-LAYOUT.md` + summary,
  `docs/layout/lib.md`), architecture (`docs/PROJ-ARCH.md` + summary,
  `docs/arch/request-lifecycle.md`), threat model (`docs/THREAT-MODEL.md` + summary,
  `docs/threats/` — token handling, request/retry, file uploads, Hex supply chain), and
  doc-pointer markers across the doc set (`.meta/pointers.yaml`).
