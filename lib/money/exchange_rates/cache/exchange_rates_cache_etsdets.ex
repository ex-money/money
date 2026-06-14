defmodule Money.ExchangeRates.Cache.EtsDets do
  @moduledoc false

  defmacro define_common_functions do
    quote do
      def latest_rates do
        case get(:latest_rates) do
          nil ->
            {:error, {Money.ExchangeRateError, "No exchange rates were found"}}

          rates ->
            {:ok, rates}
        end
      end

      def historic_rates(%Date{calendar: Calendar.ISO} = date) do
        case get(date) do
          nil ->
            {:error,
             {Money.ExchangeRateError, "No exchange rates for #{Date.to_string(date)} were found"}}

          rates ->
            {:ok, rates}
        end
      end

      def historic_rates(%{year: year, month: month, day: day}) do
        {:ok, date} = Date.new(year, month, day)
        historic_rates(date)
      end

      def last_updated do
        case get(:last_updated) do
          nil ->
            Logger.error("Argument error getting last updated timestamp from ETS table")
            {:error, {Money.ExchangeRateError, "Last updated date is not known"}}

          last_updated ->
            {:ok, last_updated}
        end
      end

      def store_latest_rates(rates, retrieved_at) do
        put(:latest_rates, rates)
        put(:last_updated, retrieved_at)
      end

      def store_historic_rates(rates, date) do
        put(date, rates)
      end
    end
  end
end
