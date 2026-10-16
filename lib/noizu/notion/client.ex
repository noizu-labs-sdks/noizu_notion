defmodule Noizu.Notion.Client do
  @api_version "2026-03-11"
  @default_base_url "https://api.notion.com"

  @moduledoc """
  Explicit connection configuration, passed as the first argument to every call.

  Nothing about the client is global: build one struct and hand it around.

      client = Noizu.Notion.Client.new(token: System.fetch_env!("NOTION_TOKEN"))
      {:ok, me} = Noizu.Notion.Users.me(client)

  `new/1` precedence: function options -> application env
  (`Application.get_env(:noizu_notion, :client)`, a keyword list) -> defaults.
  The app env is an optional convenience; the library never reads it anywhere else.

  ## Options

    * `:token` — bearer token (internal integration token, OAuth token, or personal
      access token). May be nil at construction, but is required at request time.
    * `:version` — value for the `Notion-Version` header. Default: `#{@api_version}`
      (the current latest per developers.notion.com).
    * `:base_url` — API root. Default: `"https://api.notion.com"`.
    * `:req_options` — keyword options merged into every underlying `Req.request/1`
      call (e.g. `plug:`, `receive_timeout:`, `user_agent:`). Escape hatch; the
      library's own options (method, url, auth headers) always take precedence.
    * `:retry` — keyword: `:max_attempts` (default `3`; `0` disables retrying) and
      `:base_backoff_ms` (default `500`; used when the server sends no `Retry-After`).
  """

  defstruct [:token, :version, :base_url, :req_options, :retry]

  @type t :: %__MODULE__{
          token: String.t() | nil,
          version: String.t(),
          base_url: String.t(),
          req_options: keyword(),
          retry: keyword()
        }

  @doc """
  Builds a client struct. See the module doc for option details.
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) when is_list(opts) do
    env = Application.get_env(:noizu_notion, :client) || []
    merged = Keyword.merge(env, opts)

    %__MODULE__{
      token: Keyword.get(merged, :token),
      version: Keyword.get(merged, :version, @api_version),
      base_url: Keyword.get(merged, :base_url, @default_base_url),
      req_options: Keyword.get(merged, :req_options, []),
      retry: Keyword.get(merged, :retry, [])
    }
  end

  @doc "The default `Notion-Version` header value this library is pinned to."
  @spec api_version() :: String.t()
  def api_version, do: @api_version
end
