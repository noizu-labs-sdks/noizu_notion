defmodule Noizu.Notion.Error do
  @moduledoc """
  Error returned by every failing `Noizu.Notion` call as `{:error, %Noizu.Notion.Error{}}`.

  Mirrors the Notion error envelope — `{"object": "error", "status", "code", "message",
  "request_id", "additional_data"}`:

      %Noizu.Notion.Error{
        status: 404,
        code: :object_not_found,
        message: "Could not find page with ID: abcd-....",
        request_id: "e45f...",
        additional_data: nil
      }

  `:code` is an atom for every code documented by the pinned API version (see
  `known_codes/0`); unrecognized codes are kept verbatim as strings — the library never
  creates atoms from network data. Transport-level failures (connection refused, timeout)
  carry `status: nil` with `code: :request_failed`; a 2xx response whose body is not a
  Notion object maps to `code: :invalid_response`.

  The struct implements the `Exception` behaviour so a mid-stream pagination failure can
  raise it with a readable message.
  """

  # defexception declares the Exception behaviour; exception/1 and message/1 below
  # are the (overridden) callbacks.

  defexception [:status, :code, :message, :request_id, :additional_data]

  @type t :: %__MODULE__{
          status: pos_integer() | nil,
          code: atom() | String.t() | nil,
          message: String.t() | nil,
          request_id: String.t() | nil,
          additional_data: map() | nil
        }

  @known_codes ~w(
    invalid_json
    invalid_request_url
    invalid_request
    invalid_grant
    validation_error
    missing_version
    invalid_beta
    unauthorized
    restricted_resource
    object_not_found
    row_limit_exceeded
    conflict_error
    rate_limited
    internal_server_error
    bad_gateway
    service_unavailable
    database_connection_unavailable
    gateway_timeout
    service_overload
    public_api_request_blocked
  )a

  @doc "All error codes documented by Notion-Version 2026-03-11."
  @spec known_codes() :: [atom()]
  def known_codes, do: @known_codes

  @doc false
  @impl Exception
  @spec exception(keyword()) :: t()
  def exception(fields) when is_list(fields) do
    struct!(__MODULE__, fields)
  end

  @impl Exception
  @spec message(t()) :: String.t()
  def message(%__MODULE__{} = error) do
    status = error.status || "no-status"
    code = error.code || "no-code"
    request_id = if error.request_id, do: " [request_id: #{error.request_id}]", else: ""
    base = "notion_error status=#{status} code=#{code}#{request_id}"

    case error.message do
      nil -> base
      msg -> base <> ": " <> msg
    end
  end

  @doc """
  Builds an error from an HTTP status and the decoded response body.

  A body shaped as the Notion error envelope populates `status`/`code`/`message`/
  `request_id`/`additional_data`; anything else becomes `code: :invalid_response`.
  """
  @spec from_response(pos_integer(), term()) :: t()
  def from_response(status, %{"object" => "error"} = body) do
    %__MODULE__{
      status: body["status"] || status,
      code: normalize_code(body["code"]),
      message: body["message"],
      request_id: body["request_id"],
      additional_data: body["additional_data"]
    }
  end

  def from_response(status, body) do
    %__MODULE__{
      status: status,
      code: :invalid_response,
      message: "expected an object:\"error\" envelope, got a #{inspect_shape(body)} body"
    }
  end

  @doc "Wraps a transport-level exception (Req errors, timeouts, connectivity)."
  @spec from_exception(Exception.t()) :: t()
  def from_exception(%_{} = exception) do
    %__MODULE__{status: nil, code: :request_failed, message: Exception.message(exception)}
  end

  @doc """
  Server-documented retryability for this error under the client's retry policy.

  `429 rate_limited` and `529 service_overload` are always retryable (honor
  `Retry-After`). `502`/`503`/`504` are retryable **only for idempotent methods** —
  pass `idempotent: false` for writes. Everything else (including `409 conflict_error`,
  which requires refreshed parameters, and `500`, which Notion does not recommend
  retrying) returns `false`.
  """
  @spec retryable?(t(), keyword()) :: boolean()
  def retryable?(%__MODULE__{status: status}, opts \\ []) when is_list(opts) do
    idempotent = Keyword.get(opts, :idempotent, true)

    cond do
      status in [429, 529] -> true
      status in [502, 503, 504] and idempotent -> true
      true -> false
    end
  end

  @doc """
  How long to wait before retrying, in milliseconds: the `retry-after` response header
  (integer seconds) when present, else the body's `additional_data.retry_after`, else
  `nil` (the caller applies its own backoff).
  """
  @spec retry_after_ms(t(), %{optional(String.t()) => [String.t()]}) :: non_neg_integer() | nil
  def retry_after_ms(error, headers \\ %{})

  def retry_after_ms(%__MODULE__{} = error, headers) when is_map(headers) do
    case headers do
      %{"retry-after" => [seconds | _]} when is_binary(seconds) -> parse_seconds(seconds, error)
      _ -> body_retry_after(error)
    end
  end

  def retry_after_ms(%__MODULE__{} = error, _other), do: body_retry_after(error)

  defp parse_seconds(seconds, error) do
    case Integer.parse(seconds) do
      {n, _rest} when n >= 0 -> n * 1000
      _ -> body_retry_after(error)
    end
  end

  defp body_retry_after(%__MODULE__{additional_data: %{"retry_after" => n}}) when is_number(n),
    do: trunc(n * 1000)

  defp body_retry_after(_), do: nil

  defp normalize_code(code) when is_binary(code) do
    try do
      atom = String.to_existing_atom(code)
      if atom in @known_codes, do: atom, else: code
    rescue
      ArgumentError -> code
    end
  end

  defp normalize_code(code), do: code

  defp inspect_shape(body) when is_binary(body), do: "non-JSON (#{byte_size(body)} bytes)"
  defp inspect_shape(_), do: "non-error"
end
