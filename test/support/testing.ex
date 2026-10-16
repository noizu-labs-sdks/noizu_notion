defmodule Noizu.Notion.Testing do
  @moduledoc false

  # Shared helpers for Req.Test-plug-stubbed tests. No network, no real tokens.

  alias Noizu.Notion.Client

  @doc "Client wired to a bare-function plug; no live network."
  def client(plug, extra \\ []) when is_function(plug, 1) and is_list(extra) do
    Client.new(Keyword.merge([token: "test-token", req_options: [plug: plug]], extra))
  end

  def body_params(%Plug.Conn{} = conn) do
    {:ok, raw, _conn} = Plug.Conn.read_body(conn)
    if raw == "", do: %{}, else: Jason.decode!(raw)
  end

  def query_params(conn), do: URI.decode_query(conn.query_string)

  def header(conn, name) do
    case List.keyfind(conn.req_headers, name, 0) do
      {^name, value} -> value
      nil -> nil
    end
  end

  @doc "Notion list-envelope fixture."
  def list_page(results, opts \\ []) do
    page = %{
      "object" => "list",
      "results" => results,
      "has_more" => Keyword.get(opts, :has_more, false),
      "next_cursor" => Keyword.get(opts, :next_cursor),
      "type" => Keyword.get(opts, :type, "page")
    }

    case Keyword.get(opts, :type, "page") do
      nil -> Map.delete(page, "type")
      type -> Map.put(page, type, %{})
    end
  end

  @doc "Notion error-envelope fixture."
  def error_body(status, code, message) do
    %{
      "object" => "error",
      "status" => status,
      "code" => code,
      "message" => message,
      "request_id" => "req-abc-123"
    }
  end

  def respond_json(conn, status \\ 200, data \\ %{}) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.resp(status, Jason.encode!(data))
  end
end
