defmodule Money.ExchangeRates.Cache do
  @moduledoc """
  Defines a cache behaviour and default implementation
  of a cache for exchange rates
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
  Store the latest exchange rates in the cache.
  """
  @callback store_latest_rates(map(), DateTime.t()) :: :ok

  @doc """
  Store the historic exchange rates for a given
  date in the cache.
  """
  @callback store_historic_rates(map(), Date.t()) :: :ok

  def latest_rates do
    cache().latest_rates
  end

  def historic_rates(date) do
    cache().historic_rates(date)
  end

  def cache do
    Money.ExchangeRates.Retriever.config().cache_module
  end
end
