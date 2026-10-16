defmodule Noizu.Notion.PaginationTest do
  use ExUnit.Case, async: true

  import Noizu.Notion.Testing

  alias Noizu.Notion.{DataSources, Error, Pagination}

  describe "stream/2" do
    test "walks cursors until has_more is false" do
      fetch = fn
        nil -> {:ok, list_page([%{"i" => 1}], has_more: true, next_cursor: "c2")}
        "c2" -> {:ok, list_page([%{"i" => 2}], has_more: true, next_cursor: "c3")}
        "c3" -> {:ok, list_page([%{"i" => 3}], has_more: false)}
      end

      assert [%{"i" => 1}, %{"i" => 2}, %{"i" => 3}] =
               Pagination.stream(fetch) |> Enum.to_list()
    end

    test "stops when has_more is true but the cursor is missing" do
      fetch = fn nil -> {:ok, list_page([%{"i" => 1}], has_more: true, next_cursor: nil)} end

      assert [%{"i" => 1}] = Pagination.stream(fetch) |> Enum.to_list()
    end

    test "raises the %Error{} when a page fetch fails mid-stream" do
      fetch = fn
        nil ->
          {:ok, list_page([%{"i" => 1}], has_more: true, next_cursor: "c2")}

        "c2" ->
          {:error, Error.exception(status: 500, code: :internal_server_error, message: "boom")}
      end

      assert_raise Error, ~r/status=500/, fn ->
        fetch |> Pagination.stream() |> Enum.to_list()
      end
    end

    test "results_key reads a non-standard envelope (data source templates)" do
      fetch = fn nil ->
        {:ok, %{"templates" => [%{"id" => "t1"}], "has_more" => false, "next_cursor" => nil}}
      end

      assert [%{"id" => "t1"}] =
               fetch |> Pagination.stream(results_key: "templates") |> Enum.to_list()
    end
  end

  describe "failure messages describe shape, not content (T-005)" do
    test "non-envelope bodies render as a shape description" do
      fetch = fn nil -> {:ok, %{"secret" => "top secret workspace page title"}} end

      error =
        assert_raise ArgumentError, fn ->
          fetch |> Pagination.stream() |> Enum.to_list()
        end

      message = Exception.message(error)
      assert message =~ "expected a paginated list envelope"
      assert message =~ "a map with 1 key"
      refute message =~ "top secret"
      refute message =~ "workspace"
    end

    test "unexpected fetch failures render as a shape description" do
      raw = "raw transport failure mentioning secret_token_value"
      fetch = fn nil -> {:error, raw} end

      error =
        assert_raise ArgumentError, fn ->
          fetch |> Pagination.stream() |> Enum.to_list()
        end

      message = Exception.message(error)
      assert message =~ "unexpected fetch failure"
      assert message =~ "a string of #{byte_size(raw)} bytes"
      refute message =~ "secret_token_value"
    end
  end

  test "with_cursor/2 and with_cursor_in_body/2 manage start_cursor" do
    assert Pagination.with_cursor([page_size: 10], "c1") == [start_cursor: "c1", page_size: 10]
    assert Pagination.with_cursor([start_cursor: "old"], nil) == []
    assert Pagination.with_cursor([], "") == []

    assert Pagination.with_cursor_in_body(%{"query" => "x"}, "c1") == %{
             "query" => "x",
             "start_cursor" => "c1"
           }

    assert Pagination.with_cursor_in_body(%{"start_cursor" => "old"}, nil) == %{}
  end

  test "list_templates_stream walks the templates key across pages" do
    test_pid = self()

    plug = fn conn ->
      params = query_params(conn)
      send(test_pid, {:call, params})

      case params do
        %{"start_cursor" => "t2"} ->
          respond_json(conn, 200, %{
            "templates" => [%{"id" => "t2"}],
            "has_more" => false,
            "next_cursor" => nil
          })

        _ ->
          respond_json(conn, 200, %{
            "templates" => [%{"id" => "t1"}],
            "has_more" => true,
            "next_cursor" => "t2"
          })
      end
    end

    templates =
      client(plug)
      |> DataSources.list_templates_stream("ds1")
      |> Enum.to_list()

    assert [%{"id" => "t1"}, %{"id" => "t2"}] = templates
  end
end
