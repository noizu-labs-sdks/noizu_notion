# Noizu.Notion

Elixir client for the [Notion API](https://developers.notion.com/reference/intro), pinned to
`Notion-Version: 2026-03-11`. Explicit-client, no global state: every call takes a
`Noizu.Notion.Client` struct and returns `{:ok, map}` or `{:error, %Noizu.Notion.Error{}}`.

- **Resources** — pages, databases, data sources, blocks, users, search, comments, file uploads
- **Pagination** — one-shot `{:ok, list_page}` plus lazy `*_stream/2..4` helpers that walk
  `start_cursor`/`has_more` for you
- **Errors** — one struct (`status`, `code`, `message`, `request_id`, `additional_data`),
  documented codes as atoms, unknown codes kept as strings
- **Retry** — bounded 429/529 retries honoring `Retry-After`; idempotent-5xx retries only
  for `GET`/`HEAD`/`DELETE` (Req's built-in retry is disabled so this policy owns the wheel)
- **Tests** — fully stubbed via `Req.Test`; no network, no real tokens

Full contract (endpoints, error taxonomy, rate limits, what is intentionally not covered):
[`docs/API-CONTRACT.md`](docs/API-CONTRACT.md).

## Installation

```elixir
def deps do
  [
    {:noizu_notion, "~> 0.1"}
  ]
end
```

## Quickstart

```elixir
client = Noizu.Notion.Client.new(token: System.fetch_env!("NOTION_TOKEN"))

{:ok, me} = Noizu.Notion.Users.me(client)

# Query rows from a data source (the table inside a database, API 2025-09-03+)
{:ok, page} =
  Noizu.Notion.DataSources.query(client, data_source_id, %{
    "filter" => %{"property" => "Done", "checkbox" => %{"equals" => true}},
    "page_size" => 100
  })

# Or stream every matching row across cursors
Noizu.Notion.DataSources.query_stream(client, data_source_id)
|> Enum.each(&IO.puts(&1["id"]))

# Create a page under a data source parent
{:ok, page} =
  Noizu.Notion.Pages.create(client, %{
    "parent" => %{"data_source_id" => data_source_id},
    "properties" => %{"Name" => %{"title" => [%{"text" => %{"content" => "Hello"}}]}}
  })

# Soft-delete a block (trash), restore later
{:ok, _} = Noizu.Notion.Blocks.delete(client, block_id)
{:ok, _} = Noizu.Notion.Blocks.restore(client, block_id)
```

## Errors

```elixir
case Noizu.Notion.Pages.retrieve(client, page_id) do
  {:ok, page} -> page
  {:error, %Noizu.Notion.Error{status: 404, code: :object_not_found}} -> :gone
  {:error, %Noizu.Notion.Error{code: :rate_limited}} -> :already_retried_for_you
  {:error, other} -> raise other
end
```

Retries (429/529 with `Retry-After`, idempotent 5xx) happen inside the call; when you get
`%Error{}` the documented attempt budget is spent. Configure it:

```elixir
Noizu.Notion.Client.new(token: token, retry: [max_attempts: 5, base_backoff_ms: 250])
```

## Optional app-env default

```elixir
# config/config.exs (runtime: config is read at call time via Application.get_env)
config :noizu_notion, :client, token: System.get_env("NOTION_TOKEN")
```

`Client.new/1` precedence: function opts → app env → defaults. Passing an explicit
client everywhere still works and remains the primary style.

## Development

```sh
mix deps.get
mix format --check-formatted
mix compile --warnings-as-errors
mix test
mix docs
mix hex.build
```

## License

MIT — see [LICENSE](LICENSE).
