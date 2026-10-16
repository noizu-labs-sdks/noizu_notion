# Token Handling

Threat detail for T-001, T-005, T-008, T-010 — how the bearer credential (internal
integration token, OAuth bearer, or personal access token) lives and moves.

## Lifecycle in this library

| Stage | Where | Handling |
|---|---|---|
| Entry | `Client.new(token: …)` | Caller supplies the token, normally `System.fetch_env!("NOTION_TOKEN")`. The library never reads env vars, files, or dotenv/direnv itself. Optional app-env default `:noizu_notion, :client` is a keyword list read at call time. |
| Rest | `%Client{token}` struct field | Plain field, held in process memory only. Nothing is written to disk, ETS, or a cache. No process ever copies it except `Request.perform/4` when building headers. |
| Transmit | `authorization: Bearer <token>` header | Set by `Request.perform/4` on every request; never a query param or URL fragment (T-010). Library-set headers cannot be overridden via `req_options` (T-013 in the register). |
| Absence | `ensure_token/1` | Non-empty binary required; otherwise `{:error, %Error{status: 401, code: :unauthorized}}` **before** any network I/O (T-014). The failure message contains no token material. |
| Exit | — | No logout/scrub API: the token lives as long as the struct. BEAM process GC handles the rest; nothing to persist. |

## T-001 (High) — inspect-visible token · Open

`defstruct [:token, :version, :base_url, :req_options, :retry]` in
`lib/noizu/notion/client.ex` derives no `Inspect` implementation. Any of these prints the
raw credential:

```elixir
inspect(client)                    # %Noizu.Notion.Client{token: "secret_...", ...}
Logger.debug("client: #{inspect(client)}")
:observer.peek(process)            # struct state visible in process dumps
```

Elixir convention for credential-bearing structs is a redacted `Inspect` — either

```elixir
@derive {Inspect, only: [:version, :base_url, :retry]}
defstruct [:token, :version, :base_url, :req_options, :retry]
```

or a custom `inspect/2` rendering `token: "#redacted"`. Until landed: the host's logging
discipline is the only control (never log client structs; crash reports that capture
process state can still leak).

The library itself never logs — zero `Logger` calls in `lib/` (verified by grep) — so the
only in-library leak path is exception messages, which are built from server-supplied
strings and never interpolate the token (`Error.message/1` emits status, code,
`request_id`, and Notion's own message only; the missing-token message is a fixed string).

## T-005 (Low) — response fragments in stream errors · Open

`Noizu.Notion.Pagination` raises `ArgumentError` with `inspect(other, limit: 5)` when a
fetch returns a non-envelope 2xx body or an unexpected error shape. The `limit: 5` keeps
it bounded, but five terms of a Notion response can still name workspace content. If a
host logs stream-raised exceptions, assume small content fragments reach logs.

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
