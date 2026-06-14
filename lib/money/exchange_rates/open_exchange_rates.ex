defmodule Money.ExchangeRates.OpenExchangeRates do
  @moduledoc """
  Implements the `Money.ExchangeRates` for the Open Exchange
  Rates service.

  ## Required configuration:

  The configuration key `:open_exchange_rates_app_id` should be
  set to your `app_id`. For example:

      config :ex_money,
        open_exchange_rates_app_id: "your_app_id"

  or configure it via environment variable:

      config :ex_money,
        open_exchange_rates_app_id: {:system, "OPEN_EXCHANGE_RATES_APP_ID"}

  It is also possible to configure an alternative base url for this
  service in case it changes in the future. For example:

      config :ex_money,
        open_exchange_rates_app_id: "your_app_id"
        open_exchange_rates_url: "https://openexchangerates.org/alternative_api"

  """

  alias Money.ExchangeRates.Retriever

  @behaviour Money.ExchangeRates

  @open_exchange_rate_url "https://openexchangerates.org/api"

  @doc """
  Update the retriever configuration to include the requirements
  for Open Exchange Rates. This function is invoked when the
  exchange rate service starts up, just after the ets table
  :exchange_rates is created.

  * `default_config` is the configuration returned by `Money.ExchangeRates.default_config/0`

  Returns the configuration either unchanged or updated with
  additional configuration specific to this exchange
  rates retrieval module.
  """
  def init(default_config) do
    url = Money.get_env(:open_exchange_rates_url, @open_exchange_rate_url)
    app_id = Money.get_env(:open_exchange_rates_app_id, nil)
    Map.put(default_config, :retriever_options, %{url: url, app_id: app_id})
  end

  def decode_rates(body) when is_list(body) do
    body
    |> List.to_string()
    |> decode_rates()
  end

  def decode_rates(body) when is_binary(body) do
    %{"base" => _base, "rates" => rates} = :json.decode(body)

    rates
    |> Localize.Utils.Map.atomize_keys()
    |> Enum.map(fn
      {k, v} when is_float(v) -> {k, Decimal.from_float(v)}
      {k, v} when is_integer(v) -> {k, Decimal.new(v)}
    end)
    |> Enum.into(%{})
  end

  @doc """
  Retrieves the latest exchange rates from Open Exchange Rates site.

  * `config` is the retrieval configuration. When invoked from the
    exchange rates service this will be the config returned from
    `Money.ExchangeRates.config/0`

  Returns:

  * `{:ok, rates}` if the rates can be retrieved

  * `{:error, reason}` if rates cannot be retrieved

  Typically this function is called by the exchange rates retrieval
  service although it can be called outside that context as
  required.

  """
  @spec get_latest_rates(Money.ExchangeRates.Config.t()) :: {:ok, map()} | {:error, String.t()}
  def get_latest_rates(config) do
    url = config.retriever_options.url
    app_id = config.retriever_options.app_id
    retrieve_latest_rates(url, app_id, config)
  end

  defp retrieve_latest_rates(_url, nil, _config) do
    {:error, app_id_not_configured()}
  end

  @latest_rates "/latest.json"
  defp retrieve_latest_rates(url, app_id, config) do
    Retriever.retrieve_rates(url <> @latest_rates <> "?app_id=" <> app_id, config)
  end

  @doc """
  Retrieves the historic exchange rates from Open Exchange Rates site.

  * `date` is a date returned by `Date.new/3` or any struct with the
    elements `:year`, `:month` and `:day`.

  * `config` is the retrieval configuration. When invoked from the
    exchange rates service this will be the config returned from
    `Money.ExchangeRates.config/0`

  Returns:

  * `{:ok, rates}` if the rates can be retrieved

  * `{:error, reason}` if rates cannot be retrieved

  Typically this function is called by the exchange rates retrieval
  service although it can be called outside that context as
  required.
  """
  def get_historic_rates(date, config) do
    url = config.retriever_options.url
    app_id = config.retriever_options.app_id
    retrieve_historic_rates(date, url, app_id, config)
  end

  defp retrieve_historic_rates(_date, _url, nil, _config) do
    {:error, app_id_not_configured()}
  end

  @historic_rates "/historical/"
  defp retrieve_historic_rates(%Date{calendar: Calendar.ISO} = date, url, app_id, config) do
    date_string = Date.to_string(date)

    Retriever.retrieve_rates(
      url <> @historic_rates <> "#{date_string}.json" <> "?app_id=" <> app_id,
      config
    )
  end

  defp retrieve_historic_rates(%{year: year, month: month, day: day}, url, app_id, config) do
    case Date.new(year, month, day) do
      {:ok, date} -> retrieve_historic_rates(date, url, app_id, config)
      error -> error
    end
  end

  defp app_id_not_configured do
    "Open Exchange Rates app_id is not configured. Rates are not retrieved."
  end
end
