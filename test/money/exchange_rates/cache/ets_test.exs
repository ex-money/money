defmodule Money.ExchangeRates.Cache.EtsTest do
  use ExUnit.Case

  alias Money.ExchangeRates.Cache.Ets

  doctest Ets

  @rates %{USD: Decimal.new(1), AUD: Decimal.new("1.5")}
  @date ~D[2099-01-01]

  setup do
    cache = Ets.init(:"ets_test_#{System.unique_integer([:positive])}")

    {:ok, cache: cache}
  end

  describe "init/1" do
    test "accepts a non-atom name and returns a usable handle" do
      cache = Ets.init({:via, Registry, {SomeRegistry, :bid}})

      retrieved_at = DateTime.utc_now()
      Ets.store_latest_rates(cache, @rates, retrieved_at)
      assert Ets.latest_rates(cache) == {:ok, @rates}
    end

    test "returns an isolated cache on each call" do
      other = Ets.init(:"ets_test_#{System.unique_integer([:positive])}")

      Ets.store_latest_rates(other, @rates, DateTime.utc_now())

      assert Ets.latest_rates(other) == {:ok, @rates}

      assert Ets.latest_rates(Ets.init(:another)) ==
               {:error, {Money.ExchangeRateError, "No exchange rates were found"}}
    end
  end

  describe "terminate/1" do
    test "returns :ok", %{cache: cache} do
      assert Ets.terminate(cache) == :ok
    end
  end

  describe "store_latest_rates/3 and latest_rates/1" do
    test "returns stored rates", %{cache: cache} do
      retrieved_at = DateTime.utc_now()
      Ets.store_latest_rates(cache, @rates, retrieved_at)
      assert Ets.latest_rates(cache) == {:ok, @rates}
    end
  end

  describe "store_historic_rates/3 and historic_rates/2" do
    test "returns stored rates for a Date", %{cache: cache} do
      Ets.store_historic_rates(cache, @rates, @date)
      assert Ets.historic_rates(cache, @date) == {:ok, @rates}
    end

    test "returns an error for an unstored date", %{cache: cache} do
      assert Ets.historic_rates(cache, ~D[2099-12-31]) ==
               {:error, {Money.ExchangeRateError, "No exchange rates for 2099-12-31 were found"}}
    end
  end

  describe "last_updated/1" do
    test "returns the timestamp stored alongside the latest rates", %{cache: cache} do
      retrieved_at = DateTime.utc_now()
      Ets.store_latest_rates(cache, @rates, retrieved_at)
      assert Ets.last_updated(cache) == {:ok, retrieved_at}
    end
  end
end
