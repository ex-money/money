defmodule Money.ExchangeRates.Cache do
  @moduledoc """
  Defines the cache behaviour for exchange rates.

  Most callbacks receive a `t:cache/0` term - the value returned by `c:init/1` -
  identifying which retriever's storage to operate on. This allows a single
  cache module (such as the bundled `Money.ExchangeRates.Cache.Ets` and
  `Money.ExchangeRates.Cache.Dets`) to be shared safely by multiple named
  retrievers, each backed by its own separated storage.

  ## Migrating from the deprecated singleton callbacks

  Older cache modules implemented `init/0`, `terminate/0`, `latest_rates/0`,
  `historic_rates/1`, `last_updated/0`, `store_latest_rates/2` and
  `store_historic_rates/2`, storing rates as fixed, module-wide state. These
  still work (with a compiler warning), but named retrievers sharing such a
  module overwrite each other's rates.

  To migrate, add the `t:cache/0` value returned by `init/1` as the leading
  argument to every other callback, and key storage off the `name` given to
  `init/1` instead of a fixed identifier:

      def init(name), do: :ets.new(name, [:named_table, :public])
      def latest_rates(cache), do: :ets.lookup(cache, :latest_rates)
      def store_latest_rates(cache, rates, retrieved_at) do
        :ets.insert(cache, {:latest_rates, rates})
        :ets.insert(cache, {:last_updated, retrieved_at})
      end

  `terminate/1`, `historic_rates/2` and `store_historic_rates/3` follow the
  same pattern.
  """

  alias Money.ExchangeRates

  @typedoc "A reference to a retriever's cache storage, returned by `c:init/1`."
  @type cache :: any()

  @doc """
  Initialize the cache when the exchange rates
  retriever is started

  Called with the retriever's `:name`, so that a cache module can maintain
  separate storage per retriever. Must return a `t:cache/0` value that is
  passed to every other callback.
  """
  @callback init(name :: term()) :: cache()

  @doc deprecated: "Use init/1 instead"
  @callback init() :: any()

  @doc """
  Terminate the cache when the retriever process
  stops normally
  """
  @callback terminate(cache()) :: any()

  @doc deprecated: "Use terminate/1 instead"
  @callback terminate() :: any()

  @doc """
  Retrieve the latest exchange rates from the
  cache.
  """
  @callback latest_rates(cache()) ::
              {:ok, ExchangeRates.t()} | {:error, {Exception.t(), String.t()}}

  @doc deprecated: "Use latest_rates/1 instead"
  @callback latest_rates() :: {:ok, ExchangeRates.t()} | {:error, {Exception.t(), String.t()}}

  @doc """
  Retrieve the exchange rates for a given
  date.
  """
  @callback historic_rates(cache(), Date.t()) ::
              {:ok, ExchangeRates.t()} | {:error, {Exception.t(), String.t()}}

  @doc deprecated: "Use historic_rates/2 instead"
  @callback historic_rates(Date.t()) ::
              {:ok, ExchangeRates.t()} | {:error, {Exception.t(), String.t()}}

  @doc """
  Return the timestamp when the exchange rates were last updated.
  """
  @callback last_updated(cache()) :: {:ok, DateTime.t()} | {:error, {Exception.t(), String.t()}}

  @doc deprecated: "Use last_updated/1 instead"
  @callback last_updated() :: {:ok, DateTime.t()} | {:error, {Exception.t(), String.t()}}

  @doc """
  Store the latest exchange rates in the cache.
  """
  @callback store_latest_rates(cache(), ExchangeRates.t(), DateTime.t()) :: :ok

  @doc deprecated: "Use store_latest_rates/3 instead"
  @callback store_latest_rates(ExchangeRates.t(), DateTime.t()) :: :ok

  @doc """
  Store the historic exchange rates for a given
  date in the cache.
  """
  @callback store_historic_rates(cache(), ExchangeRates.t(), Date.t()) :: :ok

  @doc deprecated: "Use store_historic_rates/3 instead"
  @callback store_historic_rates(ExchangeRates.t(), Date.t()) :: :ok

  @optional_callbacks init: 0,
                      terminate: 0,
                      latest_rates: 0,
                      historic_rates: 1,
                      last_updated: 0,
                      store_latest_rates: 2,
                      store_historic_rates: 2
end
