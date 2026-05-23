defmodule Money.ExchangeRates.Supervisor do
  @moduledoc """
  Functions to manage the starting, stopping,
  deleting and restarting of the Exchange
  Rates Retriever.
  """

  use Supervisor
  alias Money.ExchangeRates

  @child_name ExchangeRates.Retriever

  @doc false
  def start_link do
    Supervisor.start_link(__MODULE__, :ok, name: ExchangeRates.Supervisor)
  end

  @doc """
  Starts the Exchange Rates supervisor and
  optionally starts the exchange rates
  retrieval service as well.

  ## Options

  * `:restart` is a boolean value indicating
    if the supervisor is to be restarted. This is
    typically used to move the supervisor from its
    default position under the `ex_money` supervision
    tree to a different supervision tree. The default
    is `false`

  * `:start_retriever` is a boolean indicating
    if the exchange rates retriever is to be started
    when the supervisor is started. The default is
    defined by the configuration key
    `:auto_start_exchange_rate_service`
  """
  def start_link(options) do
    options = Keyword.merge(default_options(), options)
    if options[:restart], do: stop()
    supervisor = start_link()
    if options[:start_retriever], do: start_retriever!()
    supervisor
  end

  defp default_options do
    [
      restart: false,
      start_retriever: Money.get_env(:auto_start_exchange_rates_service, false, :boolean)
    ]
  end

  @doc """
  Stop the Money.ExchangeRates.Supervisor.

  Unless `ex_money` is configured in `mix.exs` as
  `runtime: false`, the Money.ExchangeRates.Supervisor
  is always started when `ex_money` starts even if the
  config key `:auto_start_exchange_rates_service` is
  set to `false`.


  In some instances an application may require the
  `Money.ExchangeRates.Supervisor` to be started under
  a different supervision tree. In this case it is
  required to call this function first before a new
  configuration is started.

  One use case is when the Exchange Rates service is
  configured with either an API module, a Callback module
  or a Cache module which uses Ecto and therefore it's
  a requirement that Ecto is started first.

  See the README section on "Using Ecto or other applications
  from within the callback module" for an example of how
  to configure the supervisor in this case.
  """
  def stop(supervisor \\ default_supervisor()) do
    Supervisor.terminate_child(supervisor, __MODULE__)
  end

  @doc """
  Returns the name of the default supervisor
  which is `Money.Supervisor`

  """
  def default_supervisor do
    {_, options} =
      Application.spec(:ex_money)
      |> Keyword.get(:mod)

    Keyword.get(options, :name)
  end

  @doc false
  @impl true
  def init(:ok) do
    Supervisor.init([], strategy: :one_for_one)
  end

  @doc """
  Returns a boolean indicating whether the
  retriever process is configured and
  running
  """
  def retriever_running? do
    !!Process.whereis(@child_name)
  end

  @doc """
  Returns the status of the exchange rates
  retriever. The returned value is one of:

  * `:running` if the service is running. In this
    state the valid action is `Money.ExchangeRates.Retriever.stop/0`.

  * `:stopped` if it is stopped. In this state
    the valid actions are `Money.ExchangeRates.Supervisor.restart_retriever/0`
    or `Money.ExchangeRates.Supervisor.delete_retriever/0`.

  * `:not_started` if it is not configured
    in the supervisor and is not running. In
    this state the only valid action is
    `Money.ExchangeRates.Supervisor.start_retriever/1`.

  """
  def retriever_status do
    cond do
      !!Process.whereis(@child_name) -> :running
      configured?(@child_name) -> :stopped
      true -> :not_started
    end
  end

  defp configured?(child) do
    Money.ExchangeRates.Supervisor
    |> Supervisor.which_children()
    |> Enum.any?(fn {name, _pid, _type, _args} -> name == child end)
  end

  @doc """
  Starts the exchange rates retriever.

  ## Arguments

  * `config` is a `t:Money.ExchangeRates.Config.t/0`
    struct returned by `Money.ExchangeRates.config/0`
    and adjusted as required. The default is
    `Money.ExchangeRates.config/0`.

  """
  def start_retriever(config \\ ExchangeRates.config()) do
    Supervisor.start_child(__MODULE__, retriever_spec(config))
  end

  @doc """
  Stop the exchange rates retriever.
  """
  def stop_retriever do
    Supervisor.terminate_child(__MODULE__, @child_name)
  end

  @doc """
  Restarts a stopped retriever.

  See also `Money.ExchangeRates.Retriever.stop/0`
  """
  def restart_retriever do
    Supervisor.restart_child(__MODULE__, @child_name)
  end

  @doc """
  Deletes the retriever child specification from
  the exchange rates supervisor.

  This is primarily of use if you want to change
  the configuration of the retriever after it is
  stopped and before it is restarted.

  In this situation the sequence of calls would be:

  ```
  iex> Money.ExchangeRates.Retriever.stop
  iex> Money.ExchangeRates.Retriever.delete
  iex> Money.ExchangeRates.Retriever.start(config)
  ```

  """
  def delete_retriever do
    Supervisor.delete_child(__MODULE__, @child_name)
  end

  defp retriever_spec(config) do
    %{id: @child_name, start: {@child_name, :start_link, [@child_name, config]}}
  end

  defp start_retriever! do
    case ExchangeRates.Retriever.start() do
      {:ok, _pid} -> :ok
      {:error, reason} -> raise "Unhandled error starting retriever; #{inspect(reason)}"
    end
  end
end
