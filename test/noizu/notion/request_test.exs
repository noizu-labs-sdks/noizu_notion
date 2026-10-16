defmodule Noizu.Notion.RequestTest do
  use ExUnit.Case, async: true

  import Noizu.Notion.Testing

  alias Noizu.Notion.{DataSources, Error, Users}

  # The Req.Test plug runs in the test process, so the process dictionary safely
  # tracks per-test call counts and `send/2` reaches assert_received/2.

  describe "error decoding" do
    test "404 envelope decodes to %Error{} with request_id" do
      plug = fn conn ->
        respond_json(conn, 404, error_body(404, "object_not_found", "Could not find page."))
      end

      assert {:error, %Error{} = error} = Users.retrieve(client(plug), "missing")

      assert error.status == 404
      assert error.code == :object_not_found
      assert error.message == "Could not find page."
      assert error.request_id == "req-abc-123"
      assert Exception.message(error) =~ "code=object_not_found"
    end

    test "non-JSON error bodies become :invalid_response" do
      plug = fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("text/plain")
        |> Plug.Conn.resp(502, "Bad Gateway")
      end

      assert {:error, %Error{status: 502, code: :invalid_response}} = Users.me(client(plug))
    end
  end

  describe "429 retry honoring Retry-After" do
    test "retries with the header's delay and succeeds" do
      parent = self()

      plug = fn conn ->
        count = bump()

        if count == 1 do
          conn
          |> Plug.Conn.put_resp_header("retry-after", "0")
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(429, Jason.encode!(error_body(429, "rate_limited", "slow down")))
        else
          send(parent, {:retried, count})
          respond_json(conn, 200, %{"object" => "user", "id" => "u1"})
        end
      end

      assert {:ok, %{"id" => "u1"}} = Users.me(client(plug))
      assert_received {:retried, 2}
    end

    test "gives up after max_attempts and returns the error" do
      parent = self()

      plug = fn conn ->
        send(parent, :called)

        conn
        |> Plug.Conn.put_resp_header("retry-after", "0")
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(429, Jason.encode!(error_body(429, "rate_limited", "still slow")))
      end

      cl = client(plug, retry: [max_attempts: 2])

      assert {:error, %Error{code: :rate_limited, status: 429}} = Users.me(cl)
      assert_received :called
      assert_received :called
      refute_received :called
    end
  end

  describe "5xx retry policy" do
    test "retries idempotent GETs with backoff when no Retry-After" do
      parent = self()

      plug = fn conn ->
        if bump() == 1 do
          send(parent, :first)
          respond_json(conn, 503, error_body(503, "service_unavailable", "try later"))
        else
          send(parent, :second)
          respond_json(conn, 200, %{"object" => "user", "id" => "u1"})
        end
      end

      cl = client(plug, retry: [max_attempts: 3, base_backoff_ms: 1])

      assert {:ok, %{"id" => "u1"}} = Users.me(cl)
      assert_received :first
      assert_received :second
      refute_received :first
    end

    test "does not retry writes that return 5xx" do
      parent = self()

      plug = fn conn ->
        send(parent, :called)
        respond_json(conn, 503, error_body(503, "service_unavailable", "may have applied"))
      end

      cl = client(plug, retry: [max_attempts: 3, base_backoff_ms: 1])

      assert {:error, %Error{status: 503}} =
               DataSources.query(cl, "ds1", %{}, filter_properties: ["A"])

      assert_received :called
      refute_received :called
    end
  end

  describe "Retry-After clamping (T-002)" do
    test "clamps a huge Retry-After header to 30s, sleep function injectable" do
      parent = self()

      plug = fn conn ->
        if bump() == 1 do
          conn
          |> Plug.Conn.put_resp_header("retry-after", "2000000000")
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(429, Jason.encode!(error_body(429, "rate_limited", "slow down")))
        else
          send(parent, :retried)
          respond_json(conn, 200, %{"object" => "user", "id" => "u1"})
        end
      end

      cl =
        client(plug,
          retry: [
            max_attempts: 2,
            sleep_fn: fn ms -> send(parent, {:slept, ms}) end
          ]
        )

      assert {:ok, %{"id" => "u1"}} = Users.me(cl)
      assert_received {:slept, 30_000}
      assert_received :retried
    end

    test "negative and non-numeric Retry-After headers fall back to the backoff" do
      for header <- ["-5", "soon"] do
        Process.put(:call_count, 0)
        parent = self()

        plug = fn conn ->
          if bump() == 1 do
            conn
            |> Plug.Conn.put_resp_header("retry-after", header)
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.resp(429, Jason.encode!(error_body(429, "rate_limited", "slow down")))
          else
            send(parent, :retried)
            respond_json(conn, 200, %{"object" => "user", "id" => "u1"})
          end
        end

        cl =
          client(plug,
            retry: [
              max_attempts: 2,
              base_backoff_ms: 7,
              sleep_fn: fn ms -> send(parent, {:slept, ms}) end
            ]
          )

        assert {:ok, %{"id" => "u1"}} = Users.me(cl)
        assert_received {:slept, 7}
        assert_received :retried
      end
    end

    test "clamps additional_data.retry_after; negative values use the backoff" do
      parent = self()

      plug = fn conn ->
        count = bump()

        if count == 1 do
          respond_json(conn, 429, %{
            "object" => "error",
            "status" => 429,
            "code" => "rate_limited",
            "message" => "slow down",
            "additional_data" => %{"retry_after" => 86_400}
          })
        else
          send(parent, :retried)
          respond_json(conn, 200, %{"object" => "user", "id" => "u1"})
        end
      end

      cl =
        client(plug,
          retry: [
            max_attempts: 2,
            base_backoff_ms: 7,
            sleep_fn: fn ms -> send(parent, {:slept, ms}) end
          ]
        )

      assert {:ok, %{"id" => "u1"}} = Users.me(cl)
      assert_received {:slept, 30_000}
      assert_received :retried
    end
  end

  defp bump do
    prev = Process.get(:call_count) || 0
    Process.put(:call_count, prev + 1)
    prev + 1
  end
end
