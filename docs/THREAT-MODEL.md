# Threat Model

〚📁:𓉇𓁀𓜂𓔪〛 noizu_notion threat model :: Threat model: token handling, untrusted input, retry DoS, uploads, Hex supply chain; vulnerability register.

Living threat model for `noizu_notion` — an Elixir client **library** (not a service).
The crown jewel is the **Notion bearer token** (internal integration token, OAuth token,
or personal access token) held in `%Noizu.Notion.Client{}`: whoever holds it gets every
capability the connection was granted, against every page in scope. Second-order asset:
the workspace content that flows through responses as raw maps.

## Scope and posture

The library starts no processes, opens no listeners, writes nothing to disk, and performs
no logging of its own. Its entire attack surface is: (1) how it holds and transmits the
token, (2) how it parses server-controlled responses, (3) its two runtime Hex
dependencies (`req ~> 0.7`, `jason ~> 1.4`), and (4) what it publishes to Hex for
downstream consumers. Threats that require control of the host process (env vars, app
env, memory) are the host application's threat model, not this one — the library treats
the host as trusted.

## Trust boundaries

```
Host app config (env vars, :noizu_notion app env)   ← trusted (host's problem)
        │  Client.new(token:, base_url:, req_options:)
        ▼
┌─────────────────────────────────────────────────────┐
│ noizu_notion library code (this threat model)       │
│   token in %Client{} · retry policy · JSON parsing  │
└─────────────────────────────────────────────────────┘
        │  HTTPS + Bearer (Req/Finch, TLS-verified)      ← boundary 1: egress
        ▼
   api.notion.com                                     ← untrusted peer after TLS
        │  JSON responses, error envelopes, Retry-After headers, cursors
        ▼
   response parsing (raw maps, atoms policy)          ← boundary 2: untrusted input
```

- **Boundary 1 (egress):** the token crosses in the `Authorization` header only; TLS
  verification is Req/Finch default (no opt-outs in the codebase).
- **Boundary 2 (ingress parse):** everything the server returns is untrusted data —
  bodies, error codes, `Retry-After` values, cursors — fed into maps, exceptions, and
  sleep durations.
- **Hex supply chain:** locked dependencies enter the host's build; the published Hex
  package enters every consumer's build.

→ *Per-boundary detail: [threats/token-handling.md](threats/token-handling.md),
[threats/request-and-retry.md](threats/request-and-retry.md),
[threats/file-uploads.md](threats/file-uploads.md),
[threats/supply-chain.md](threats/supply-chain.md)*

## Attack Surface

```mermaid
graph LR
    subgraph Host["Host application (trusted)"]
        C["Caller code"]
        E["NOTION_TOKEN env"]
    end
    subgraph Lib["noizu_notion"]
        S["%Client{} — token field<br/>(inspect-redacted: T-001)"]
        R["Request engine<br/>headers, retry loop"]
        P["Parsers: body, error<br/>envelope, Retry-After"]
        M["multipart send_file<br/>(whole file in memory: T-006)"]
    end
    N[("api.notion.com<br/>untrusted responses")]
    H["Hex + mix.lock deps<br/>(req, jason: T-003)"]

    E --> C --> S --> R
    R -->|"Bearer header, TLS"| N
    N -->|"JSON, error codes,<br/>Retry-After (T-002, clamped)"| P --> R
    C -->|"file bytes"| M --> R
    H -.->|"build time"| Lib
```

## Vulnerability Register

