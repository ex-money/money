defmodule Money.ExchangeRates.OpenExchangeRatesTest do
  use ExUnit.Case, async: false

  alias Money.ExchangeRates.OpenExchangeRates

  defmodule HttpMock do
    @rates_body ~c({"base":"USD","rates":{"USD":1.0,"EUR":0.9,"AUD":1.5}})

    def get_with_headers(
          {"https://openexchangerates.org/api/latest.json?app_id=test_app_id", _headers},
          _opts
        ) do
      {:ok, [], @rates_body}
    end

    def get_with_headers(
          {"https://openexchangerates.org/api/historical/2024-01-15.json?app_id=test_app_id",
           _headers},
          _opts
        ) do
      {:ok, [], @rates_body}
    end
  end

  setup do
    on_exit(fn ->
      Application.delete_env(:ex_money, :open_exchange_rates_app_id)
      Application.delete_env(:ex_money, :open_exchange_rates_url)
      Application.delete_env(:ex_money, :exchange_rates_http_client)
    end)

    :ok
  end

  describe "init/1" do
    test "merges retriever_options with the default url and configured app_id" do
      Application.put_env(:ex_money, :open_exchange_rates_app_id, "test_app_id")

      config = OpenExchangeRates.init(Money.ExchangeRates.default_config())

      assert config.retriever_options == %{
               url: "https://openexchangerates.org/api",
               app_id: "test_app_id"
             }
    end

    test "uses a custom url when open_exchange_rates_url is set" do
      custom_url = "https://custom.example.com/api"
      Application.put_env(:ex_money, :open_exchange_rates_url, custom_url)

      config = OpenExchangeRates.init(Money.ExchangeRates.default_config())

      assert config.retriever_options.url == custom_url
    end

    test "sets app_id to nil when not configured" do
      config = OpenExchangeRates.init(Money.ExchangeRates.default_config())

      assert config.retriever_options.app_id == nil
    end
  end

  describe "get_latest_rates/1" do
    setup do: %{config: init_config()}

    test "returns an error when app_id is nil" do
      config = init_config(app_id: nil)

      assert OpenExchangeRates.get_latest_rates(config) ==
               {:error, "Open Exchange Rates app_id is not configured. Rates are not retrieved."}
    end

    test "retrieves and returns the decoded rates map", %{config: config} do
      assert {:ok, rates} = OpenExchangeRates.get_latest_rates(config)

      assert rates == %{
               USD: Decimal.from_float(1.0),
               EUR: Decimal.from_float(0.9),
               AUD: Decimal.from_float(1.5)
             }
    end
  end

  describe "get_historic_rates/2" do
    setup do: %{config: init_config()}

    test "returns an error when app_id is nil" do
      config = init_config(app_id: nil)

      assert OpenExchangeRates.get_historic_rates(~D[2024-01-15], config) ==
               {:error, "Open Exchange Rates app_id is not configured. Rates are not retrieved."}
    end

    test "retrieves rates for a Date struct", %{config: config} do
      assert {:ok, rates} = OpenExchangeRates.get_historic_rates(~D[2024-01-15], config)

      assert rates == %{
               USD: Decimal.from_float(1.0),
               EUR: Decimal.from_float(0.9),
               AUD: Decimal.from_float(1.5)
             }
    end
  end

  defp init_config(opts \\ []) do
    Application.put_env(
      :ex_money,
      :open_exchange_rates_app_id,
      Keyword.get(opts, :app_id, "test_app_id")
    )

    Application.put_env(:ex_money, :exchange_rates_http_client, HttpMock)

    OpenExchangeRates.init(Money.ExchangeRates.default_config())
  end
end
