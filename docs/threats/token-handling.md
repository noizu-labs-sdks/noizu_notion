# Token Handling

Threat detail for T-001, T-005, T-008, T-010 — how the bearer credential (internal
integration token, OAuth bearer, or personal access token) lives and moves.

## Lifecycle in this library

| Stage | Where | Handling |
|---|---|---|
| Entry | `Client.new(token: …)` | Caller supplies the token, normally `System.fetch_env!("NOTION_TOKEN")`. The library never reads env vars, files, or dotenv/direnv itself. Optional app-env default `:noizu_notion, :client` is a keyword list read at call time. |
| Rest | `%Client{token}` struct field | Held in process memory only. `inspect/2` renders the field as `token: "[REDACTED]"` via a custom `Inspect` implementation (T-001, mitigated). Nothing is written to disk, ETS, or a cache. No process ever copies it except `Request.perform/4` when building headers. |
| Transmit | `authorization: Bearer <token>` header | Set by `Request.perform/4` on every request; never a query param or URL fragment (T-010). Library-set headers cannot be overridden via `req_options` (T-013 in the register). |
| Absence | `ensure_token/1` | Non-empty binary required; otherwise `{:error, %Error{status: 401, code: :unauthorized}}` **before** any network I/O (T-014). The failure message contains no token material. |
| Exit | — | No logout/scrub API: the token lives as long as the struct. BEAM process GC handles the rest; nothing to persist. |

## T-001 (High) — inspect-visible token · Mitigated

`defstruct [:token, :version, :base_url, :req_options, :retry]` in
`lib/noizu/notion/client.ex` now carries a custom `Inspect` implementation that renders
the token as a fixed placeholder and every other field readable:

```elixir
inspect(client)
#=> "#Noizu.Notion.Client<token: \"[REDACTED]\", version: \"2026-03-11\", ...>"
```

So `Logger.debug("client: #{inspect(client)}")`, crash reports capturing process state,
and REPL output can no longer leak the raw credential from this library's structs.

Guardrails asserted by the suite (`test/noizu/notion/client_test.exs`):

- `Noizu.Notion.ClientTest "inspect/2 never prints the bearer token"` — the redaction,
  plus `nil` tokens rendering as `token: nil`.
- `"error structs and exception messages never carry the token"` — `Error.message/1`
  emits status, code, `request_id`, and Notion's own message only; the missing-token
  message is a fixed string.
- `"Req redacts the authorization header in request inspect output"` — tripwire on the
  dependency: Req's own `Inspect` for `%Req.Request{}` masks `authorization` headers and
  `:auth` options, so request dumps stay safe as long as Req keeps that behaviour.

The library itself never logs — zero `Logger` calls in `lib/` (verified by grep).

## T-005 (Low) — response fragments in stream errors · Mitigated

`Noizu.Notion.Pagination` used to raise `ArgumentError` with `inspect(other, limit: 5)`
embedded in the message — five terms of a Notion response can name workspace content, and
raised messages land in host logs. Failure messages now describe the **shape** of the
unexpected value only (kind + size, e.g. `a map with 2 keys`, `a string of 51 bytes`);
no response content is ever interpolated.

Evidence: `Noizu.Notion.PaginationTest "failure messages describe shape, not content"`
(both the non-envelope and unexpected-failure branches, asserting the content does not
appear and the description does).

## T-008 (Medium) — credential redirection via config · Accepted

The token is sent wherever `base_url` points. `base_url` and `req_options` are
caller-controlled (function opts → app env → defaults), so anything that can write
`:noizu_notion, :client` config — or pass a client struct into library code — can
exfiltrate the bearer by pointing `base_url` at a hostile host (or flip TLS off with an
`http://` URL). This is inherent to a thin client that trusts its host; the mitigation is
consumer-side: treat `:noizu_notion, :client` configuration as secret-sensitive, never
accept client structs from untrusted input, and keep the default `https://api.notion.com`.

## Token types and capabilities (grounded: API-CONTRACT.md §2)

| Token | Acts as | Notes |
|---|---|---|
| Internal integration token | the connection's bot | single workspace, capability-gated server-side |
| OAuth bearer | authorizing user | OAuth dance out of scope; pre-obtained token only |
| Personal access token | its creator | cannot list workspace users (`Users.list/2` → server 403) |

All three are opaque bearers handled identically — the library does not distinguish or
refresh them. OAuth token expiry/refresh is the host's responsibility (deliberate, §7 of
the contract).
