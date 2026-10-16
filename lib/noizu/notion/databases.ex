defmodule Noizu.Notion.Databases do
  @moduledoc """
  Database container operations — create, retrieve, update.

  Since API version 2025-09-03 (carried into the pinned `#{Noizu.Notion.Client.api_version()}`), a database is a
  container over one or more **data sources** (the tables). The property schema lives on
  the data source (`Noizu.Notion.DataSources`), not here; `retrieve/2` returns the
  database's `data_sources` list with the IDs needed to query them.
  """

  alias Noizu.Notion.{Client, Request}

  @doc """
  Creates a database. `POST /v1/databases`.

  `params` is the request body: `parent` (a `page_id` parent or `workspace`), `title`,
  `description`, `icon`, `cover`, `is_inline`, and the initial schema under
  `initial_data_source.properties` (there is no top-level `properties` key), or
  `database_type` (`tasks` | `projects` | `skills`; mutually exclusive with
  `initial_data_source`). One call creates the database, its first data source, and its
  first table view.
  """
  @spec create(Client.t(), map()) :: {:ok, map()} | {:error, Noizu.Notion.Error.t()}
  def create(client, params) when is_map(params) do
    Request.perform(client, :post, "/v1/databases", json: params)
  end

  @doc "Retrieves a database container. `GET /v1/databases/{database_id}`."
  @spec retrieve(Client.t(), String.t()) :: {:ok, map()} | {:error, Noizu.Notion.Error.t()}
  def retrieve(client, database_id) when is_binary(database_id) do
    Request.perform(client, :get, "/v1/databases/" <> Request.encode_segment(database_id))
  end

  @doc """
  Updates a database container. `PATCH /v1/databases/{database_id}`.

  `params` may include `title`, `description`, `icon`, `cover`, `in_trash`, `parent`,
  `is_inline`, `is_locked`. Property-schema changes belong to `Noizu.Notion.DataSources.update/3`.
  """
  @spec update(Client.t(), String.t(), map()) :: {:ok, map()} | {:error, Noizu.Notion.Error.t()}
  def update(client, database_id, params) when is_binary(database_id) and is_map(params) do
    Request.perform(client, :patch, "/v1/databases/" <> Request.encode_segment(database_id),
      json: params
    )
  end
end
