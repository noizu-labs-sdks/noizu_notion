# Noizu.Notion — Project Layout

Navigable map of the repository. One-line descriptions say *what lives where*; how it
works is `docs/PROJ-ARCH.md`, the wire-level promise is `docs/API-CONTRACT.md`.

```
noizu_notion/
├── lib/                              # Library source → [layout/lib.md](layout/lib.md)
│   └── noizu/
│       ├── notion.ex                 # Facade: Noizu.Notion.new/1 + resource index
│       └── notion/                   # 13 modules: client, request engine, resources
├── test/                             # Mix test suite (Req.Test stubs, no network)
│   ├── noizu/notion_test.exs         # Resource-level behavior (endpoints, params, streams)
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
│   ├── THREAT-MODEL.md               # Security threat model
│   └── layout/                       # Per-directory detail extracted from this file
├── .formatter.exs                    # mix format config (Elixir 1.20 style)
├── .gitignore                        # /_build/, /deps/, /doc/, /cover/, tarballs
├── mix.exs                           # Project: app :noizu_notion, Hex package metadata
├── mix.lock                          # Locked dependency versions
├── CHANGELOG.md                      # Release notes (Keep-a-changelog style, newest first)
├── LICENSE                           # MIT
└── README.md                         # Start here: install, quickstart, errors, config
```

## Directories

### `lib/` — see [layout/lib.md](layout/lib.md)

Thirteen modules under `lib/noizu/notion/`. Three layers: the public facade
(`Noizu.Notion`), shared machinery (`Client`, `Request`, `Error`, `Pagination`), and one
resource module per Notion object (`Pages`, `Databases`, `DataSources`, `Blocks`,
`Users`, `Search`, `Comments`, `FileUploads`).

### `test/`

Every test is stubbed through `Req.Test` plugs built by `Noizu.Notion.Testing.client/2`
— no network, no real tokens. `test/support` is compiled into the `:test` environment
only (`elixirc_paths/1` in `mix.exs`).

### `docs/`

Contract-first documentation. `API-CONTRACT.md` is the source of truth for the client's
behavior; the architecture and threat-model docs reference it rather than restating it.

## Key files

| File | Notes |
|---|---|
| `mix.exs` | App `:noizu_notion`, version `0.1.0`, Elixir `~> 1.20`. Runtime deps: `req ~> 0.7` (multipart send requires ≥ 0.7), `jason ~> 1.4`. Test-only: `plug`. Dev-only: `ex_doc`. Hex package ships `lib`, `docs`, `mix.exs`, `README.md`, `LICENSE`, `CHANGELOG.md`, `.formatter.exs`. |
| `mix.lock` | Locked dep versions; regen with `mix deps.update --all` only deliberately. |
| `.formatter.exs` | Standard Elixir formatter input glob. |

Nothing in the repo requires manual configuration — the library reads no config files;
the only runtime configuration surface is the optional `:noizu_notion, :client`
application env (keyword list) and the `Noizu.Notion.Client` struct itself. Tokens come
from the host application's environment (e.g. `NOTION_TOKEN`) — the library never loads
dotenv/direnv files itself.
