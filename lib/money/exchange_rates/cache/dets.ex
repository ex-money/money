defmodule Money.ExchangeRates.Cache.Dets do
  @moduledoc """
  Money.ExchangeRates.Cache implementation for
  :dets
  """

  @behaviour Money.ExchangeRates.Cache

  @ets_table :exchange_rates

  require Logger
  require Money.ExchangeRates.Cache.EtsDets
  Money.ExchangeRates.Cache.EtsDets.define_common_functions()

  @impl true
  def init do
    path = System.tmp_dir!() |> Path.join(".exchange_rates") |> String.to_charlist()
    {:ok, name} = :dets.open_file(@ets_table, file: path)
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
