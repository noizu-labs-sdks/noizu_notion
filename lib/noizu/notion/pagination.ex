defmodule Noizu.Notion.Pagination do
  @moduledoc false

  # Lazy cursor walker behind every `*_stream/2..4` helper. Wraps Stream.resource/3:
  # emits one element per entry of `results`, fetching the next page only when the
  # consumer pulls. Stops when `has_more` is false or `next_cursor` is absent.
  #
  # A failed page fetch raises the %Noizu.Notion.Error{} (an enumerable may not
  # return an error value mid-stream); rescue at the enumeration site if desired.

  alias Noizu.Notion.Error

  @spec stream((String.t() | nil -> {:ok, map()} | {:error, Error.t()}), keyword()) ::
          Enumerable.t(map())
  def stream(fetch, opts \\ []) when is_function(fetch, 1) do
    results_key = Keyword.get(opts, :results_key, "results")

    Stream.resource(
      fn -> nil end,
      fn
        :done ->
          {:halt, nil}

        cursor ->
          case fetch.(cursor) do
            {:ok, %{"has_more" => has_more} = page} ->
              results = Map.get(page, results_key, [])
              {results, next_state(page, has_more)}

            {:ok, other} ->
              raise ArgumentError,
                    "expected a paginated list envelope (object:\"list\"), got " <>
                      inspect_shape(other)

            {:error, %Error{} = error} ->
              raise error

            {:error, other} ->
              raise ArgumentError, "unexpected fetch failure: #{inspect_shape(other)}"
          end
      end,
      fn _ -> :ok end
    )
  end

  # Adds (or removes) `start_cursor` on a keyword-opts call (GET endpoints).
  @spec with_cursor(keyword(), String.t() | nil) :: keyword()
  def with_cursor(opts, cursor) do
    opts = Keyword.delete(opts, :start_cursor)

    if is_binary(cursor) and cursor != "" do
      Keyword.put(opts, :start_cursor, cursor)
    else
      opts
    end
  end

  # Adds (or removes) `start_cursor` in a JSON body (POST endpoints: query, search).
  @spec with_cursor_in_body(map(), String.t() | nil) :: map()
  def with_cursor_in_body(body, cursor) do
    body = Map.delete(body, "start_cursor")

    if is_binary(cursor) and cursor != "" do
      Map.put(body, "start_cursor", cursor)
    else
      body
    end
  end

  defp next_state(page, true) do
    case page["next_cursor"] do
      cursor when is_binary(cursor) and cursor != "" -> cursor
      _ -> :done
    end
  end

  defp next_state(_page, _), do: :done

  # T-005: failure messages describe the shape of an unexpected response, never its
  # content — five inspect terms of a Notion body can name workspace content, and a
  # raised message tends to land in host logs. Kind + size only.
  defp inspect_shape(term) when is_map(term),
    do: "a map with #{plural(map_size(term), "key")}"

  defp inspect_shape(term) when is_binary(term),
    do: "a string of #{plural(byte_size(term), "byte")}"

  defp inspect_shape(term) when is_list(term),
    do: "a list of #{plural(length(term), "item")}"

  defp inspect_shape(term) when is_number(term), do: "a number"
  defp inspect_shape(nil), do: "nil"
  defp inspect_shape(term) when is_atom(term), do: "an atom"
  defp inspect_shape(_term), do: "an opaque term"

  defp plural(n, singular), do: "#{n} #{singular}#{if n == 1, do: "", else: "s"}"
end
