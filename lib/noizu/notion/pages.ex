defmodule Noizu.Notion.Pages do
  @moduledoc """
  Page operations — create, retrieve, update, trash/restore, move, and per-property
  reads. Paths per `docs/API-CONTRACT.md` §4.1 (`Notion-Version: #{Noizu.Notion.Client.api_version()}`).

  Page properties must match the parent data source's schema (a `title` property is the
  only valid one under a plain page parent). Responses are raw maps — full or partial
  page objects per Notion's response-shape rules.
  """

  alias Noizu.Notion.{Client, Pagination, Request}

  @doc """
  Creates a page. `POST /v1/pages`.

  `params` is the request body: `parent` (`page_id` | `data_source_id` | `database_id` |
  `workspace`), `properties`, `icon`, `cover`, and optionally `content`/`children`
  (mutually exclusive with `markdown`), `markdown` + `markdown_version`, `allow_async`
  (returns a 202 async-task object), `template`, `position`, `notifications`.

  ## Options

    * `:filter_properties` — list of property names/IDs limiting returned properties.
  """
  @spec create(Client.t(), map(), keyword()) :: {:ok, map()} | {:error, Noizu.Notion.Error.t()}
  def create(client, params, opts \\ []) when is_map(params) and is_list(opts) do
    Request.perform(client, :post, "/v1/pages",
      json: params,
      params: filter_properties_params(opts)
    )
  end

  @doc """
  Retrieves a page. `GET /v1/pages/{page_id}`.

  ## Options

    * `:filter_properties` — list of property names/IDs limiting returned properties.
  """
  @spec retrieve(Client.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, Noizu.Notion.Error.t()}
  def retrieve(client, page_id, opts \\ []) when is_binary(page_id) do
    Request.perform(client, :get, "/v1/pages/" <> Request.encode_segment(page_id),
      params: filter_properties_params(opts)
    )
  end

  @doc """
  Updates a page's properties/icon/cover or trash state. `PATCH /v1/pages/{page_id}`.

  `params` may include `properties`, `icon`, `cover`, `in_trash`, `is_locked`,
  `template`, `erase_content`, `notifications`. The parent cannot be changed — use
  `move/3`.

  ## Options

    * `:filter_properties` — list of property names/IDs limiting returned properties.
  """
  @spec update(Client.t(), String.t(), map(), keyword()) ::
          {:ok, map()} | {:error, Noizu.Notion.Error.t()}
  def update(client, page_id, params, opts \\ []) when is_map(params) and is_list(opts) do
    Request.perform(client, :patch, "/v1/pages/" <> Request.encode_segment(page_id),
      json: params,
      params: filter_properties_params(opts)
    )
  end

  @doc """
  Trashes (default) or restores a page via `in_trash` on the update endpoint.
  The API has no permanent page deletion.
  """
  @spec trash(Client.t(), String.t(), boolean()) ::
          {:ok, map()} | {:error, Noizu.Notion.Error.t()}
  def trash(client, page_id, in_trash \\ true) when is_boolean(in_trash) do
    update(client, page_id, %{"in_trash" => in_trash})
  end

  @doc """
  Moves an ordinary page. `POST /v1/pages/{page_id}/move`.

  `parent` is one of `%{"type" => "page_id", "page_id" => id}` or
  `%{"type" => "data_source_id", "data_source_id" => id}` (data-source parents must use
  the data source ID, not the database ID).
  """
  @spec move(Client.t(), String.t(), map()) :: {:ok, map()} | {:error, Noizu.Notion.Error.t()}
  def move(client, page_id, parent) when is_map(parent) do
    Request.perform(client, :post, "/v1/pages/" <> Request.encode_segment(page_id) <> "/move",
      json: %{"parent" => parent}
    )
  end

  @doc """
  Retrieves one page property. `GET /v1/pages/{page_id}/properties/{property_id}`.

  `property_id` may be the property ID or its URL-encoded name. Most types return a
  single `property_item` map; `title`, `rich_text`, `people`, `relation` and rollups
  return a paginated `object: "list"` envelope.

  ## Options

    * `:start_cursor` / `:page_size` — pagination for list-valued properties.
  """
  @spec property(Client.t(), String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, Noizu.Notion.Error.t()}
  def property(client, page_id, property_id, opts \\ [])
      when is_binary(page_id) and is_binary(property_id) do
    path =
      "/v1/pages/" <>
        Request.encode_segment(page_id) <>
        "/properties/" <>
        Request.encode_segment(property_id)

    Request.perform(client, :get, path, params: Pagination.with_cursor(opts, opts[:start_cursor]))
  end

  @doc """
  Streams `results` of a paginated page property (`title`, `rich_text`, `people`,
  `relation`, rollup). Raises a `Noizu.Notion.Error` if a page fetch fails.
  """
  @spec property_stream(Client.t(), String.t(), String.t(), keyword()) ::
          Enumerable.t(map())
  def property_stream(client, page_id, property_id, opts \\ []) do
    path =
      "/v1/pages/" <>
        Request.encode_segment(page_id) <>
        "/properties/" <>
        Request.encode_segment(property_id)

    Pagination.stream(fn cursor ->
      Request.perform(client, :get, path, params: Pagination.with_cursor(opts, cursor))
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
