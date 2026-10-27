# Noizu.Notion — Schema Summary

No persistence layer: no database, no Ecto/Liquibase, no disk or KV state. The documented
data model is the client config schema plus the Notion interface envelopes the library
decodes (and the test fixtures that mirror them).

- **Client config:** `%Noizu.Notion.Client{token, version, base_url, req_options, retry}`;
  merge order function opts → `:noizu_notion, :client` app env → defaults
  (`"2026-03-11"`, `https://api.notion.com`, `[]`). Token redacted in `Inspect`.
- **Retry config:** `retry: [max_attempts: 3, base_backoff_ms: 500, sleep_fn: …]`;
  `max_attempts: 0` disables retries.
- **Request shape:** `authorization: Bearer` + `notion-version` headers (not overridable),
  percent-encoded path segments, list params expand to repeated query keys, `:json` XOR
  `:form_multipart`, `retry: false` on Req.
- **List envelope:** `object: "list"`, `results`, `has_more`, `next_cursor`, `type` keyed
  map, `request_status.type`. Cursor returns as `start_cursor` — query string on GET, JSON
  body on POST. Templates endpoint uses `"templates"` instead of `"results"`.
- **Error envelope:** `object: "error"`, `status`, `code`, `message`, `request_id`,
  `additional_data` → `%Noizu.Notion.Error{status, code, message, request_id,
  additional_data}`; only the 20 documented codes become atoms, unknown codes stay
  strings; transport failures are `status: nil` with `:request_failed` / `:invalid_response`.
- **Fixtures:** `Noizu.Notion.Testing` — `client/2`, `list_page/2`, `error_body/3`,
  `respond_json/3` (+ param/header extractors), test-only.

→ Full detail: [PROJ-SCHEMA.md](PROJ-SCHEMA.md) · wire contract:
[API-CONTRACT.md](API-CONTRACT.md) · layout: [PROJ-LAYOUT.md](PROJ-LAYOUT.md)
