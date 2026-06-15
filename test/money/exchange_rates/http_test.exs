defmodule Money.ExchangeRates.HTTPTest do
  use ExUnit.Case, async: false

  alias Money.ExchangeRates.HTTP

  defmodule HttpMock do
    def get_with_headers({"https://example.com", []}, _opts) do
      {:ok, [{~c"etag", "etag-v1"}], "response"}
    end

    def get_with_headers({"https://example.com", [{~c"if-none-match", "etag-v1"}]}, _opts) do
      {:not_modified, [{~c"etag", "etag-v2"}]}
    end

    def get_with_headers({"https://example.com", [{~c"if-none-match", "etag-v2"}]}, _opts) do
      {:not_modified, [{~c"etag", "etag-v2"}]}
    end

    def get_with_headers({"https://example.com/error", []}, _opts) do
      {:error, :timeout}
    end
  end

  setup do
    Application.put_env(:ex_money, :exchange_rates_http_client, HttpMock)
    on_exit(fn -> Application.delete_env(:ex_money, :exchange_rates_http_client) end)
  end

  describe "get/2" do
    test "caches response headers and returns the body" do
      assert HTTP.get("https://example.com") == {:ok, "response"}
    end

    test "sends cached conditional headers on subsequent requests" do
      # populates cache with etag-v1
      HTTP.get("https://example.com")
      assert HTTP.get("https://example.com") == {:ok, :not_modified}
    end

    test "saves headers from :not_modified response to cache" do
      # caches etag-v1
      HTTP.get("https://example.com")
      # server rotates to etag-v2
      assert HTTP.get("https://example.com") == {:ok, :not_modified}
      # only passes if etag-v2 was cached; etag-v1 would raise here
      assert HTTP.get("https://example.com") == {:ok, :not_modified}
    end

    test "wraps HTTP errors in an ExchangeRateError" do
      assert HTTP.get("https://example.com/error") ==
               {:error, {Money.ExchangeRateError, ":timeout"}}
    end
  end
end
