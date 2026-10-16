# Request Engine, Retry, and Untrusted Input

Threat detail for T-002, T-011–T-015 — the `Noizu.Notion.Request` engine
(`lib/noizu/notion/request.ex`), its retry policy, and how server-controlled data is
parsed. Flow and state machine: [../arch/request-lifecycle.md](../arch/request-lifecycle.md).

## T-002 (Medium) — unbounded Retry-After sleep · Open

The retry delay comes from, in order (`Error.retry_after_ms/2`):

1. `retry-after` response header — `Integer.parse/1`, any result `>= 0` accepted;
2. body `additional_data.retry_after` — any number accepted;
3. fallback `base_backoff_ms * attempt` (caller-controlled).

The chosen value is passed straight to `Process.sleep/1`. Nothing clamps it: a peer
returning `Retry-After: 2000000000` parks the calling process for ~63 years — a clean
denial of service against whatever process made the call (a request process in a Phoenix
app, a LiveView, a GenServer). The API contract documents ≤60 s for the connection window
(longer for the workspace budget), but the code does not enforce any ceiling, and nothing
verifies the header's provenance beyond TLS.

Recommended fix: clamp in `retry_delay_ms/4` (e.g. `min(ms, 120_000)`) and expose the
clamp as a `retry: [:max_retry_after_ms]` client option.

Secondary retry-posture notes (accepted as designed):

- **Idempotency is method-derived only** (`GET`/`HEAD`/`DELETE`); 5xx'd writes are never
  retried because the change may have applied — this errs safe against duplicate writes.
- **429/529 retry POSTs** (including multipart `send` — see T-007 in the main register).
- **Transport exceptions are not retried** — the `{:error, exception}` branch returns
  immediately, so connectivity flaps surface to the caller instead of looping.
- **Sleeping happens in the caller's process** — a `max_attempts` config is also a
  latency bound the host must size (3 attempts × linear 500 ms default ≈ ≤3 s added).

## Untrusted server input — what the parser guarantees (T-011)

Every server-supplied string that could become an atom or code goes through a guard:

| Input | Path | Guarantee |
|---|---|---|
| Error `code` string | `Error.normalize_code/1`: `String.to_existing_atom/1` **then** membership in `@known_codes` | never creates an atom; unlisted codes stay strings |
| Response body | `Jason.decode/1` (binary fallback in `decode_body/1`) | maps with binary keys; no atom option |
| Non-JSON body | kept as binary; surfaced as `:invalid_response` + byte size only (`inspect_shape/1` deliberately reports size, not content) | body content not echoed into the error struct |
| Path IDs (caller-supplied) | `Request.encode_segment/1` — `URI.encode` with unreserved-chars-only predicate (T-012) | no path traversal / header smuggling via `..`, `/`, CR/LF |
| Query params | `expand_params/1` then Req's own encoder | repeated-key form, no raw interpolation |
| Cursors | round-tripped verbatim into `start_cursor` (query string or JSON body) | opaque per Notion; encoded by the same paths as above |

Caller-supplied JSON bodies (page properties, filters, search params) are passed through
**unvalidated** — that is the documented contract (raw maps in, raw maps out); validation
is Notion's 400 `validation_error`. A hostile caller can send the library anything, but a
hostile caller already owns the host — this is not a boundary.

## Option precedence (T-013)

`request_opts = base ++ client.req_options` — keyword lookups take the **first**
occurrence, so `retry: false`, the auth/version headers, and the URL cannot be overridden
by `req_options`. The escape hatch can add behavior (`plug:`, `receive_timeout:`,
telemetry) but cannot silently re-route auth or defeat the library's retry ownership.
Caveat: this precedence is load-bearing and should get an explicit test; today it is
asserted only implicitly via the retry tests.

## Transport security (T-015)

No `verify:` opt-out, no `protocols:` downgrade, no plain-HTTP default anywhere in `lib/`
(verified by grep). The default base URL is `https://api.notion.com`; Req/Finch default
TLS verification applies. Deliberate plain-HTTP override of `base_url` is possible and is
covered under T-008 (host trust), not here.
