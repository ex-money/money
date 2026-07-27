defmodule Money.ExchangeRates.Cache.Ets do
  @moduledoc """
  Money.ExchangeRates.Cache implementation for
  :ets
  """

  use Money.ExchangeRates.Cache.EtsDets

  @impl true
  def init(_name) do
    :ets.new(__MODULE__, [:public, read_concurrency: true])
  end

  @impl true
  def terminate(tid) do
    # Delete the table so a `reconfigure` (terminate + re-init on the still-alive
    # retriever) does not orphan it. On process death the VM reclaims it anyway.
    :ets.delete(tid)
    :ok
  end

  defp get(tid, key) do
    case :ets.lookup(tid, key) do
      [{^key, value}] -> value
      _ -> nil
    end
  end

  defp put(tid, key, value) do
    :ets.insert(tid, {key, value})
    value
  end
end
