defmodule Noizu.Notion.FileUploads do
  @moduledoc """
  File upload lifecycle — create, send contents, complete multi-part, retrieve, list.

  Flow: `create/2` -> `send_file/3` (once for `single_part`; N parts for `multi_part`)
  -> `complete/2` (multi-part only) -> attach by passing
  `%{"type" => "file_upload", "file_upload_id" => id}` as a file object on page, block,
  or database payloads while the upload's `status` is `"uploaded"` (before
  `expiry_time`).

  Modes: `single_part` (default), `multi_part` (files over 20 MiB, 1-10 000 parts),
  `external_url` (Notion imports from a temporary public HTTPS URL; no send step).
  """

  alias Noizu.Notion.{Client, Pagination, Request}

  @doc """
  Creates a file upload. `POST /v1/file_uploads`.

  `params`: `mode` (`single_part` default | `multi_part` | `external_url`), `filename`
  (max 900 bytes including extension), `content_type`, `number_of_parts` (multi-part),
  `external_url` (external_url mode).
  """
  @spec create(Client.t(), map()) :: {:ok, map()} | {:error, Noizu.Notion.Error.t()}
  def create(client, params) when is_map(params) do
    Request.perform(client, :post, "/v1/file_uploads", json: params)
  end

  @doc """
  Sends file contents. `POST /v1/file_uploads/{file_upload_id}/send`
  (`multipart/form-data`, `file` part — the only multipart endpoint in the API).

  ## Options

    * `:data` — (required) file contents as a binary.
    * `:filename` — part filename (default `"upload.bin"`).
    * `:content_type` — part MIME type (default `"application/octet-stream"`; must be
      consistent with the `content_type`/`filename` declared at creation).
    * `:part_number` — integer for multi-part uploads, sent as a form field.
  """
  @spec send_file(Client.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, Noizu.Notion.Error.t()}
  def send_file(client, file_upload_id, opts) when is_binary(file_upload_id) and is_list(opts) do
    data = Keyword.fetch!(opts, :data)

    fields =
      [
        {"file",
         {data,
          [
            filename: Keyword.get(opts, :filename, "upload.bin"),
            content_type: Keyword.get(opts, :content_type, "application/octet-stream")
          ]}}
      ] ++
        case Keyword.get(opts, :part_number) do
          nil ->
            []

          part_number when is_integer(part_number) ->
            [{"part_number", Integer.to_string(part_number)}]
        end

    path =
      "/v1/file_uploads/" <> Request.encode_segment(file_upload_id) <> "/send"

    Request.perform(client, :post, path, form_multipart: fields)
  end

  @doc "Finalizes a multi-part upload after all parts are sent. `POST .../complete` (no body)."
  @spec complete(Client.t(), String.t()) :: {:ok, map()} | {:error, Noizu.Notion.Error.t()}
  def complete(client, file_upload_id) when is_binary(file_upload_id) do
    path =
      "/v1/file_uploads/" <> Request.encode_segment(file_upload_id) <> "/complete"

    Request.perform(client, :post, path)
  end

  @doc "Retrieves a file upload object. `GET /v1/file_uploads/{file_upload_id}`."
  @spec retrieve(Client.t(), String.t()) :: {:ok, map()} | {:error, Noizu.Notion.Error.t()}
  def retrieve(client, file_upload_id) when is_binary(file_upload_id) do
    Request.perform(client, :get, "/v1/file_uploads/" <> Request.encode_segment(file_upload_id))
  end

  @doc """
  Lists file uploads, newest first. `GET /v1/file_uploads`.

  ## Options

    * `:status` — filter by `pending` | `uploaded` | `expired` | `failed`.
    * `:start_cursor`, `:page_size`.
  """
  @spec list(Client.t(), keyword()) :: {:ok, map()} | {:error, Noizu.Notion.Error.t()}
  def list(client, opts \\ []) when is_list(opts) do
    Request.perform(client, :get, "/v1/file_uploads",
      params: Pagination.with_cursor(opts, opts[:start_cursor])
    )
  end

  @doc "Streams file uploads across pages. Raises a `Noizu.Notion.Error` on a failed fetch."
  @spec list_stream(Client.t(), keyword()) :: Enumerable.t(map())
  def list_stream(client, opts \\ []) when is_list(opts) do
    Pagination.stream(fn cursor ->
      list(client, Pagination.with_cursor(opts, cursor))
    end)
  end
end
