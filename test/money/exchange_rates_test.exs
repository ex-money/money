defmodule Money.ExchangeRatesTest do
  use ExUnit.Case
  import ExUnit.CaptureIO

  alias Money.ExchangeRates

  test "Get exchange rates from ExchangeRates.Retriever" do
    test_result = {:ok, %{USD: Decimal.new(1), AUD: Decimal.new("0.7"), EUR: Decimal.new("1.2")}}
    assert Money.ExchangeRates.latest_rates() == test_result
  end

  test "Get exchange rates from ExchangeRates" do
    test_result = {:ok, %{USD: Decimal.new(1), AUD: Decimal.new("0.7"), EUR: Decimal.new("1.2")}}
    assert Money.ExchangeRates.latest_rates() == test_result
  end

  test "Localize money" do
    assert {:ok, _} = Money.localize(Money.new(:AUD, 100), locale: "en")
  end

  test "Convert from USD to AUD" do
    assert Money.compare(Money.to_currency!(Money.new(:USD, 100), :AUD), Money.new(:AUD, 70)) == :eq
  end

  test "Convert from USD to USD" do
    assert Money.compare(Money.to_currency!(Money.new(:USD, 100), :USD), Money.new(:USD, 100)) ==
             :eq
  end

  test "Convert from USD to ZZZ should return an error" do
    capture_io(fn ->
      assert Money.to_currency(Money.new(:USD, 100), :ZZZ) ==
               {:error, {Money.UnknownCurrencyError, "The currency :ZZZ is not known."}}
    end)
  end

  test "Convert from USD to ZZZ should raise an exception" do
    capture_io(fn ->
      assert_raise Money.UnknownCurrencyError, ~r/The currency :ZZZ is not known/, fn ->
        assert Money.to_currency!(Money.new(:USD, 100), :ZZZ)
      end
    end)
  end

  test "Convert from USD to AUD using historic rates" do
    capture_io(fn ->
      assert Money.to_currency!(
               Money.new(:USD, 100),
               :AUD,
               ExchangeRates.historic_rates(~D[2017-01-01])
             )
             |> Money.round() == Money.new(:AUD, Decimal.new("71.43"))
    end)
  end

  test "Convert from USD to AUD using historic rates that aren't available" do
    assert Money.to_currency(
             Money.new(:USD, 100),
             :AUD,
             ExchangeRates.historic_rates(~D[2017-02-01])
           ) == {:error, {Money.ExchangeRateError, "No exchange rates for 2017-02-01 were found"}}
  end

  test "That an error is returned if there is no open exchange rates app_id configured" do
    Application.put_env(:ex_money, :open_exchange_rates_app_id, nil)
    config = Money.ExchangeRates.OpenExchangeRates.init(Money.ExchangeRates.default_config())
    config = Map.put(config, :log_levels, %{failure: nil, info: nil, success: nil})

    assert Money.ExchangeRates.OpenExchangeRates.get_latest_rates(config) ==
             {:error, "Open Exchange Rates app_id is not configured. Rates are not retrieved."}
  end

  if System.get_env("OPEN_EXCHANGE_RATES_APP_ID") do
    test "That the Open Exchange Rates retriever returns a map" do
      Application.put_env(
        :ex_money,
        :open_exchange_rates_app_id,
        System.get_env("OPEN_EXCHANGE_RATES_APP_ID")
      )

      config = Money.ExchangeRates.OpenExchangeRates.init(Money.ExchangeRates.default_config())
      config = Map.put(config, :log_levels, %{failure: nil, info: nil, success: nil})

      # Testing only, should not be used in production
      # config = Map.put(config, :verify_peer, false)

      case Money.ExchangeRates.OpenExchangeRates.get_latest_rates(config) do
        {:ok, rates} -> assert is_map(rates)
        {:error, :nxdomain} -> :no_network
        {:error, other} -> IO.warn(inspect(other))
      end
    end
  end

  test "that api latest_rates callbacks are executed" do
    config =
      Money.ExchangeRates.default_config()
      |> Map.put(:callback_module, Money.ExchangeRatesCallbackMock)

    Money.ExchangeRates.Retriever.reconfigure(config)
    Money.ExchangeRates.Retriever.latest_rates()

    assert Application.get_env(:ex_money, :test) == "Latest Rates Retrieved"

    Money.ExchangeRates.default_config()
    |> Money.ExchangeRates.Retriever.reconfigure()
  end

  test "that api historic_rates callbacks are executed" do
    config =
      Money.ExchangeRates.default_config()
      |> Map.put(:callback_module, Money.ExchangeRatesCallbackMock)

    Money.ExchangeRates.Retriever.reconfigure(config)
    Money.ExchangeRates.Retriever.historic_rates(~D[2017-01-01])

    assert Application.get_env(:ex_money, :test) == "Historic Rates Retrieved"

    Money.ExchangeRates.default_config()
    |> Money.ExchangeRates.Retriever.reconfigure()
  end

  test "that the last_udpated timestamp is returned in a success tuple" do
    # warm up cache
    Money.ExchangeRates.Retriever.latest_rates()

    assert {:ok, %DateTime{}} = Money.ExchangeRates.last_updated()
  end
end
