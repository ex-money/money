defmodule Money.ExchangeRatesHttpMock do
  @etag ~c"test-etag-123"
  @date ~c"Mon, 01 Jan 2024 00:00:00 GMT"
  @response_headers [{~c"etag", @etag}, {~c"date", @date}]
  @rates_body ~s({"base":"USD","rates":{"AUD":1.5,"EUR":0.9,"USD":1.0}})

  def get_with_headers({"http://error.example.com", _headers}, _opts) do
    {:error, :nxdomain}
  end

  def get_with_headers({"http://success.example.com", headers}, _opts) do
    if :proplists.get_value(~c"if-none-match", headers) == :undefined do
      {:ok, @response_headers, @rates_body}
    else
      {:not_modified, @response_headers}
    end
  end
end
