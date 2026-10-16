defmodule Noizu.Notion.Blocks do
  @moduledoc """
  Block operations — retrieve, update, trash/restore, list children, append children.

  Deletion is a soft delete (`in_trash: true`); restore through `restore/2` or
  `update/3`. The append endpoint takes the 2026-03-11 `position` object — the old
  `after` parameter no longer exists.
  """

  alias Noizu.Notion.{Client, Pagination, Request}

  @doc "Retrieves a block. `GET /v1/blocks/{block_id}`."
  @spec retrieve(Client.t(), String.t()) :: {:ok, map()} | {:error, Noizu.Notion.Error.t()}
  def retrieve(client, block_id) when is_binary(block_id) do
    Request.perform(client, :get, "/v1/blocks/" <> Request.encode_segment(block_id))
  end

  @doc """
  Updates a block's type content and/or trash state. `PATCH /v1/blocks/{block_id}`.

  `params` carries a key named after the block type (`paragraph`, `heading_1`, `to_do`,
  `code`, `callout`, `image`, `table_row`, ...) whose value holds the fields for that
  type, and/or `in_trash`. Fields are replaced in full; omitted fields are untouched.
  Children are not updatable here; `child_page`/`child_database` blocks must go through
  the page/database endpoints.
  """
  @spec update(Client.t(), String.t(), map()) :: {:ok, map()} | {:error, Noizu.Notion.Error.t()}
  def update(client, block_id, params) when is_binary(block_id) and is_map(params) do
    Request.perform(client, :patch, "/v1/blocks/" <> Request.encode_segment(block_id),
      json: params
    )
  end

  @doc "Restores a trashed block (`in_trash: false`)."
  @spec restore(Client.t(), String.t()) :: {:ok, map()} | {:error, Noizu.Notion.Error.t()}
  def restore(client, block_id), do: update(client, block_id, %{"in_trash" => false})

  @doc """
  Soft-deletes a block (moves it, including page blocks, to the trash).
  `DELETE /v1/blocks/{block_id}`.
  """
  @spec delete(Client.t(), String.t()) :: {:ok, map()} | {:error, Noizu.Notion.Error.t()}
  def delete(client, block_id) when is_binary(block_id) do
    Request.perform(client, :delete, "/v1/blocks/" <> Request.encode_segment(block_id))
  end

  @doc """
  Lists a block's first-level children. `GET /v1/blocks/{block_id}/children`.

  ## Options

    * `:start_cursor`, `:page_size`.
  """
  @spec children(Client.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, Noizu.Notion.Error.t()}
  def children(client, block_id, opts \\ []) when is_binary(block_id) and is_list(opts) do
    path = "/v1/blocks/" <> Request.encode_segment(block_id) <> "/children"

    Request.perform(client, :get, path, params: Pagination.with_cursor(opts, opts[:start_cursor]))
  end

  @doc """
  Streams a block's first-level children across pages. Raises a `Noizu.Notion.Error`
  if a page fetch fails; recurse via `has_children` for nested content.
  """
  @spec children_stream(Client.t(), String.t(), keyword()) :: Enumerable.t(map())
  def children_stream(client, block_id, opts \\ []) when is_binary(block_id) and is_list(opts) do
    path = "/v1/blocks/" <> Request.encode_segment(block_id) <> "/children"

    Pagination.stream(fn cursor ->
      Request.perform(client, :get, path, params: Pagination.with_cursor(opts, cursor))
    end)
  end

  @doc """
  Appends children to a block or page. `PATCH /v1/blocks/{block_id}/children`.

  `children` is a list of block objects (max 100, up to two nesting levels).

  ## Options

    * `:position` — `:end` (default), `:start`, or `{:after_block, block_id}`; sent as
      the 2026-03-11 `position` object (`{"type": "end" | "start"}` /
      `{"type": "after_block", "after_block": {"id": ...}}`). A `position` map with a
      `"type"` key is passed through verbatim.
    * `:notifications` — `%{"mode" => "default" | "silent"}`.
  """
  @spec append_children(Client.t(), String.t(), [map()], keyword()) ::
          {:ok, map()} | {:error, Noizu.Notion.Error.t()}
  def append_children(client, block_id, children, opts \\ [])
      when is_binary(block_id) and is_list(children) and is_list(opts) do
    path = "/v1/blocks/" <> Request.encode_segment(block_id) <> "/children"

    body =
      %{"children" => children, "position" => position(opts[:position] || :end)}
      |> maybe_put_notifications(opts)

    Request.perform(client, :patch, path, json: body)
  end

  defp position(%{"type" => _} = position), do: position
  defp position(:end), do: %{"type" => "end"}
  defp position(:start), do: %{"type" => "start"}

  defp position({:after_block, block_id}) when is_binary(block_id),
    do: %{"type" => "after_block", "after_block" => %{"id" => block_id}}

  defp maybe_put_notifications(body, opts) do
    case Keyword.get(opts, :notifications) do
      %{"mode" => _} = notifications -> Map.put(body, "notifications", notifications)
      _ -> body
    end
  end
end
