# Noizu.Notion — Project Layout

Navigable map of the repository. One-line descriptions say *what lives where*; how it
works is `docs/PROJ-ARCH.md`, the wire-level promise is `docs/API-CONTRACT.md`.

```
noizu_notion/
├── lib/                              # Library source → [layout/lib.md](layout/lib.md)
│   └── noizu/
│       ├── notion.ex                 # Facade: Noizu.Notion.new/1 + resource index
│       └── notion/                   # 12 modules: client, request engine, error,
│                                     #   pagination + 8 resource modules
├── test/                             # Mix test suite (Req.Test stubs, no network)
│   ├── noizu/notion_test.exs         # Resource-level behavior (endpoints, params, streams)
│   ├── noizu/notion/client_test.exs  # Client struct, option precedence, token redaction
│   ├── noizu/notion/request_test.exs # Request engine: headers, retry, multipart
│   ├── noizu/notion/error_test.exs   # Error envelope, code normalization, retryability
│   ├── noizu/notion/pagination_test.exs
│   ├── support/testing.ex            # Noizu.Notion.Testing — plug-stub helpers + fixtures
│   └── test_helper.exs
├── docs/                             # House documentation
│   ├── API-CONTRACT.md               # Wire contract: versioning, auth, endpoints, errors
│   ├── PROJ-LAYOUT.md                # This file
│   ├── PROJ-LAYOUT.summary.md        # Plain-tree companion
│   ├── PROJ-ARCH.md                  # Architecture
│   ├── PROJ-ARCH.summary.md          # Architecture quick reference
│   ├── PROJ-SCHEMA.md                # Data-shape reference (config, envelopes, fixtures)
│   ├── PROJ-SCHEMA.summary.md        # Schema quick reference
│   ├── THREAT-MODEL.md               # Security threat model
│   ├── THREAT-MODEL.summary.md       # Threat-model quick reference
│   ├── layout/lib.md                 # Per-directory detail extracted from this file
│   ├── arch/request-lifecycle.md     # Request flow + retry state machine
│   └── threats/                      # Per-boundary threat detail (4 files)
├── .meta/pointers.yaml               # Doc-pointer store (UUID → locus); written by the tool
├── .github/workflows/ci.yml          # CI: format, compile, test, hex.audit (3-way matrix)
├── .formatter.exs                    # mix format inputs (mix/.formatter.exs, config, lib, test)
├── .gitignore                        # /_build/, /deps/, /doc/, /cover/, tarballs
├── mix.exs                           # Project: app :noizu_notion, Hex package metadata
├── mix.lock                          # Locked dependency versions
├── CHANGELOG.md                      # Release notes (Keep-a-changelog style, newest first)
├── LICENSE                           # MIT
└── README.md                         # Start here: install, quickstart, errors, config
```

## Directories

### `lib/` — see [layout/lib.md](layout/lib.md)

Twelve modules under `lib/noizu/notion/` (thirteen `defmodule`s including the facade).
Three layers: the public facade (`Noizu.Notion`), shared machinery (`Client`, `Request`,
`Error`, `Pagination`), and one resource module per Notion object (`Pages`, `Databases`,
`DataSources`, `Blocks`, `Users`, `Search`, `Comments`, `FileUploads`).

### `test/`

Every test is stubbed through `Req.Test` plugs built by `Noizu.Notion.Testing.client/2`
— no network, no real tokens. `test/support` is compiled into the `:test` environment
only (`elixirc_paths/1` in `mix.exs`).

### `docs/`

Contract-first documentation. `API-CONTRACT.md` is the source of truth for the client's
behavior; the architecture, schema, and threat-model docs reference it rather than
restating it. Each `PROJ-*`/`THREAT-MODEL` doc has a `.summary.md` companion kept in sync;
`layout/`, `arch/`, and `threats/` hold the extracted per-area detail.

### `.meta/`

Doc-pointer store for the repo (one `.meta/pointers.yaml`, paths relative to this
repository). Maintained by the `doc-pointers` CLI/MCP; verify with
`doc-pointers build --root . --check`.

## Key files

| File | Notes |
|---|---|
| `mix.exs` | App `:noizu_notion`, version `0.1.0`, Elixir `~> 1.15` (floor; CI runs 1.15.8/OTP 26, 1.18.4/OTP 27, 1.20.4/OTP 29). Runtime deps: `req ~> 0.7` (multipart send requires ≥ 0.7), `jason ~> 1.4`. Test-only: `plug`. Dev-only: `ex_doc`. Hex package ships `lib`, `docs`, `mix.exs`, `README.md`, `LICENSE`, `CHANGELOG.md`, `.formatter.exs`. `@source_url` is `github.com/noizu-labs-sdks/noizu_notion`. |
| `mix.lock` | Locked dep versions; regen with `mix deps.update --all` only deliberately. |
| `.formatter.exs` | Standard Elixir formatter input glob (`mix`/`.formatter.exs`, `config`, `lib`, `test`). |
| `.github/workflows/ci.yml` | CI on push/PR for `develop`/`stage`/`main`: `mix deps.get`, `mix format --check-formatted`, `mix compile --warnings-as-errors`, `mix test`, `mix hex.audit`. |
| `.meta/pointers.yaml` | Doc-pointer store (UUID → locus); written by `doc-pointers`, never hand-edited. |

Nothing in the repo requires manual configuration — the library reads no config files;
the only runtime configuration surface is the optional `:noizu_notion, :client`
application env (keyword list) and the `Noizu.Notion.Client` struct itself. Tokens come
from the host application's environment (e.g. `NOTION_TOKEN`) — the library never loads
dotenv/direnv files itself.
