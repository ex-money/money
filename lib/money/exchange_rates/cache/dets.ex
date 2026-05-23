defmodule Money.ExchangeRates.Cache.Dets do
  @moduledoc """
  Money.ExchangeRates.Cache implementation for
  :dets
  """

  @behaviour Money.ExchangeRates.Cache

  @ets_table :exchange_rates
  @dets_path Path.join(:code.priv_dir(:ex_money), ".exchange_rates")
             |> String.to_charlist()

  require Logger
  require Money.ExchangeRates.Cache.EtsDets
  Money.ExchangeRates.Cache.EtsDets.define_common_functions()

  @impl true
  def init do
    {:ok, name} = :dets.open_file(@ets_table, file: @dets_path)
    name
  end

  @impl true
  def terminate do
    :dets.close(@ets_table)
  end

  def get(key) do
    case :dets.lookup(@ets_table, key) do
      [{^key, value}] -> value
      [] -> nil
    end
  end

  def put(key, value) do
    :dets.insert(@ets_table, {key, value})
    value
  end
end
