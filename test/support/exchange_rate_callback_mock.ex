defmodule Money.ExchangeRatesCallbackMock do
  @behaviour Money.ExchangeRates.Callback

  def init do
    :ok
  end

  def latest_rates_retrieved(_rates, _retrieved_at) do
    Application.put_env(:ex_money, :test, "Latest Rates Retrieved")
    :ok
  end

  def historic_rates_retrieved(_rates, _date) do
    Application.put_env(:ex_money, :test, "Historic Rates Retrieved")
    :ok
  end
end
