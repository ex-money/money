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
      pid = Process.whereis(Money.ExchangeRates.Retriever)
      assert {:ok, rates} = ExchangeRates.latest_rates()

      trace_module(pid, Money.ExchangeRatesCallbackMock)

      assert ExchangeRates.latest_rates() == {:ok, rates}

      refute_received {:trace, ^pid, :call,
                       {Money.ExchangeRatesCallbackMock, :latest_rates_retrieved, _}}
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
      assert {:ok, _rates} = ExchangeRates.latest_rates()
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
      pid = Process.whereis(Money.ExchangeRates.Retriever)
      assert {:ok, rates} = ExchangeRates.historic_rates(~D[2017-01-01])

      trace_module(pid, Money.ExchangeRatesCallbackMock)

      assert ExchangeRates.historic_rates(~D[2017-01-01]) == {:ok, rates}

      refute_received {:trace, ^pid, :call,
                       {Money.ExchangeRatesCallbackMock, :historic_rates_retrieved, _}}
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
      assert {:ok, _rates} = ExchangeRates.historic_rates(~D[2017-01-01])
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
      assert {:ok, _rates} = ExchangeRates.latest_rates()

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
      assert {:ok, _rates} = ExchangeRates.latest_rates()
      stop_supervised(Money.ExchangeRates.Retriever)

      refute ExchangeRates.latest_rates_available?()
    end
  end

  describe "last_updated/0" do
    test "returns the time when rates have been stored" do
      before_fetch = DateTime.utc_now()
      assert {:ok, _rates} = ExchangeRates.latest_rates()

      assert {:ok, retrieved_at} = ExchangeRates.last_updated()
      assert DateTime.compare(retrieved_at, before_fetch) != :lt
    end

    test "returns an error when the retriever is not running" do
      stop_supervised(Money.ExchangeRates.Retriever)

      assert ExchangeRates.last_updated() ==
               {:error,
                {Money.ExchangeRateError, "Exchange rate service does not appear to be running"}}
    end

    test "returns error when retriever stops even if timestamp is cached" do
      assert {:ok, _rates} = ExchangeRates.latest_rates()
      stop_supervised(Money.ExchangeRates.Retriever)

      assert ExchangeRates.last_updated() ==
               {:error,
                {Money.ExchangeRateError, "Exchange rate service does not appear to be running"}}
    end
  end

  # An api module that does not export the optional init/1 callback.
  defmodule NoInitApi do
    def get_latest_rates(_config), do: {:error, "not implemented"}
    def get_historic_rates(_date, _config), do: {:error, "not implemented"}
  end

  describe "config/0" do
    test "uses the default configuration when the api module has no init/1" do
      previous = Application.get_env(:ex_money, :api_module)
      Application.put_env(:ex_money, :api_module, NoInitApi)

      try do
        config = Money.ExchangeRates.config()

        assert config.api_module == NoInitApi
        assert config.retriever_options == nil
      after
        if previous do
          Application.put_env(:ex_money, :api_module, previous)
        else
          Application.delete_env(:ex_money, :api_module)
        end
      end
    end

    test "runs the api module's init/1 to populate retriever_options even when the module is not loaded (issue #202)" do
      # Reproduces https://github.com/ex-money/money/issues/202: during
      # application startup the API module is referenced only as a config atom
      # and may not be loaded, so `function_exported?/3` returns false and the
      # `init/1` callback (which sets `:retriever_options`) is skipped, leaving
      # it `nil` and crashing the first rate fetch with `{:badmap, nil}`.
      previous = Application.get_env(:ex_money, :api_module)
      Application.put_env(:ex_money, :api_module, Money.ExchangeRates.OpenExchangeRates)

      try do
        # Force the "not loaded yet" condition. Safe here: the retriever started
        # in setup uses the mock API module, so no process is running this code.
        :code.purge(Money.ExchangeRates.OpenExchangeRates)
        :code.delete(Money.ExchangeRates.OpenExchangeRates)

        refute :erlang.function_exported(Money.ExchangeRates.OpenExchangeRates, :init, 1),
               "precondition: the api module must be unloaded for this regression"

        config = Money.ExchangeRates.config()

        assert is_map(config.retriever_options),
               "retriever_options must be populated, got: #{inspect(config.retriever_options)}"

        assert Map.has_key?(config.retriever_options, :url)
        assert Map.has_key?(config.retriever_options, :app_id)
      after
        if previous do
          Application.put_env(:ex_money, :api_module, previous)
        else
          Application.delete_env(:ex_money, :api_module)
        end
      end
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
