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
                    "expected a paginated list envelope (object:\"list\"), got: " <>
                      inspect(other, limit: 5)

            {:error, %Error{} = error} ->
              raise error

            {:error, other} ->
              raise ArgumentError, "unexpected fetch failure: #{inspect(other, limit: 5)}"
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
end
