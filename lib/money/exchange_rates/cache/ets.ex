defmodule Money.ExchangeRates.Cache.Ets do
  @moduledoc """
  Money.ExchangeRates.Cache implementation for
  :ets
  """

  @behaviour Money.ExchangeRates.Cache

  @ets_table :exchange_rates

  require Logger
  require Money.ExchangeRates.Cache.EtsDets
  Money.ExchangeRates.Cache.EtsDets.define_common_functions()

  @impl true
  def init do
    if :ets.info(@ets_table) == :undefined do
      :ets.new(@ets_table, [
        :named_table,
        :public,
        read_concurrency: true
      ])
    else
      @ets_table
    end
  end

  @impl true
  def terminate do
    :ok
  end

  def get(key) do
    case :ets.lookup(@ets_table, key) do
      [{^key, value}] -> value
      [] -> nil
    end
  end

  def put(key, value) do
    :ets.insert(@ets_table, {key, value})
    value
  end
end
