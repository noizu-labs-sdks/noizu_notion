defmodule Noizu.Notion do
  @moduledoc """
  Elixir client for the [Notion API](https://developers.notion.com/reference/intro),
  pinned to `Notion-Version: #{Noizu.Notion.Client.api_version()}`.

  All calls take an explicit `Noizu.Notion.Client` struct as the first argument and
  return `{:ok, map}` or `{:error, %Noizu.Notion.Error{}}` — no global state, no
  raising bang variants. Responses stay raw maps (tolerant reader: unknown fields are
  preserved and ignored).

      client = Noizu.Notion.Client.new(token: System.fetch_env!("NOTION_TOKEN"))

      {:ok, me} = Noizu.Notion.Users.me(client)

      {:ok, page} =
        Noizu.Notion.Pages.create(client, %{
          "parent" => %{"data_source_id" => ds_id},
          "properties" => %{"Name" => %{"title" => [%{"text" => %{"content" => "Hello"}}]}}
        })

      Noizu.Notion.DataSources.query_stream(client, ds_id)
      |> Enum.take(50)

  ## Resources

    * `Noizu.Notion.Pages` — create/retrieve/update/trash/move, per-property reads
    * `Noizu.Notion.Databases` — database containers (create/retrieve/update)
    * `Noizu.Notion.DataSources` — table schema + queries (`query_stream/4`)
    * `Noizu.Notion.Blocks` — retrieve/update/delete, children list + append
    * `Noizu.Notion.Users` — list/retrieve/me (`list_stream/2`)
    * `Noizu.Notion.Search` — workspace search (`search_stream/3`)
    * `Noizu.Notion.Comments` — create/list/retrieve/update/delete
    * `Noizu.Notion.FileUploads` — upload lifecycle (create/send/complete/retrieve/list)

  Errors, retry (429/529 + `Retry-After`, idempotent 5xx), and pagination are specified
  in `docs/API-CONTRACT.md` — read it before building on this library.
  """

  defdelegate new(opts \\ []), to: Noizu.Notion.Client
end
