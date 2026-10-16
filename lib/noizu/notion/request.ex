defmodule Noizu.Notion.Request do
  @moduledoc false

  # Internal request engine: builds the Req call (auth + version headers), performs
  # it, decodes the response, applies the bounded retry policy, and normalizes
  # failures to %Noizu.Notion.Error{}.

  alias Noizu.Notion.{Client, Error}

  @idempotent [:get, :head, :delete]
  @default_max_attempts 3
  @default_backoff_ms 500

  @type method :: :get | :post | :patch | :delete | :head

  @doc """
  Performs one API call.

  Options:

    * `:json` — JSON-encodable request body.
    * `:form_multipart` — multipart form fields (Req `form_multipart` shape); used by
      the file-upload send endpoint.
    * `:params` — query params; a list value (`{:filter_properties, [...]}`) is
      expanded to repeated `filter_properties=<v>` keys.
    * `:headers` — extra request headers.

  Returns `{:ok, decoded_map}` for 2xx or `{:error, %Noizu.Notion.Error{}}`.
  """
  @spec perform(Client.t(), method(), String.t(), keyword()) ::
          {:ok, map()} | {:error, Error.t()}
  def perform(%Client{} = client, method, path, opts \\ [])
      when method in [:get, :post, :patch, :delete, :head] and is_binary(path) do
    with {:ok, token} <- ensure_token(client) do
      headers =
        [
          {"authorization", "Bearer " <> token},
          {"notion-version", client.version}
        ] ++
          case Keyword.get(opts, :headers) do
            nil -> []
            extra when is_list(extra) -> extra
          end

      base =
        [
          base_url: client.base_url,
          method: method,
          url: path,
          headers: headers,
          # This library owns retry policy; Req's built-in retry must stay off.
          retry: false
        ]

      base =
        cond do
          json = Keyword.get(opts, :json) -> Keyword.put(base, :json, json)
          form = Keyword.get(opts, :form_multipart) -> Keyword.put(base, :form_multipart, form)
          true -> base
        end

      base =
        case Keyword.get(opts, :params) do
          nil -> base
          params when is_list(params) -> Keyword.put(base, :params, expand_params(params))
        end

      request_opts = base ++ client.req_options
      max_attempts = max_attempts(client)

      do_request(request_opts, method, client, 1, max_attempts)
    end
  end

  @doc "Percent-encodes one path segment (IDs, property names)."
  @spec encode_segment(term()) :: String.t()
  def encode_segment(segment) when is_binary(segment) do
    URI.encode(segment, &URI.char_unreserved?/1)
  end

  defp do_request(request_opts, method, client, attempt, max_attempts) do
    case Req.request(request_opts) do
      {:ok, %Req.Response{} = resp} ->
        handle_response(resp, method, client, request_opts, attempt, max_attempts)

      {:error, exception} ->
        {:error, Error.from_exception(exception)}
    end
  end

  defp handle_response(
         %Req.Response{} = resp,
         method,
         client,
         request_opts,
         attempt,
         max_attempts
       ) do
    status = resp.status
    body = decode_body(resp.body)

    cond do
      status in 200..299 ->
        {:ok, body}

      true ->
        error = Error.from_response(status, body)
        maybe_retry(error, resp.headers, method, client, request_opts, attempt, max_attempts)
    end
  end

  defp maybe_retry(%Error{} = error, resp_headers, method, client, request_opts, attempt, max) do
    retryable? =
      Error.retryable?(error, idempotent: method in @idempotent)

    if attempt < max and retryable? do
      Process.sleep(retry_delay_ms(error, resp_headers, client, attempt))
      do_request(request_opts, method, client, attempt + 1, max)
    else
      {:error, error}
    end
  end

  defp retry_delay_ms(%Error{} = error, headers, client, attempt) do
    case Error.retry_after_ms(error, headers) do
      nil ->
        base = Keyword.get(client.retry || [], :base_backoff_ms, @default_backoff_ms)
        base * attempt

      ms when is_integer(ms) and ms >= 0 ->
        ms
    end
  end

  defp max_attempts(client),
    do: Keyword.get(client.retry || [], :max_attempts, @default_max_attempts)

  defp decode_body(body) when is_map(body), do: body
  defp decode_body(body) when body in [nil, ""], do: %{}

  defp decode_body(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} when is_map(decoded) -> decoded
      _ -> body
    end
  end

  defp decode_body(other), do: other

  defp expand_params(params) do
    Enum.flat_map(params, fn
      {k, values} when is_list(values) -> Enum.map(values, &{k, &1})
      {k, v} -> [{k, v}]
    end)
  end

  defp ensure_token(%Client{token: token}) when is_binary(token) and byte_size(token) > 0 do
    {:ok, token}
  end

  defp ensure_token(_client) do
    {:error,
     Error.exception(
       status: 401,
       code: :unauthorized,
       message: "no bearer token configured on Noizu.Notion.Client"
     )}
  end
end
