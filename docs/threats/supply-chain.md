# Supply Chain

Threat detail for T-003, T-004 — Hex dependencies and the published package.

## Dependency inventory (from `mix.exs` / `mix.lock`, verified)

| Dep | Constraint | Locked | Scope | Role |
|---|---|---|---|---|
| `req` | `~> 0.7` | 0.7.5 | **runtime** | HTTP client (JSON + multipart). Floor is functional: `form_multipart` requires ≥0.7. Pulls `finch` (non-optional), `jason`, `mime`, plus optional `brotli`/`nimble_csv`. |
| `jason` | `~> 1.4` | — | **runtime** | JSON decode fallback + test encoding. |
| `plug` | `~> 1.16` | — | **test only** | `Req.Test` plug stubs. |
| `ex_doc` | `~> 0.37` | — | **dev only, no runtime** | Hex docs. |

Runtime surface is deliberately tiny: two direct deps. `req`'s transitive tree (finch,
mint, castore/etc. via CA store, nimble_options) is the real trust footprint.

## T-003 (Medium) — compromised Hex dependency · Mitigated

A malicious or hijacked release within `~>` bounds executes inside every consumer's
process, with full access to the token this library holds and to the host. Controls in
place:

- `mix.lock` is committed — reproducible builds; consumers get exactly the audited
  versions unless they deliberately update.
- Constraints are bounded ranges, not `>=` — no silent major-version drift.
- The runtime tree is minimal and `req`/`finch` are mainstream, widely-watched packages.
- **CI runs `mix hex.audit`** on every push and PR (T-004 fixed), catching retired or
  unreachable packages in the tree.

Residual risk, inherent to any small library: a *future* in-bounds release that is
compromised but not yet retired passes `hex.audit` until flagged; no renovate/dependabot
config gates lockfile drift yet. Reviewed, deliberate bumps remain the second control.

## T-004 (Low) — no CI pipeline · Mitigated

`.github/workflows/ci.yml` now gates every push and PR against `develop`, `stage`, and
`main`: `mix deps.get`, `mix format --check-formatted`, `mix compile --warnings-as-errors`,
`mix test`, and `mix hex.audit`, on a three-entry matrix (Elixir 1.15.8/OTP 26 — the
supported floor, since `mix.exs` requires `~> 1.15` and every locked dep also declares
`~> 1.15` — plus 1.18.4/OTP 27 and 1.20.4/OTP 29), with `deps`/`_build` cached and action
versions pinned to majors.
For a credential-handling library the test suite is also the security regression net
(atom-safety, filter_properties encoding, retry clamping, token redaction are byte-exact
assertions) — it now runs on every push.

## Published package (downstream supply chain)

- `mix.exs` `files:` ships `lib`, `docs`, `mix.exs`, `README.md`, `LICENSE`,
  `CHANGELOG.md`, `.formatter.exs` — no tests, no lock file in the tarball (Hex default),
  nothing that executes at package-install time.
- Runtime contract is honest: no application module, no `:start_permanent` services, no
  config injection — consumers start nothing by depending on it.
- Release path is manual (`mix hex.publish`) with no CI-driven publish; publishing is
  out of scope for agents per project rules.
- Version pinning guidance for consumers: depend on `~> 0.1` and keep a lockfile; treat
  any `base_url` override shipped in shared config with the same care as a secret (T-008).

## Provenance verification quick-reference

```sh
mix hex.audit                     # retired/unreachable packages in the tree
mix deps                          # constraint vs locked overview
git diff mix.lock                 # review before ANY dependency bump
```

Hex verifies package checksums against the registry on fetch (checksums live in
`mix.lock`), which protects integrity in transit but not a malicious upload by the
maintainer account — hence audit tooling and deliberate, reviewed bumps.
