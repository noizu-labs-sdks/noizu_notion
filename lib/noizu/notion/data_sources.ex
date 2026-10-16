defmodule Noizu.Notion.DataSources do
  @moduledoc """
  Data source operations — the tables inside a database.

  Since API version 2025-09-03, querying rows and managing the property schema happen
  on `/v1/data_sources/{data_source_id}`; the `data_source_id` comes from
  `Noizu.Notion.Databases.retrieve/2` (`data_sources` list) or from a page parent.
  """

  alias Noizu.Notion.{Client, Pagination, Request}

  @doc """
  Creates a data source inside an existing database. `POST /v1/data_sources`.

  `params`: `parent` (must contain `database_id`), `properties` (required schema map),
  optionally `title` and `icon`.
  """
  @spec create(Client.t(), map()) :: {:ok, map()} | {:error, Noizu.Notion.Error.t()}
  def create(client, params) when is_map(params) do
    Request.perform(client, :post, "/v1/data_sources", json: params)
  end

  @doc """
  Retrieves a data source and its column schema. `GET /v1/data_sources/{data_source_id}`.
  """
  @spec retrieve(Client.t(), String.t()) :: {:ok, map()} | {:error, Noizu.Notion.Error.t()}
  def retrieve(client, data_source_id) when is_binary(data_source_id) do
    Request.perform(client, :get, "/v1/data_sources/" <> Request.encode_segment(data_source_id))
  end

  @doc """
  Updates a data source. `PATCH /v1/data_sources/{data_source_id}`.

  `params` may include `title`, `icon`, `in_trash`, `parent` (move to another
  database), and `properties` — where each entry is a full type config, a rename
  `{"name" => new_name}`, or `nil` to remove the property. The `title` property cannot
  be removed or converted.
  """
  @spec update(Client.t(), String.t(), map()) :: {:ok, map()} | {:error, Noizu.Notion.Error.t()}
  def update(client, data_source_id, params) when is_binary(data_source_id) and is_map(params) do
    Request.perform(client, :patch, "/v1/data_sources/" <> Request.encode_segment(data_source_id),
      json: params
    )
  end

  @doc """
  Queries a data source's rows. `POST /v1/data_sources/{data_source_id}/query`.

  `params` is the request body: `filter`, `sorts`, `page_size`, `is_archived`,
  `result_type` (`page` | `data_source`; wiki only). `start_cursor` is managed here —
  do not pass it in `params` for streamed calls. Note `in_trash` is **not** accepted by
  this endpoint (use `is_archived`); results cap at 10 000 with
  `request_status.type: "incomplete"` in the raw envelope.

  ## Options

    * `:filter_properties` — list of property names/IDs limiting each row's `properties`.
  """
  @spec query(Client.t(), String.t(), map(), keyword()) ::
          {:ok, map()} | {:error, Noizu.Notion.Error.t()}
  def query(client, data_source_id, params \\ %{}, opts \\ [])
      when is_binary(data_source_id) and is_map(params) and is_list(opts) do
    Request.perform(
      client,
      :post,
      "/v1/data_sources/" <> Request.encode_segment(data_source_id) <> "/query",
      json: params,
      params: filter_properties_params(opts)
    )
  end

  @doc """
  Streams query result rows across cursors. Raises a `Noizu.Notion.Error` if a page
  fetch fails; ends silently at the server-side 10 000-result cap (see `query/4`).
  """
  @spec query_stream(Client.t(), String.t(), map(), keyword()) :: Enumerable.t(map())
  def query_stream(client, data_source_id, params \\ %{}, opts \\ [])
      when is_binary(data_source_id) and is_map(params) and is_list(opts) do
    path = "/v1/data_sources/" <> Request.encode_segment(data_source_id) <> "/query"

    Pagination.stream(fn cursor ->
      Request.perform(client, :post, path,
        json: Pagination.with_cursor_in_body(params, cursor),
        params: filter_properties_params(opts)
      )
    end)
  end

  @doc """
  Lists a data source's template pages. `GET /v1/data_sources/{data_source_id}/templates`.

  Non-standard envelope: results are extracted from the `"templates"` key.

  ## Options

    * `:start_cursor`, `:page_size`, `:name` (case-insensitive substring filter).
  """
  @spec list_templates(Client.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, Noizu.Notion.Error.t()}
  def list_templates(client, data_source_id, opts \\ []) when is_binary(data_source_id) do
    path =
      "/v1/data_sources/" <> Request.encode_segment(data_source_id) <> "/templates"

    Request.perform(client, :get, path, params: Pagination.with_cursor(opts, opts[:start_cursor]))
  end

  @doc "Streams data source template entries (`\"templates\"` key)."
  @spec list_templates_stream(Client.t(), String.t(), keyword()) :: Enumerable.t(map())
  def list_templates_stream(client, data_source_id, opts \\ []) when is_binary(data_source_id) do
    path =
      "/v1/data_sources/" <> Request.encode_segment(data_source_id) <> "/templates"

    Pagination.stream(
      fn cursor ->
        Request.perform(client, :get, path, params: Pagination.with_cursor(opts, cursor))
      end,
      results_key: "templates"
    )
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
