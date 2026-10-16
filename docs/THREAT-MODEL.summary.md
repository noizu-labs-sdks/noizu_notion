# Noizu.Notion — Threat Model Summary

- **Crown jewel:** the Notion bearer token in `%Noizu.Notion.Client{}` (integration /
  OAuth / PAT — handled identically, never refreshed by the library).
- **Boundaries:** host config (trusted) → library → HTTPS egress (Bearer header, TLS
  default) → untrusted server responses (bodies, error codes, Retry-After) → Hex supply
  chain (req, jason runtime; plug test; ex_doc dev).
- **Register:** 11 mitigated · 1 open (documented, T-006) · 2 accepted.
- **Recently mitigated (2026-10 security pass):**
  - T-001 (High): custom `Inspect` on `%Client{}` renders `token: "[REDACTED]"`.
  - T-002 (Medium): server-supplied `Retry-After` (header + `additional_data`) clamped
    to 30 s; negative/non-numeric values fall back to the client backoff.
  - T-004/T-003: first CI pipeline (`.github/workflows/ci.yml` — format, compile
    warnings-as-errors, tests, `mix hex.audit`, 2-entry Elixir/OTP matrix).
  - T-005 (Low): pagination failure messages carry a shape description only, never
    response fragments.
  - T-008 (Medium, accepted): `base_url`/app-env tampering redirects the bearer.
- **Key mitigations in place:** token in Authorization header only (never URLs); token
  redacted in `inspect/2`; no atoms from network data (`to_existing_atom` + known-codes
  membership); path segments percent-encoded; `req_options` cannot override auth/retry;
  missing token fails before network; `Retry-After` clamped to 30 s; no logging anywhere
  in `lib/`; CI gates every push.
- **Out of scope:** host-process compromise, Notion-side incidents, OAuth refresh.

→ Detail: [threats/token-handling.md](threats/token-handling.md) ·
[threats/request-and-retry.md](threats/request-and-retry.md) ·
[threats/file-uploads.md](threats/file-uploads.md) ·
[threats/supply-chain.md](threats/supply-chain.md)
