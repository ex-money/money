defmodule Money.ExchangeRates.Supervisor do
  @moduledoc deprecated: """
             `Money.ExchangeRates.Supervisor` is deprecated. Add `Money.ExchangeRates.Retriever`
             directly to your application's supervision tree instead:

             ```
             children = [
               Money.ExchangeRates.Retriever
             ]
             ```

             If your callback module depends on other applications being started first, position
             `Money.ExchangeRates.Retriever` after those dependencies in the children list.
             """

  use Supervisor
  alias Money.ExchangeRates.Retriever

  @doc deprecated: "Add `Money.ExchangeRates.Retriever` to your supervision tree directly."
  def start_link(options) do
    if Keyword.get(options, :restart, false), do: stop()
    Supervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc deprecated: "Manage `Money.ExchangeRates.Retriever` directly in your supervision tree."
  def stop(supervisor \\ default_supervisor()) do
    Supervisor.terminate_child(supervisor, __MODULE__)
  end

  @doc false
  def default_supervisor do
    {_, options} =
      Application.spec(:ex_money)
      |> Keyword.get(:mod)

    Keyword.get(options, :name)
  end

  @doc false
  @impl true
  def init(:ok) do
    Supervisor.init([Retriever], strategy: :one_for_one)
  end

  @doc deprecated: "Use `Process.whereis(Money.ExchangeRates.Retriever)` directly."
  def retriever_running? do
    !!Process.whereis(Retriever)
  end

  @doc deprecated:
         "Use `Process.whereis(Money.ExchangeRates.Retriever)` to check if the retriever is running."
  def retriever_status do
    cond do
      !!Process.whereis(Retriever) -> :running
      configured?(Retriever) -> :stopped
      true -> :not_started
    end
  end

  defp configured?(child) do
    Money.ExchangeRates.Supervisor
    |> Supervisor.which_children()
    |> Enum.any?(fn {name, _pid, _type, _args} -> name == child end)
  end

  @doc deprecated: "Add `Money.ExchangeRates.Retriever` to your supervision tree directly."
  def start_retriever(config \\ Money.ExchangeRates.config()) do
    Supervisor.start_child(__MODULE__, {Retriever, [config: config]})
  end

  @doc deprecated:
         "Migrate to managing `Money.ExchangeRates.Retriever` in your own supervision tree, then use your supervisor's `terminate_child/2`."
  def stop_retriever do
    Supervisor.terminate_child(__MODULE__, Retriever)
  end

  @doc deprecated:
         "Migrate to managing `Money.ExchangeRates.Retriever` in your own supervision tree, then use your supervisor's `restart_child/2`."
  def restart_retriever do
    Supervisor.restart_child(__MODULE__, Retriever)
  end

  @doc deprecated:
         "Migrate to managing `Money.ExchangeRates.Retriever` in your own supervision tree, then use your supervisor's `delete_child/2`."
  def delete_retriever do
    Supervisor.delete_child(__MODULE__, Retriever)
  end
end
