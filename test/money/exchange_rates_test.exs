defmodule Money.ExchangeRatesTest do
  use ExUnit.Case, async: false

  alias Money.ExchangeRates

  doctest ExchangeRates

  @rates %{
    AUD: Decimal.new("0.5"),
    EUR: Decimal.new("1.1"),
    USD: Decimal.new("0.7")
  }

  setup do
    Code.ensure_loaded!(Money.ExchangeRatesCallbackMock)

    config = %{
      Money.ExchangeRates.default_config()
      | callback_module: Money.ExchangeRatesCallbackMock
    }

    start_supervised!({Money.ExchangeRates.Retriever, [config: config]})
    :ok
  end

  describe "latest_rates/0" do
    test "fetches from the cache when rates are cached" do
      ExchangeRates.Cache.Ets.store_latest_rates(@rates, DateTime.utc_now())

      assert ExchangeRates.latest_rates() == {:ok, @rates}
    end

    test "fetches from the retriever when the cache is empty" do
      assert ExchangeRates.latest_rates() ==
               {:ok, %{AUD: Decimal.new("0.7"), EUR: Decimal.new("1.2"), USD: Decimal.new(1)}}
    end

    test "returns an error if the retriever is not running" do
      stop_supervised(Money.ExchangeRates.Retriever)

      assert ExchangeRates.latest_rates() ==
               {:error,
                {Money.ExchangeRateError, "Exchange rate service does not appear to be running"}}
    end

    test "returns error when retriever stops even if cache has rates" do
      ExchangeRates.Cache.Ets.store_latest_rates(@rates, DateTime.utc_now())
      stop_supervised(Money.ExchangeRates.Retriever)

      assert ExchangeRates.latest_rates() ==
               {:error,
                {Money.ExchangeRateError, "Exchange rate service does not appear to be running"}}
    end

    test "invokes latest_rates_retrieved callback after retrieval" do
      pid = Process.whereis(Money.ExchangeRates.Retriever)
      trace_module(pid, Money.ExchangeRatesCallbackMock)

      ExchangeRates.latest_rates()

      assert_received {:trace, ^pid, :call,
                       {Money.ExchangeRatesCallbackMock, :latest_rates_retrieved,
                        [_rates, _retrieved_at]}}
    end
  end

  describe "historic_rates/1" do
    test "fetches from the cache when rates are cached" do
      ExchangeRates.Cache.Ets.store_historic_rates(@rates, ~D[2017-01-01])

      assert ExchangeRates.historic_rates(~D[2017-01-01]) == {:ok, @rates}
    end

    test "fetches from the retriever when the cache is empty" do
      assert ExchangeRates.historic_rates(~D[2017-01-01]) == {:ok, @rates}
    end

    test "returns an error when the retriever is not running" do
      stop_supervised(Money.ExchangeRates.Retriever)

      assert ExchangeRates.historic_rates(~D[2017-01-01]) ==
               {:error,
                {Money.ExchangeRateError, "Exchange rate service does not appear to be running"}}
    end

    test "returns error when retriever stops even if cache has rates" do
      ExchangeRates.Cache.Ets.store_historic_rates(@rates, ~D[2017-01-01])
      stop_supervised(Money.ExchangeRates.Retriever)

      assert ExchangeRates.historic_rates(~D[2017-01-01]) ==
               {:error,
                {Money.ExchangeRateError, "Exchange rate service does not appear to be running"}}
    end

    test "invokes historic_rates_retrieved callback after retrieval" do
      pid = Process.whereis(Money.ExchangeRates.Retriever)
      trace_module(pid, Money.ExchangeRatesCallbackMock)

      ExchangeRates.historic_rates(~D[2017-01-01])

      assert_received {:trace, ^pid, :call,
                       {Money.ExchangeRatesCallbackMock, :historic_rates_retrieved, [_rates, _date]}}
    end
  end

  describe "latest_rates_available?/0" do
    test "returns true when rates are in the cache" do
      ExchangeRates.Cache.Ets.store_latest_rates(@rates, DateTime.utc_now())

      assert ExchangeRates.latest_rates_available?()
    end

    test "returns false when no rates are cached" do
      refute ExchangeRates.latest_rates_available?()
    end

    test "returns false when the retriever is not running" do
      stop_supervised(Money.ExchangeRates.Retriever)

      refute ExchangeRates.latest_rates_available?()
    end

    test "returns false when retriever stops even if cache has rates" do
      ExchangeRates.Cache.Ets.store_latest_rates(@rates, DateTime.utc_now())
      stop_supervised(Money.ExchangeRates.Retriever)

      refute ExchangeRates.latest_rates_available?()
    end
  end

  describe "last_updated/0" do
    test "returns the time when rates have been stored" do
      retrieved_at = DateTime.utc_now(:second)
      ExchangeRates.Cache.Ets.store_latest_rates(@rates, retrieved_at)

      assert ExchangeRates.last_updated() == {:ok, retrieved_at}
    end

    test "returns an error when the retriever is not running" do
      stop_supervised(Money.ExchangeRates.Retriever)

      assert ExchangeRates.last_updated() ==
               {:error,
                {Money.ExchangeRateError, "Exchange rate service does not appear to be running"}}
    end

    test "returns error when retriever stops even if timestamp is cached" do
      retrieved_at = DateTime.utc_now(:second)
      ExchangeRates.Cache.Ets.store_latest_rates(@rates, retrieved_at)
      stop_supervised(Money.ExchangeRates.Retriever)

      assert ExchangeRates.last_updated() ==
               {:error,
                {Money.ExchangeRateError, "Exchange rate service does not appear to be running"}}
    end
  end

  defp trace_module(pid, module) do
    :erlang.trace_pattern({module, :_, :_}, true, [:local])
    :erlang.trace(pid, true, [:call])

    on_exit(fn ->
      :erlang.trace_pattern({module, :_, :_}, false, [:local])
    end)
  end
end
