defmodule Noizu.Notion.Comments do
  @moduledoc """
  Comment operations — create, list by block/page, retrieve, update, delete.

  Creation needs exactly one anchor (`parent.page_id`, `parent.block_id`, or
  `discussion_id` for a reply) and exactly one content field (`rich_text` or
  `markdown`). Updates and deletes are limited to comments the connection created;
  touching someone else's returns 404.
  """

  alias Noizu.Notion.{Client, Pagination, Request}

  @doc """
  Creates a comment. `POST /v1/comments`.

  `params`: exactly one of `parent` (`page_id`/`block_id`) or `discussion_id`; exactly
  one of `rich_text` (max 100 items) or `markdown` (+ optional `markdown_version`);
  optional `attachments` (max 3 `%{"type" => "file_upload", "file_upload_id" => id}`),
  `display_name`.
  """
  @spec create(Client.t(), map()) :: {:ok, map()} | {:error, Noizu.Notion.Error.t()}
  def create(client, params) when is_map(params) do
    Request.perform(client, :post, "/v1/comments", json: params)
  end

  @doc """
  Lists unresolved comments on a page or block. `GET /v1/comments`.

  ## Options

    * `:start_cursor`, `:page_size`.
  """
  @spec list(Client.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, Noizu.Notion.Error.t()}
  def list(client, block_id, opts \\ []) when is_binary(block_id) and is_list(opts) do
    opts = Keyword.put_new(opts, :block_id, block_id)

    Request.perform(client, :get, "/v1/comments",
      params: Pagination.with_cursor(opts, opts[:start_cursor])
    )
  end

  @doc """
  Streams comments across pages. Raises a `Noizu.Notion.Error` if a page fetch fails.
  """
  @spec list_stream(Client.t(), String.t(), keyword()) :: Enumerable.t(map())
  def list_stream(client, block_id, opts \\ []) when is_binary(block_id) and is_list(opts) do
    Pagination.stream(fn cursor ->
      list(client, block_id, Pagination.with_cursor(opts, cursor))
    end)
  end

  @doc "Retrieves a single comment. `GET /v1/comments/{comment_id}`."
  @spec retrieve(Client.t(), String.t()) :: {:ok, map()} | {:error, Noizu.Notion.Error.t()}
  def retrieve(client, comment_id) when is_binary(comment_id) do
    Request.perform(client, :get, "/v1/comments/" <> Request.encode_segment(comment_id))
  end

  @doc """
  Updates a comment's content (own comments only). `PATCH /v1/comments/{comment_id}`.

  `params`: exactly one of `rich_text` or `markdown` (+ optional `markdown_version`).
  """
  @spec update(Client.t(), String.t(), map()) :: {:ok, map()} | {:error, Noizu.Notion.Error.t()}
  def update(client, comment_id, params) when is_binary(comment_id) and is_map(params) do
    Request.perform(client, :patch, "/v1/comments/" <> Request.encode_segment(comment_id),
      json: params
    )
  end

  @doc "Deletes a comment (own comments only, no body). `DELETE /v1/comments/{comment_id}`."
  @spec delete(Client.t(), String.t()) :: {:ok, map()} | {:error, Noizu.Notion.Error.t()}
  def delete(client, comment_id) when is_binary(comment_id) do
    Request.perform(client, :delete, "/v1/comments/" <> Request.encode_segment(comment_id))
  end
end
