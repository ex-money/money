defmodule Money.ExchangeRatesCallbackMock do
  @behaviour Money.ExchangeRates.Callback

  def init do
    :ok
  end

  def latest_rates_retrieved(_rates, _retrieved_at) do
    :ok
  end

  def historic_rates_retrieved(_rates, _date) do
    :ok
  end
end
