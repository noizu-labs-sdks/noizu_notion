defmodule Noizu.Notion.ErrorTest do
  use ExUnit.Case, async: true

  alias Noizu.Notion.Error
  alias Noizu.Notion.Testing

  describe "from_response/2" do
    test "maps the documented envelope onto the struct with an atom code" do
      body = Testing.error_body(404, "object_not_found", "Could not find page with ID: abc.")

      assert %Error{} = error = Error.from_response(404, body)
      assert error.status == 404
      assert error.code == :object_not_found
      assert error.message == "Could not find page with ID: abc."
      assert error.request_id == "req-abc-123"
    end

    test "keeps unknown codes as strings (no dynamic atom creation)" do
      body = Testing.error_body(400, "some_brand_new_code", "what is this")

      assert %Error{code: "some_brand_new_code"} = Error.from_response(400, body)
    end

    test "known codes are existing atoms" do
      body = Testing.error_body(429, "rate_limited", "slow down")

      assert %Error{code: :rate_limited} = Error.from_response(429, body)
      assert :rate_limited in Error.known_codes()
    end

    test "falls back to the HTTP status when the body omits it" do
      body = %{"object" => "error", "code" => "conflict_error", "message" => "conflict"}

      assert %Error{status: 409} = Error.from_response(409, body)
    end

    test "non-error bodies become :invalid_response" do
      assert %Error{status: 502, code: :invalid_response} =
               Error.from_response(502, "Bad Gateway")
    end
  end

  describe "retryable?/2" do
    test "429 and 529 are always retryable" do
      assert Error.retryable?(%Error{status: 429}, idempotent: false)
      assert Error.retryable?(%Error{status: 529}, idempotent: false)
    end

    test "502/503/504 only for idempotent methods" do
      assert Error.retryable?(%Error{status: 503}, idempotent: true)
      refute Error.retryable?(%Error{status: 502}, idempotent: false)
      refute Error.retryable?(%Error{status: 504}, idempotent: false)
    end

    test "client errors, 409 and 500 are not retryable" do
      for status <- [400, 401, 403, 404, 406, 409, 500] do
        refute Error.retryable?(%Error{status: status}), "status #{status}"
      end
    end
  end

  describe "retry_after_ms/2" do
    test "prefers the retry-after header (seconds -> ms)" do
      error = Error.from_response(429, Testing.error_body(429, "rate_limited", "x"))

      assert Error.retry_after_ms(error, %{"retry-after" => ["3"]}) == 3_000
      assert Error.retry_after_ms(error, %{"retry-after" => ["0"]}) == 0
    end

    test "falls back to additional_data.retry_after" do
      body =
        Testing.error_body(429, "rate_limited", "x")
        |> Map.put("additional_data", %{"retry_after" => 2})

      assert Error.retry_after_ms(Error.from_response(429, body), %{}) == 2_000
    end

    test "returns nil when neither header nor body hint exists" do
      error = Error.from_response(429, Testing.error_body(429, "rate_limited", "x"))
      assert Error.retry_after_ms(error, %{}) == nil
    end

    test "clamps huge header and body values to the 30s cap (T-002)" do
      error = Error.from_response(429, Testing.error_body(429, "rate_limited", "x"))

      assert Error.retry_after_ms(error, %{"retry-after" => ["45"]}) == 30_000
      assert Error.retry_after_ms(error, %{"retry-after" => ["2000000000"]}) == 30_000

      huge_body =
        Testing.error_body(429, "rate_limited", "x")
        |> Map.put("additional_data", %{"retry_after" => 1_000_000})

      assert Error.retry_after_ms(Error.from_response(429, huge_body), %{}) == 30_000
    end

    test "negative or non-numeric header values fall back (T-002)" do
      error = Error.from_response(429, Testing.error_body(429, "rate_limited", "x"))

      assert Error.retry_after_ms(error, %{"retry-after" => ["-5"]}) == nil
      assert Error.retry_after_ms(error, %{"retry-after" => ["soon"]}) == nil
    end

    test "additional_data.retry_after: clamped, negatives nil, fractions kept (T-002)" do
      fraction =
        Testing.error_body(429, "rate_limited", "x")
        |> Map.put("additional_data", %{"retry_after" => 1.5})

      negative =
        Testing.error_body(429, "rate_limited", "x")
        |> Map.put("additional_data", %{"retry_after" => -4})

      assert Error.retry_after_ms(Error.from_response(429, fraction)) == 1_500
      assert Error.retry_after_ms(Error.from_response(429, negative)) == nil
    end
  end

  test "message/1 renders a readable one-liner" do
    error = Error.from_response(404, Testing.error_body(404, "object_not_found", "nope"))

    assert Exception.message(error) ==
             "notion_error status=404 code=object_not_found [request_id: req-abc-123]: nope"
  end

  test "from_exception/1 wraps transport errors" do
    error = Error.from_exception(%RuntimeError{message: "connection refused"})

    assert error.status == nil
    assert error.code == :request_failed
    assert error.message == "connection refused"
  end
end
