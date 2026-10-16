# Noizu.Notion — Layout Summary

```
noizu_notion/
├── lib/                        # Library source → [layout/lib.md](layout/lib.md)
│   └── noizu/
│       ├── notion.ex           # Facade
│       └── notion/             # client, request, error, pagination + 8 resource modules
├── test/                       # Req.Test-stubbed suite, no network
│   ├── noizu/                  # notion_test + request/error/pagination tests
│   └── support/testing.ex      # Plug-stub helpers + fixtures
├── docs/                       # API-CONTRACT, PROJ-LAYOUT(+summary), PROJ-ARCH, THREAT-MODEL, layout/
├── .formatter.exs              # mix format config
├── .gitignore                  # _build/, deps/, doc/, cover/, tarballs
├── mix.exs                     # :noizu_notion, deps: req ~> 0.7, jason ~> 1.4
├── mix.lock                    # Locked dep versions
├── CHANGELOG.md                # Release notes
├── LICENSE                     # MIT
└── README.md                   # Install + quickstart
```
