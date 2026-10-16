defmodule Noizu.Notion.Users do
  @moduledoc """
  User operations — list workspace users, retrieve one, and the token's bot user.

  Guests are excluded from listings and order is not guaranteed; personal access tokens
  cannot list workspace users.
  """

  alias Noizu.Notion.{Client, Pagination, Request}

  @doc """
  Lists users. `GET /v1/users`.

  ## Options

    * `:start_cursor`, `:page_size`.
  """
  @spec list(Client.t(), keyword()) :: {:ok, map()} | {:error, Noizu.Notion.Error.t()}
  def list(client, opts \\ []) when is_list(opts) do
    Request.perform(client, :get, "/v1/users",
      params: Pagination.with_cursor(opts, opts[:start_cursor])
    )
  end

  @doc """
  Streams all users across pages. Raises a `Noizu.Notion.Error` if a page fetch fails.
  """
  @spec list_stream(Client.t(), keyword()) :: Enumerable.t(map())
  def list_stream(client, opts \\ []) when is_list(opts) do
    Pagination.stream(fn cursor ->
      list(client, Pagination.with_cursor(opts, cursor))
    end)
  end

  @doc "Retrieves a user by ID. `GET /v1/users/{user_id}`."
  @spec retrieve(Client.t(), String.t()) :: {:ok, map()} | {:error, Noizu.Notion.Error.t()}
  def retrieve(client, user_id) when is_binary(user_id) do
    Request.perform(client, :get, "/v1/users/" <> Request.encode_segment(user_id))
  end

  @doc "Retrieves the bot user bound to the token. `GET /v1/users/me`."
  @spec me(Client.t()) :: {:ok, map()} | {:error, Noizu.Notion.Error.t()}
  def me(client) do
    Request.perform(client, :get, "/v1/users/me")
  end
end
