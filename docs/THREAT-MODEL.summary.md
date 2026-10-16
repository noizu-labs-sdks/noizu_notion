# Noizu.Notion — Threat Model Summary

- **Crown jewel:** the Notion bearer token in `%Noizu.Notion.Client{}` (integration /
  OAuth / PAT — handled identically, never refreshed by the library).
- **Boundaries:** host config (trusted) → library → HTTPS egress (Bearer header, TLS
  default) → untrusted server responses (bodies, error codes, Retry-After) → Hex supply
  chain (req, jason runtime; plug test; ex_doc dev).
- **Register:** 6 mitigated · 1 partial · 5 open · 2 accepted.
- **Top open items:**
  - T-001 (High): token visible to `inspect/2` — no redacted Inspect on `%Client{}`.
  - T-002 (Medium): server-controlled `Retry-After` slept unbounded (`Process.sleep/1`,
    no clamp) — can park the calling process.
  - T-003 (Medium, partial): Hex dep compromise — lockfile committed, but no automated
    audit.
  - T-008 (Medium, accepted): `base_url`/app-env tampering redirects the bearer.
- **Key mitigations in place:** token in Authorization header only (never URLs); no
  atoms from network data (`to_existing_atom` + known-codes membership); path segments
  percent-encoded; `req_options` cannot override auth/retry; missing token fails before
  network; no logging anywhere in `lib/`.
- **Out of scope:** host-process compromise, Notion-side incidents, OAuth refresh.

→ Detail: [threats/token-handling.md](threats/token-handling.md) ·
[threats/request-and-retry.md](threats/request-and-retry.md) ·
[threats/file-uploads.md](threats/file-uploads.md) ·
[threats/supply-chain.md](threats/supply-chain.md)
