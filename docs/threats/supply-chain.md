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

## T-003 (Medium) — compromised Hex dependency · Partial

A malicious or hijacked release within `~>` bounds executes inside every consumer's
process, with full access to the token this library holds and to the host. Current
controls:

- `mix.lock` is committed — reproducible builds; consumers get exactly the audited
  versions unless they deliberately update.
- Constraints are bounded ranges, not `>=` — no silent major-version drift.
- The runtime tree is minimal and `req`/`finch` are mainstream, widely-watched packages.

Missing controls:

- No automated vulnerability/retirement auditing (`mix hex.audit`, `mix deps.audit`
  via `hex_audit`, renovate/dependabot) — nothing in the repo runs them.
- No CI to run anything on a schedule (see T-004).

Consumer guidance shipped in `README.md`/`mix.exs` cannot fix this; the repo needs the
tooling. Minimum viable: a CI job running `mix deps.get && mix test && mix hex.audit`
and a renovate config pinned to `mix.lock`.

## T-004 (Low) — no CI pipeline · Open

The repo has **no `.github/` directory at all** — no workflow gates tests, formatting
(`mix format --check-formatted`), compilation warnings, or dependency audits on push or
PR. The README's Development section assumes a human runs these locally. Consequence:
regressions and supply-chain drift reach `main` (and then Hex via a manual
`mix hex.publish`) with no automated check. For a credential-handling library the test
suite is also the security regression net (atom-safety, filter_properties encoding,
retry behavior are byte-exact assertions) — it should run on every push.

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
