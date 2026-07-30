defmodule Money.ExchangeRates.Cache.Dets do
  @moduledoc """
  Money.ExchangeRates.Cache implementation for
  :dets
  """

  use Money.ExchangeRates.Cache.EtsDets

  @impl true
  def init(name) do
    path = Path.join(System.tmp_dir!(), ".exchange_rates_#{:erlang.phash2(name)}")
    {:ok, table} = :dets.open_file(name, file: String.to_charlist(path))
    table
  end

  @impl true
  def terminate(table) do
    :dets.close(table)
  end

  defp get(table, key) do
    with info when is_list(info) <- :dets.info(table),
         [{^key, value}] <- :dets.lookup(table, key) do
      value
    else
      _ -> nil
    end
  end

  defp put(table, key, value) do
    :dets.insert(table, {key, value})
    value
  end
end
