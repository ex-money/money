defmodule Money.ExchangeRates.Cache.DetsTest do
  use ExUnit.Case

  alias Money.ExchangeRates.Cache.Dets

  doctest Dets

  @rates %{USD: Decimal.new(1), AUD: Decimal.new("1.5")}
  @date ~D[2099-02-01]

  setup do
    name = :"dets_test_#{System.unique_integer([:positive])}"
    cache = Dets.init(name)

    on_exit(fn -> Dets.terminate(cache) end)

    {:ok, cache: cache}
  end

  describe "init/1" do
    test "accepts a non-atom name and returns a usable handle" do
      cache = Dets.init({:via, Registry, {SomeRegistry, :bid}})
      on_exit(fn -> Dets.terminate(cache) end)

      Dets.store_latest_rates(cache, @rates, DateTime.utc_now())
      assert Dets.latest_rates(cache) == {:ok, @rates}
    end
  end

  describe "terminate/1" do
    test "returns :ok", %{cache: cache} do
      assert Dets.terminate(cache) == :ok
    end
  end

  describe "store_latest_rates/3 and latest_rates/1" do
    test "returns stored rates", %{cache: cache} do
      retrieved_at = DateTime.utc_now()
      Dets.store_latest_rates(cache, @rates, retrieved_at)
      assert Dets.latest_rates(cache) == {:ok, @rates}
    end
  end

  describe "store_historic_rates/3 and historic_rates/2" do
    test "returns stored rates for a Date", %{cache: cache} do
      Dets.store_historic_rates(cache, @rates, @date)
      assert Dets.historic_rates(cache, @date) == {:ok, @rates}
    end

    test "returns an error for an unstored date", %{cache: cache} do
      assert Dets.historic_rates(cache, ~D[2099-12-30]) ==
               {:error, {Money.ExchangeRateError, "No exchange rates for 2099-12-30 were found"}}
    end
  end

  describe "last_updated/1" do
    test "returns the timestamp stored alongside the latest rates", %{cache: cache} do
      retrieved_at = DateTime.utc_now()
      Dets.store_latest_rates(cache, @rates, retrieved_at)
      assert Dets.last_updated(cache) == {:ok, retrieved_at}
    end
  end

  describe "persistence across restarts" do
    test "latest rates survive terminate/init cycle", %{cache: cache} do
      retrieved_at = DateTime.utc_now()
      Dets.store_latest_rates(cache, @rates, retrieved_at)
      Dets.terminate(cache)
      cache = Dets.init(cache)
      assert Dets.latest_rates(cache) == {:ok, @rates}
    end

    test "historic rates survive terminate/init cycle", %{cache: cache} do
      Dets.store_historic_rates(cache, @rates, @date)
      Dets.terminate(cache)
      cache = Dets.init(cache)
      assert Dets.historic_rates(cache, @date) == {:ok, @rates}
    end
  end
end
