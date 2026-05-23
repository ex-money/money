defmodule Money.ExchangeRates.Cache do
  @moduledoc """
  Defines the cache behaviour for exchange rates.
  """

  @doc """
  Initialize the cache when the exchange rates
  retriever is started
  """
  @callback init() :: any()

  @doc """
  Terminate the cache when the retriever process
  stops normally
  """
  @callback terminate() :: any()

  @doc """
  Retrieve the latest exchange rates from the
  cache.
  """
  @callback latest_rates() :: {:ok, map()} | {:error, {Exception.t(), String.t()}}

  @doc """
  Retrieve the exchange rates for a given
  date.
  """
  @callback historic_rates(Date.t()) :: {:ok, map()} | {:error, {Exception.t(), String.t()}}

  @doc """
  Return the timestamp when the exchange rates were last updated.
  """
  @callback last_updated() :: {:ok, DateTime.t()} | {:error, {Exception.t(), String.t()}}

  @doc """
  Store the latest exchange rates in the cache.
  """
  @callback store_latest_rates(map(), DateTime.t()) :: :ok

  @doc """
  Store the historic exchange rates for a given
  date in the cache.
  """
  @callback store_historic_rates(map(), Date.t()) :: :ok

  @doc false
  def latest_rates do
    cache().latest_rates
  end

  @doc false
  def historic_rates(date) do
    cache().historic_rates(date)
  end

  @doc false
  def cache do
    Money.ExchangeRates.Retriever.config().cache_module
  end
end
