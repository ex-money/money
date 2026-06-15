defmodule Money.ExchangeRatesMock do
  @behaviour Money.ExchangeRates

  @app_id "app_id"
  @exr_url "https://openexchangerates.org/api"

  @latest_endpoint "/latest.json"
  @latest_url @exr_url <> @latest_endpoint <> "?app_id=" <> @app_id

  @impl true
  def init(config) do
    url = @latest_url
    app_id = @app_id

    Map.put(config, :retriever_options, %{url: url, app_id: app_id})
  end

  def decode_rates(rates) do
    Money.ExchangeRates.OpenExchangeRates.decode_rates(rates)
  end

  @impl true
  def get_latest_rates(_config) do
    get_rates(@latest_url)
  end

  @impl true
  def get_historic_rates(~D[2017-01-01], _config) do
    {:ok, %{AUD: Decimal.new("0.5"), EUR: Decimal.new("1.1"), USD: Decimal.new("0.7")}}
  end

  def get_historic_rates(~D[2017-01-02], _config) do
    {:ok, %{AUD: Decimal.new("0.4"), EUR: Decimal.new("0.9"), USD: Decimal.new("0.6")}}
  end

  def get_historic_rates(date, _config) do
    {:error, {Money.ExchangeRateError, "No exchange rates for #{Date.to_string(date)} were found"}}
  end

  defp get_rates("invalid_url") do
    {:error, "bad url"}
  end

  defp get_rates("http:/something.com/unknown" = url) do
    {:error, "#{url} was not found"}
  end

  defp get_rates(@latest_url) do
    {:ok, %{AUD: Decimal.new("0.7"), EUR: Decimal.new("1.2"), USD: Decimal.new(1)}}
  end
end
