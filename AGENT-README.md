# AGENT-README

> Orientation for AI coding agents working in this repo. Human docs: README.md (plus docs/API-CONTRACT.md — endpoints, error taxonomy, non-goals).

## Type

elixir-lib (Hex package, API client)

## Purpose

Elixir client for the Notion API, pinned to `Notion-Version: 2026-03-11` — pages, databases, data sources, blocks, users, search, comments, file uploads.

## Stack

Elixir ~> 1.15. Deps: `req` (~> 0.7), `jason`; `plug` test-only. Explicit-client design (no global state): every call takes a `Noizu.Notion.Client` struct; one typed `Noizu.Notion.Error` struct; cursor pagination with lazy `*_stream` helpers.

## Dev mode

```bash
mix deps.get
mix test
```

## Ports / URLs

- none (library/CLI)

## Tests

```bash
mix test    # fully stubbed via Req.Test; no network, no real tokens
```

## Gotchas

- `NOTION_TOKEN` env feeds the quickstart (`Client.new(token: ...)`).
- Retry policy (429/529 honoring `Retry-After`; idempotent-5xx retries for GET/HEAD/DELETE only) runs inside the call — Req's built-in retry is deliberately disabled so this policy owns the wheel; configure via `retry: [max_attempts: ..., base_backoff_ms: ...]`.
