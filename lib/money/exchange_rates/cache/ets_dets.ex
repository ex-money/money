defmodule Money.ExchangeRates.Cache.EtsDets do
  @moduledoc false

  defmacro __using__(_opts) do
    quote do
      @behaviour Money.ExchangeRates.Cache

      require Logger

      @impl Money.ExchangeRates.Cache
      def latest_rates(cache) do
        case get(cache, :latest_rates) do
          nil ->
            {:error, {Money.ExchangeRateError, "No exchange rates were found"}}

          rates ->
            {:ok, rates}
        end
      end

      @impl Money.ExchangeRates.Cache
      def historic_rates(cache, %Date{calendar: Calendar.ISO} = date) do
        case get(cache, date) do
          nil ->
            {:error,
             {Money.ExchangeRateError, "No exchange rates for #{Date.to_string(date)} were found"}}

          rates ->
            {:ok, rates}
        end
      end

      @impl Money.ExchangeRates.Cache
      def last_updated(cache) do
        case get(cache, :last_updated) do
          nil ->
            Logger.error("Argument error getting last updated timestamp from ETS table")
            {:error, {Money.ExchangeRateError, "Last updated date is not known"}}

          last_updated ->
            {:ok, last_updated}
        end
      end

      @impl Money.ExchangeRates.Cache
      def store_latest_rates(cache, rates, retrieved_at) do
        put(cache, :latest_rates, rates)
        put(cache, :last_updated, retrieved_at)
      end

      @impl Money.ExchangeRates.Cache
      def store_historic_rates(cache, rates, date) do
        put(cache, date, rates)
      end
    end
  end
end
