# Request Engine, Retry, and Untrusted Input

Threat detail for T-002, T-011–T-015 — the `Noizu.Notion.Request` engine
(`lib/noizu/notion/request.ex`), its retry policy, and how server-controlled data is
parsed. Flow and state machine: [../arch/request-lifecycle.md](../arch/request-lifecycle.md).

## T-002 (Medium) — unbounded Retry-After sleep · Mitigated

The retry delay comes from, in order (`Error.retry_after_ms/2`):

1. `retry-after` response header — `Integer.parse/1`, non-negative integers only;
2. body `additional_data.retry_after` — numbers only;
3. fallback `base_backoff_ms * attempt` (caller-controlled).

Every server-supplied hint that survives parsing is now **clamped to 30 s**
(`@max_retry_after_ms`): a `Retry-After: 2000000000` header or a
`retry_after: 86400` body field sleeps at most 30 s. Negative or non-numeric values
(`-5`, `soon`, a negative body number) yield `nil`, so the caller's own backoff applies.
The clamp lives in `Error.retry_after_ms/2`, so every caller of that function — not just
the retry loop — inherits it.

Evidence: `Noizu.Notion.ErrorTest` — `"clamps huge header and body values to the 30s cap
(T-002)"`, `"negative or non-numeric header values fall back (T-002)"`,
`"additional_data.retry_after: clamped, negatives nil, fractions kept (T-002)"` — and
`Noizu.Notion.RequestTest "clamps a huge Retry-After header to 30s, sleep function
injectable (T-002)"` (the retry loop itself, with the sleep function injected via
`retry: [sleep_fn:]` so the pre-fix behaviour — a real `Process.sleep` of ~63 years —
fails the test instead of hanging it).

Residual: 30 s is still 30 s × `max_attempts` of parked caller process against a hostile
peer; the client controls the multiplication via `retry: [max_attempts:]`.

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
