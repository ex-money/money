defmodule Money.ExchangeRates.Cache.EtsTest do
  use ExUnit.Case

  alias Money.ExchangeRates.Cache.Ets

  doctest Ets

  @rates %{USD: Decimal.new(1), AUD: Decimal.new("1.5")}
  @date ~D[2099-01-01]

  setup do
    # Remove any :latest_rates written during this test so the shared ETS table
    # does not contaminate other test modules that call Money.ExchangeRates.latest_rates/0
    on_exit(fn -> :ets.delete(:exchange_rates, :latest_rates) end)
    :ok
  end

  describe "init/0" do
    test "returns the table name when the table already exists" do
      assert Ets.init() == :exchange_rates
    end
  end

  describe "terminate/0" do
    test "returns :ok" do
      assert Ets.terminate() == :ok
    end
  end

  describe "store_latest_rates/2 and latest_rates/0" do
    test "returns stored rates" do
      retrieved_at = DateTime.utc_now()
      Ets.store_latest_rates(@rates, retrieved_at)
      assert Ets.latest_rates() == {:ok, @rates}
    end
  end

  describe "store_historic_rates/2 and historic_rates/1" do
    test "returns stored rates for a Date" do
      Ets.store_historic_rates(@rates, @date)
      assert Ets.historic_rates(@date) == {:ok, @rates}
    end

    test "returns an error for an unstored date" do
      assert Ets.historic_rates(~D[2099-12-31]) ==
               {:error, {Money.ExchangeRateError, "No exchange rates for 2099-12-31 were found"}}
    end
  end

  describe "last_updated/0" do
    test "returns the timestamp stored alongside the latest rates" do
      retrieved_at = DateTime.utc_now()
      Ets.store_latest_rates(@rates, retrieved_at)
      assert Ets.last_updated() == {:ok, retrieved_at}
    end
  end
end