〚🧩:𓥰𓠙𔍟𓪸〛 noizu_notion vulnerability register :: Stable-ID vulnerability register (T-001..): severity, STRIDE, component, status; referenced from threats/*.md.

| ID | Severity | STRIDE | Component | Finding | Status |
|---|---|---|---|---|---|
| T-001 | High | Information disclosure | `Client` struct | `token` is a plain struct field with no redacted `Inspect` implementation — any `inspect/2`, crash-report, or `Logger.debug` that touches a client leaks the credential in plaintext logs | **Mitigated** — custom `Inspect` renders `token: "[REDACTED]"` (`Noizu.Notion.ClientTest "inspect/2 never prints the bearer token"`) |
| T-002 | Medium | Denial of service | Retry loop | Server-controlled `Retry-After` (header or `additional_data`) is slept verbatim with `Process.sleep/1` — no upper clamp; a hostile/broken peer parks the calling process indefinitely (contract documents ≤60 s but the code does not enforce it) | **Mitigated** — `Error.retry_after_ms/2` clamps all server-supplied hints to 30 s; negative/non-numeric fall back to the client backoff (`Noizu.Notion.ErrorTest "clamps huge header and body values to the 30s cap"`, `Noizu.Notion.RequestTest "clamps a huge Retry-After header to 30s, sleep function injectable"`) |
| T-003 | Medium | Supply chain | Hex deps | Compromised `req`/`jason` release within `~>` bounds executes with host privileges and token access. Mitigations: `mix.lock` committed, bounded ranges, tiny runtime dep tree, automated `mix hex.audit` in CI | **Mitigated** — audit + lock + bounded ranges in CI (`.github/workflows/ci.yml`); residual: a future in-bounds compromised release and un-pinned renovate bumps remain inherent to any small library |
| T-004 | Low | Supply chain / Tampering | Repository | No CI pipeline exists (no `.github/`): nothing gates tests, formatting, or dependency audits on push/PR | **Mitigated** — `.github/workflows/ci.yml`: format + `compile --warnings-as-errors` + test + `hex.audit`, 3-entry Elixir/OTP matrix (1.15.8/OTP 26 floor, 1.18.4/OTP 27, 1.20.4/OTP 29), on push and PR for develop/stage/main |
| T-005 | Low | Information disclosure | Pagination errors | Malformed-envelope failures embed `inspect(other, limit: 5)` of the raw response into exception messages — workspace-content fragments can reach host logs | **Mitigated** — messages carry a shape description (kind + size) only (`Noizu.Notion.PaginationTest "failure messages describe shape, not content"`) |
| T-006 | Low | Denial of service | `FileUploads.send_file/3` | File contents are passed as one binary: the whole file (multi-part mode targets >20 MiB, up to 10 000 parts) is buffered in caller memory; no streaming path | **Open** (documented) |
| T-007 | Low | Tampering | Retry + multipart | 429/529 retry applies to POST; a `send` that processed server-side but answered 529 could re-send a part. Consequence limited: same `part_number` overwrite, per-part idempotency | **Accepted** |
| T-008 | Medium | Information disclosure / EoP | `Client` options | `base_url` and `req_options` are host-controlled: config tampering (or a hostile default in `:noizu_notion, :client`) redirects the bearer token to an attacker's host. By design — the host is trusted; noted so consumers treat client config as secret-sensitive | **Accepted** |
| T-010 | — | Spoofing | Token transport | Token never appears in URLs or query strings — header only, so it stays out of proxy/access logs | Mitigated |
| T-011 | — | Tampering | Atom table | No atoms are created from network data: error codes go through `String.to_existing_atom/1` + `known_codes/0` membership; unlisted codes stay strings | Mitigated |
| T-012 | — | Tampering | Path building | Every ID interpolated into a URL path passes `Request.encode_segment/1` (percent-encoding, unreserved chars only) | Mitigated |
| T-013 | — | Tampering | Option precedence | `req_options` cannot override library-owned keys (`retry: false`, auth/version headers) — library options precede in the merged keyword, first occurrence wins | Mitigated |
| T-014 | — | Spoofing | Missing token | Absent/empty token fails fast (`{:error, 401 unauthorized}`) before any network I/O — no unauthenticated requests are ever sent | Mitigated |
| T-015 | — | Spoofing | Transport | TLS certificate verification is Req/Finch default; no `verify: false`, no plain-HTTP default (base URL is `https://api.notion.com`; a caller may still point `base_url` at plain HTTP deliberately — see T-008) | Mitigated |

〚/🧩:𓥰𓠙𔍟𓪸〛

## Mitigation Coverage

11 mitigated · 1 open (documented, T-006) · 2 accepted. The 2026-10 security pass
closed T-001 (redacted `Inspect` on `%Client{}`), T-002 (30 s clamp on all
server-supplied `Retry-After` hints), and T-005 (shape-only pagination failure
messages), and added the first CI pipeline (T-004) with `mix hex.audit` (T-003).

## Residual Risk

- **Host-process compromise is out of scope** (T-008): anything that can read env vars,
  app env, or process memory owns the token regardless of this library.
- **Server compromise / Notion-side incidents** out of scope: the library is a faithful
  transporter of whatever api.notion.com returns.
- **Retry-duplication ambiguity** (T-007): accepted — Notion's own guidance is that 429/529
  did not apply the write; per-part overwrite bounds the damage for uploads.
- **In-memory file buffering** (T-006): accepted for v0.1 — callers streaming huge files
  should chunk multi-part sends themselves.
