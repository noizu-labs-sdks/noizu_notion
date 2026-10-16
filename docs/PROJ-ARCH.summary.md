# Noizu.Notion — Architecture Summary

- **Shape:** stateless Elixir client library for the Notion API (`Notion-Version:
  2026-03-11`). No processes, no global state; explicit `%Noizu.Notion.Client{}` struct
  passed to every call; `{:ok, map}` / `{:error, %Noizu.Notion.Error{}}` everywhere.
- **Contract-first:** `docs/API-CONTRACT.md` is the source of truth; raw-map responses
  (tolerant reader); unknown error codes never become atoms.
- **Layers:** facade (`Noizu.Notion`) → shared machinery (`Client`, `Request`, `Error`,
  `Pagination`) → 8 resource modules (Pages, Databases, DataSources, Blocks, Users,
  Search, Comments, FileUploads).
- **Request path:** token check (fail fast, no network) → library-set `Bearer` +
  `Notion-Version` headers (not overridable by `req_options`) → Req with built-in retry
  disabled → decode (tolerant) → bounded retry loop → normalized error.
- **Retry:** 429/529 always (Retry-After header → body → linear backoff, default 3
  attempts); 502/503/504 idempotent-methods-only; 409/500/transport never. Writes that
  5xx return the error untouched.
- **Pagination:** lazy `Stream.resource/3` cursor walker; `start_cursor` in query string
  (GET) or JSON body (POST); failed page fetch raises mid-stream; data-source query cap
  (10 000) ends streams silently.
- **Key decisions:** DI client over globals (testability via `Req.Test`, multi-token);
  library-owned retry; `Req ~> 0.7` floor (multipart `form_multipart`); out of scope:
  OAuth flow, webhooks, views/admin API, object hydration.
- **Stack:** Elixir ~> 1.20, Req, Jason; test-only Plug; ex_doc dev-only; Hex package,
  MIT.

→ Full detail: [PROJ-ARCH.md](PROJ-ARCH.md) ·
[arch/request-lifecycle.md](arch/request-lifecycle.md) · [API-CONTRACT.md](API-CONTRACT.md)
