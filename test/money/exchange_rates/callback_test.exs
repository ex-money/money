defmodule Money.ExchangeRates.CallbackTest do
  use ExUnit.Case

  alias Money.ExchangeRates.Callback

  test "latest_rates_retrieved/2 returns :ok" do
    assert Callback.latest_rates_retrieved(%{USD: Decimal.new(1)}, DateTime.utc_now()) == :ok
  end

  test "historic_rates_retrieved/2 returns :ok" do
    assert Callback.historic_rates_retrieved(%{USD: Decimal.new(1)}, ~D[2024-01-01]) == :ok
  end
end
