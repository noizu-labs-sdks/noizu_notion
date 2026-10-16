defmodule Noizu.Notion.ClientTest do
  use ExUnit.Case, async: true

  alias Noizu.Notion.{Client, Error, Request}

  @token "secret_live_credential_9f2c8ab1"

  describe "Inspect redaction (T-001)" do
    test "inspect/2 never prints the bearer token" do
      client = Client.new(token: @token)
      rendered = inspect(client)

      refute rendered =~ @token
      assert rendered =~ ~s(token: "[REDACTED]")
    end

    test "a nil token still renders as nil" do
      rendered = inspect(Client.new([]))

      assert rendered =~ "token: nil"
      refute rendered =~ "[REDACTED]"
    end

    test "non-token fields stay readable for debugging" do
      rendered = inspect(Client.new(token: @token, retry: [max_attempts: 5]))

      assert rendered =~ ~s(version: "2026-03-11")
      assert rendered =~ ~s(base_url: "https://api.notion.com")
      assert rendered =~ "max_attempts: 5"
    end

    test "error structs and exception messages never carry the token" do
      # missing-token failure: fixed message, no token echo
      assert {:error, %Error{} = missing} =
               Request.perform(%{Client.new([]) | token: nil}, :get, "/users/me")

      refute Exception.message(missing) =~ @token
      refute inspect(missing) =~ @token

      # response-built errors: server data only
      server_error =
        Error.from_response(404, %{
          "object" => "error",
          "code" => "object_not_found",
          "message" => "nope"
        })

      refute Exception.message(server_error) =~ @token
      refute inspect(server_error) =~ @token
    end

    test "Req redacts the authorization header in request inspect output (T-001)" do
      req = Req.new(headers: [{"authorization", "Bearer " <> @token}])

      refute inspect(req) =~ @token
    end
  end
end
