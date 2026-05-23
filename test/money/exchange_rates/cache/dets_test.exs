defmodule Money.ExchangeRates.Cache.DetsTest do
  use ExUnit.Case

  alias Money.ExchangeRates.Cache.Dets

  doctest Dets

  @rates %{USD: Decimal.new(1), AUD: Decimal.new("1.5")}
  @date ~D[2099-02-01]

  setup do
    Dets.init()

    on_exit(fn ->
      # Remove any :latest_rates written during this test so the shared ETS table
      # does not contaminate other test modules that call Money.ExchangeRates.latest_rates/0
      :ets.delete(:exchange_rates, :latest_rates)
      Dets.terminate()
    end)

    :ok
  end

  describe "init/0" do
    test "returns the table name" do
      assert Dets.init() == :exchange_rates
    end
  end

  describe "terminate/0" do
    test "returns :ok" do
      assert Dets.terminate() == :ok
    end
  end

  describe "store_latest_rates/2 and latest_rates/0" do
    test "returns stored rates" do
      retrieved_at = DateTime.utc_now()
      Dets.store_latest_rates(@rates, retrieved_at)
      assert Dets.latest_rates() == {:ok, @rates}
    end
  end

  describe "store_historic_rates/2 and historic_rates/1" do
    test "returns stored rates for a Date" do
      Dets.store_historic_rates(@rates, @date)
      assert Dets.historic_rates(@date) == {:ok, @rates}
    end

    test "returns an error for an unstored date" do
      assert Dets.historic_rates(~D[2099-12-30]) ==
               {:error, {Money.ExchangeRateError, "No exchange rates for 2099-12-30 were found"}}
    end
  end

  describe "last_updated/0" do
    test "returns the timestamp stored alongside the latest rates" do
      retrieved_at = DateTime.utc_now()
      Dets.store_latest_rates(@rates, retrieved_at)
      assert Dets.last_updated() == {:ok, retrieved_at}
    end
  end

  describe "persistence across restarts" do
    test "latest rates survive terminate/init cycle" do
      retrieved_at = DateTime.utc_now()
      Dets.store_latest_rates(@rates, retrieved_at)
      Dets.terminate()
      Dets.init()
      assert Dets.latest_rates() == {:ok, @rates}
    end

    test "historic rates survive terminate/init cycle" do
      Dets.store_historic_rates(@rates, @date)
      Dets.terminate()
      Dets.init()
      assert Dets.historic_rates(@date) == {:ok, @rates}
    end
  end
end
