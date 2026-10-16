defmodule Noizu.NotionTest do
  use ExUnit.Case, async: true

  import Noizu.Notion.Testing

  alias Noizu.Notion

  alias Noizu.Notion.{
    Blocks,
    Comments,
    Databases,
    DataSources,
    Error,
    FileUploads,
    Pages,
    Search,
    Users
  }

  describe "Client" do
    test "defaults pin the current Notion-Version and API base" do
      client = Notion.new([])
      assert client.version == "2026-03-11"
      assert client.base_url == "https://api.notion.com"
      assert client.token == nil
      assert Noizu.Notion.Client.api_version() == "2026-03-11"
    end

    test "opts override app env, app env fills gaps" do
      Application.put_env(:noizu_notion, :client, token: "env-token", version: "2020-01-01")

      assert Notion.new([]).token == "env-token"
      assert Notion.new([]).version == "2020-01-01"
      assert Notion.new(version: "2026-03-11").version == "2026-03-11"

      Application.delete_env(:noizu_notion, :client)
      assert Notion.new([]).version == "2026-03-11"
    end
  end

  describe "auth headers" do
    test "sends bearer token and Notion-Version on every request" do
      plug = fn conn ->
        assert header(conn, "authorization") == "Bearer test-token"
        assert header(conn, "notion-version") == "2026-03-11"
        respond_json(conn, 200, %{"object" => "user", "id" => "bot-1"})
      end

      assert {:ok, %{"id" => "bot-1"}} = Users.me(client(plug))
    end

    test "missing token fails fast without hitting the network" do
      test_pid = self()

      plug = fn conn ->
        send(test_pid, :reached_network)
        respond_json(conn, 200, %{"object" => "user", "id" => "bot-1"})
      end

      empty = Noizu.Notion.Client.new(req_options: [plug: plug])

      assert {:error, %Error{status: 401, code: :unauthorized}} = Users.me(empty)
      refute_received :reached_network
    end
  end

  describe "pages" do
    test "create posts the body and honors filter_properties" do
      test_pid = self()

      plug = fn conn ->
        send(
          test_pid,
          {:call, String.downcase(conn.method), conn.request_path, body_params(conn),
           conn.query_string}
        )

        respond_json(conn, 200, %{"object" => "page", "id" => "p1"})
      end

      params = %{
        "parent" => %{"data_source_id" => "ds1"},
        "properties" => %{"Name" => %{"title" => [%{"text" => %{"content" => "Hi"}}]}}
      }

      assert {:ok, %{"id" => "p1"}} =
               Pages.create(client(plug), params, filter_properties: ["Name"])

      assert_received {:call, "post", "/v1/pages", ^params, "filter_properties=Name"}
    end

    test "retrieve expands repeated filter_properties" do
      test_pid = self()

      plug = fn conn ->
        send(
          test_pid,
          {:call, String.downcase(conn.method), conn.request_path, conn.query_string}
        )

        respond_json(conn, 200, %{"object" => "page", "id" => "p1"})
      end

      assert {:ok, _} =
               Pages.retrieve(client(plug), "p1", filter_properties: ["title", "Status"])

      assert_received {:call, "get", "/v1/pages/p1",
                       "filter_properties=title&filter_properties=Status"}
    end

    test "update, trash, and move" do
      test_pid = self()

      plug = fn conn ->
        send(
          test_pid,
          {:call, String.downcase(conn.method), conn.request_path, body_params(conn)}
        )

        respond_json(conn, 200, %{"object" => "page", "id" => "p1"})
      end

      cl = client(plug)

      assert {:ok, _} =
               Pages.update(cl, "p1", %{"properties" => %{"A" => %{"rich_text" => []}}})

      assert_received {:call, "patch", "/v1/pages/p1", %{"properties" => %{"A" => _}}}

      assert {:ok, _} = Pages.trash(cl, "p1")
      assert_received {:call, "patch", "/v1/pages/p1", %{"in_trash" => true}}

      parent = %{"type" => "data_source_id", "data_source_id" => "ds9"}
      assert {:ok, _} = Pages.move(cl, "p1", parent)
      assert_received {:call, "post", "/v1/pages/p1/move", %{"parent" => ^parent}}
    end

    test "property returns the item and property_stream walks pages" do
      test_pid = self()

      plug = fn conn ->
        params = query_params(conn)
        send(test_pid, {:call, conn.request_path, params})

        case params do
          %{"start_cursor" => "c2"} ->
            respond_json(
              conn,
              200,
              list_page([%{"id" => "r2"}], has_more: false, type: "property_item")
            )

          _ ->
            respond_json(
              conn,
              200,
              list_page([%{"id" => "r1"}],
                has_more: true,
                next_cursor: "c2",
                type: "property_item"
              )
            )
        end
      end

      cl = client(plug)

      assert {:ok, %{"object" => "list"}} = Pages.property(cl, "p1", "Name")
      assert_received {:call, "/v1/pages/p1/properties/Name", %{}}

      items =
        cl
        |> Pages.property_stream("p1", "Name")
        |> Enum.to_list()

      assert [%{"id" => "r1"}, %{"id" => "r2"}] = items
      assert_received {:call, "/v1/pages/p1/properties/Name", %{"start_cursor" => "c2"}}
    end
  end

  describe "databases and data sources" do
    test "database create/retrieve/update hit /v1/databases" do
      test_pid = self()

      plug = fn conn ->
        send(
          test_pid,
          {:call, String.downcase(conn.method), conn.request_path, body_params(conn)}
        )

        respond_json(conn, 200, %{
          "object" => "database",
          "id" => "db1",
          "data_sources" => [%{"id" => "ds1", "name" => "Table"}]
        })
      end

      cl = client(plug)

      assert {:ok, %{"data_sources" => [%{"id" => "ds1"}]}} =
               Databases.create(cl, %{
                 "parent" => %{"page_id" => "p1"},
                 "initial_data_source" => %{"properties" => %{"Name" => %{"title" => %{}}}}
               })

      assert_received {:call, "post", "/v1/databases", %{"parent" => %{"page_id" => "p1"}}}

      assert {:ok, _} = Databases.retrieve(cl, "db1")
      assert_received {:call, "get", "/v1/databases/db1", %{}}

      assert {:ok, _} = Databases.update(cl, "db1", %{"title" => []})
      assert_received {:call, "patch", "/v1/databases/db1", %{"title" => []}}
    end

    test "data source query posts filter/sorts and the stream walks cursors in the body" do
      test_pid = self()

      plug = fn conn ->
        body = body_params(conn)
        send(test_pid, {:call, conn.request_path, body})

        case body do
          %{"start_cursor" => "c2"} ->
            respond_json(conn, 200, list_page([%{"id" => "row2"}], has_more: false))

          _ ->
            respond_json(
              conn,
              200,
              list_page([%{"id" => "row1"}], has_more: true, next_cursor: "c2")
            )
        end
      end

      cl = client(plug)
      params = %{"filter" => %{"property" => "Done", "checkbox" => %{"equals" => true}}}

      assert {:ok, %{"object" => "list", "results" => [%{"id" => "row1"}]}} =
               DataSources.query(cl, "ds1", params)

      assert_received {:call, "/v1/data_sources/ds1/query", ^params}

      rows =
        cl
        |> DataSources.query_stream("ds1", params)
        |> Enum.to_list()

      assert [%{"id" => "row1"}, %{"id" => "row2"}] = rows

      assert_received {:call, "/v1/data_sources/ds1/query",
                       %{"start_cursor" => "c2", "filter" => %{"property" => "Done"}}}
    end

    test "data source retrieve/update/create and templates (non-standard envelope)" do
      test_pid = self()

      plug = fn conn ->
        send(
          test_pid,
          {:call, String.downcase(conn.method), conn.request_path, body_params(conn)}
        )

        cond do
          String.ends_with?(conn.request_path, "/templates") ->
            respond_json(conn, 200, %{
              "templates" => [%{"id" => "t1", "name" => "Default", "is_default" => true}],
              "has_more" => false,
              "next_cursor" => nil
            })

          String.downcase(conn.method) == "post" ->
            respond_json(conn, 200, %{"object" => "data_source", "id" => "ds2"})

          true ->
            respond_json(conn, 200, %{
              "object" => "data_source",
              "id" => "ds1",
              "properties" => %{"Name" => %{"type" => "title"}}
            })
        end
      end

      cl = client(plug)

      assert {:ok, %{"properties" => %{"Name" => _}}} = DataSources.retrieve(cl, "ds1")
      assert_received {:call, "get", "/v1/data_sources/ds1", %{}}

      assert {:ok, _} = DataSources.update(cl, "ds1", %{"title" => []})
      assert_received {:call, "patch", "/v1/data_sources/ds1", %{"title" => []}}

      assert {:ok, _} =
               DataSources.create(cl, %{
                 "parent" => %{"database_id" => "db1"},
                 "properties" => %{"Name" => %{"title" => %{}}}
               })

      assert_received {:call, "post", "/v1/data_sources",
                       %{"parent" => %{"database_id" => "db1"}}}

      assert {:ok, %{"templates" => [%{"id" => "t1"}]}} = DataSources.list_templates(cl, "ds1")

      assert [%{"id" => "t1"}] =
               cl
               |> DataSources.list_templates_stream("ds1")
               |> Enum.to_list()
    end
  end

  describe "blocks" do
    test "retrieve, update, delete, restore" do
      test_pid = self()

      plug = fn conn ->
        send(
          test_pid,
          {:call, String.downcase(conn.method), conn.request_path, body_params(conn)}
        )

        respond_json(conn, 200, %{"object" => "block", "id" => "b1"})
      end

      cl = client(plug)

      assert {:ok, _} = Blocks.retrieve(cl, "b1")
      assert_received {:call, "get", "/v1/blocks/b1", %{}}

      assert {:ok, _} = Blocks.update(cl, "b1", %{"paragraph" => %{"rich_text" => []}})
      assert_received {:call, "patch", "/v1/blocks/b1", %{"paragraph" => _}}

      assert {:ok, _} = Blocks.delete(cl, "b1")
      assert_received {:call, "delete", "/v1/blocks/b1", %{}}

      assert {:ok, _} = Blocks.restore(cl, "b1")
      assert_received {:call, "patch", "/v1/blocks/b1", %{"in_trash" => false}}
    end

    test "children list + stream, append with the 2026 position object" do
      test_pid = self()

      plug = fn conn ->
        body = body_params(conn)
        send(test_pid, {:call, String.downcase(conn.method), conn.request_path, body})
        respond_json(conn, 200, list_page([%{"id" => "kid"}], type: "block"))
      end

      cl = client(plug)

      assert {:ok, %{"results" => [%{"id" => "kid"}]}} = Blocks.children(cl, "page1")
      assert_received {:call, "get", "/v1/blocks/page1/children", %{}}

      assert [%{"id" => "kid"}] =
               cl
               |> Blocks.children_stream("page1")
               |> Enum.to_list()

      assert {:ok, _} =
               Blocks.append_children(
                 cl,
                 "page1",
                 [%{"type" => "paragraph", "paragraph" => %{}}],
                 position: {:after_block, "b42"}
               )

      assert_received {:call, "patch", "/v1/blocks/page1/children",
                       %{
                         "children" => [%{"type" => "paragraph"}],
                         "position" => %{
                           "type" => "after_block",
                           "after_block" => %{"id" => "b42"}
                         }
                       }}

      assert {:ok, _} = Blocks.append_children(cl, "page1", [], position: :start)

      assert_received {:call, "patch", "/v1/blocks/page1/children",
                       %{"position" => %{"type" => "start"}}}
    end
  end

  describe "users" do
    test "list, retrieve, and stream across pages" do
      test_pid = self()

      plug = fn conn ->
        params = query_params(conn)
        send(test_pid, {:call, conn.request_path, params})

        cond do
          conn.request_path == "/v1/users/u9" ->
            respond_json(conn, 200, %{"object" => "user", "id" => "u9"})

          params == %{"start_cursor" => "u2"} ->
            respond_json(
              conn,
              200,
              list_page([%{"id" => "u2", "object" => "user"}], has_more: false, type: "user")
            )

          true ->
            respond_json(
              conn,
              200,
              list_page([%{"id" => "u1", "object" => "user"}],
                has_more: true,
                next_cursor: "u2",
                type: "user"
              )
            )
        end
      end

      cl = client(plug)

      assert {:ok, %{"results" => [%{"id" => "u1"}]}} = Users.list(cl)

      assert {:ok, %{"object" => "user"}} = Users.retrieve(cl, "u9")
      assert_received {:call, "/v1/users/u9", %{}}

      users =
        cl
        |> Users.list_stream()
        |> Enum.to_list()

      assert [%{"id" => "u1"}, %{"id" => "u2"}] = users
    end
  end

  describe "search" do
    test "posts the body and stream injects start_cursor" do
      test_pid = self()

      plug = fn conn ->
        body = body_params(conn)
        send(test_pid, {:call, body})

        case body do
          %{"start_cursor" => "s2"} ->
            respond_json(conn, 200, list_page([%{"id" => "r2"}], has_more: false))

          _ ->
            respond_json(
              conn,
              200,
              list_page([%{"id" => "r1"}], has_more: true, next_cursor: "s2")
            )
        end
      end

      cl = client(plug)
      params = %{"query" => "launch", "filter" => %{"property" => "object", "value" => "page"}}

      assert {:ok, %{"results" => [%{"id" => "r1"}]}} = Search.search(cl, params)

      assert [%{"id" => "r1"}, %{"id" => "r2"}] =
               cl
               |> Search.search_stream(params)
               |> Enum.to_list()

      assert_received {:call, ^params}
      assert_received {:call, ^params}
      assert_received {:call, %{"start_cursor" => "s2", "query" => "launch"}}
    end
  end

  describe "comments" do
    test "create/list/retrieve/update/delete" do
      test_pid = self()

      plug = fn conn ->
        send(
          test_pid,
          {:call, String.downcase(conn.method), conn.request_path, body_params(conn)}
        )

        if conn.request_path == "/v1/comments" do
          respond_json(
            conn,
            200,
            list_page([%{"object" => "comment", "id" => "c1"}], type: "comment")
          )
        else
          respond_json(conn, 200, %{"object" => "comment", "id" => "c1"})
        end
      end

      cl = client(plug)

      assert {:ok, _} =
               Comments.create(cl, %{
                 "parent" => %{"page_id" => "p1"},
                 "rich_text" => [%{"text" => %{"content" => "hi"}}]
               })

      assert_received {:call, "post", "/v1/comments", %{"parent" => %{"page_id" => "p1"}}}

      assert {:ok, _} = Comments.list(cl, "p1")
      assert_received {:call, "get", "/v1/comments", %{}}

      assert [%{"id" => "c1"}] =
               cl
               |> Comments.list_stream("p1")
               |> Enum.to_list()

      assert {:ok, _} = Comments.retrieve(cl, "c1")
      assert_received {:call, "get", "/v1/comments/c1", %{}}

      assert {:ok, _} = Comments.update(cl, "c1", %{"rich_text" => []})
      assert_received {:call, "patch", "/v1/comments/c1", %{"rich_text" => []}}

      assert {:ok, _} = Comments.delete(cl, "c1")
      assert_received {:call, "delete", "/v1/comments/c1", %{}}
    end
  end

  describe "file uploads" do
    test "create/send/complete/retrieve/list lifecycle" do
      test_pid = self()

      plug = fn conn ->
        send(
          test_pid,
          {:call, String.downcase(conn.method), conn.request_path, header(conn, "content-type")}
        )

        if conn.request_path == "/v1/file_uploads" do
          respond_json(
            conn,
            200,
            list_page([%{"object" => "file_upload", "id" => "fu1"}], type: "file_upload")
          )
        else
          respond_json(conn, 200, %{"object" => "file_upload", "id" => "fu1"})
        end
      end

      cl = client(plug)

      assert {:ok, _} =
               FileUploads.create(cl, %{
                 "mode" => "multi_part",
                 "filename" => "a.png",
                 "content_type" => "image/png",
                 "number_of_parts" => 2
               })

      assert_received {:call, "post", "/v1/file_uploads", "application/json"}

      assert {:ok, _} =
               FileUploads.send_file(cl, "fu1",
                 data: "BINARY-PART-1",
                 filename: "a.png",
                 content_type: "image/png",
                 part_number: 1
               )

      assert_received {:call, "post", "/v1/file_uploads/fu1/send", content_type}
      assert String.starts_with?(content_type, "multipart/form-data; boundary=")

      assert {:ok, _} = FileUploads.complete(cl, "fu1")
      assert_received {:call, "post", "/v1/file_uploads/fu1/complete", nil}

      assert {:ok, _} = FileUploads.retrieve(cl, "fu1")
      assert_received {:call, "get", "/v1/file_uploads/fu1", nil}

      assert {:ok, _} = FileUploads.list(cl, status: "pending")

      assert [%{"id" => "fu1"}] =
               cl
               |> FileUploads.list_stream()
               |> Enum.to_list()
    end
  end

  describe "filter_properties encoding" do
    test "list values encode as repeated keys, never brackets, exact query string" do
      test_pid = self()

      plug = fn conn ->
        send(test_pid, {:query, conn.request_path, conn.query_string})
        respond_json(conn, 200, list_page([], has_more: false))
      end

      cl = client(plug)

      assert {:ok, _} =
               DataSources.query(cl, "ds1", %{}, filter_properties: ["title", "Status"])

      assert_received {:query, "/v1/data_sources/ds1/query",
                       "filter_properties=title&filter_properties=Status"}

      assert {:ok, _} = Search.search(cl, %{}, filter_properties: ["title"])
      assert_received {:query, "/v1/search", "filter_properties=title"}

      assert {:ok, _} = Pages.retrieve(cl, "p1", filter_properties: ["title", "Status"])
      assert_received {:query, "/v1/pages/p1", "filter_properties=title&filter_properties=Status"}
    end
  end
end
