defmodule Noizu.Notion.Search do
  @moduledoc """
  Workspace-wide search over pages and data sources shared with the connection.
  `POST /v1/search` — results exclude duplicated linked databases.
  """

  alias Noizu.Notion.{Client, Pagination, Request}

  @doc """
  Searches. `POST /v1/search`.

  `params` is the request body: `query` (title substring; omit for everything shared),
  `filter` (`{"property" => "object", "value" => "page" | "data_source"}` plus optional
  `"in_trash"`, or `{"in_trash" => bool}`), `sort` (`{"timestamp" => "last_edited_time",
  "direction" => ...}` or `{"property" => "relevance"}`), `page_size`. `start_cursor` is
  managed here — do not pass it in `params` for streamed calls.

  ## Options

    * `:filter_properties` — list of property names/IDs limiting page `properties`.
  """
  @spec search(Client.t(), map(), keyword()) :: {:ok, map()} | {:error, Noizu.Notion.Error.t()}
  def search(client, params \\ %{}, opts \\ [])
      when is_map(params) and is_list(opts) do
    Request.perform(client, :post, "/v1/search",
      json: params,
      params: filter_properties_params(opts)
    )
  end

  @doc """
  Streams search results across cursors. Raises a `Noizu.Notion.Error` if a page fetch
  fails.
  """
  @spec search_stream(Client.t(), map(), keyword()) :: Enumerable.t(map())
  def search_stream(client, params \\ %{}, opts \\ [])
      when is_map(params) and is_list(opts) do
    Pagination.stream(fn cursor ->
      Request.perform(client, :post, "/v1/search",
        json: Pagination.with_cursor_in_body(params, cursor),
        params: filter_properties_params(opts)
      )
    end)
  end

  defp filter_properties_params(opts) do
    case Keyword.get(opts, :filter_properties) do
      values when is_list(values) and values != [] ->
        for v <- values, do: {"filter_properties", v}

      _ ->
        []
    end
  end
end
