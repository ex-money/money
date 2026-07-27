defmodule Money.ExchangeRates.Retriever do
  @moduledoc """
  A `GenServer` that retrieves exchange rates from a configured API module on a
  periodic or on-demand basis.

  Add it to your application's supervision tree to enable the exchange rates
  service:

      children = [
        MyApp.Repo,
        Money.ExchangeRates.Retriever
      ]

  To start with a custom configuration:

      children = [
        {Money.ExchangeRates.Retriever, [config: my_config]}
      ]

  Multiple named retrievers can be started independently, each backed by a
  different API source:

      children = [
        {Money.ExchangeRates.Retriever, [name: :open_exchange_rates, config: oxr_config]},
        {Money.ExchangeRates.Retriever, [name: :fixer, config: fixer_config]}
      ]

      Money.ExchangeRates.Retriever.latest_rates(:open_exchange_rates)
      Money.ExchangeRates.Retriever.historic_rates(:fixer, ~D[2024-01-01])

  > #### Named retrievers each get their own cache {: .info}
  >
  > The bundled cache implementations (`Money.ExchangeRates.Cache.Ets` and
  > `Money.ExchangeRates.Cache.Dets`) key their storage (the ETS table name /
  > DETS file path) by the retriever's `:name`, so multiple named retrievers
  > can safely share the same `cache_module` - each gets its own separated
  > cache.
  >
  > A custom cache module that implements only the deprecated,
  > lower-arity `Money.ExchangeRates.Cache` callbacks behaves as a single,
  > module-wide cache instead. Named retrievers sharing such a module will
  > overwrite each other's rates; give each its own `cache_module` in that
  > case.

  By default exchange rates are retrieved from
  [Open Exchange Rates](http://openexchangerates.org). The retrieval interval
  is configured via the `:exchange_rates_retrieve_every` key (milliseconds):

      config :ex_money,
        exchange_rates_retrieve_every: 300_000

  """

  use GenServer
  require Logger

  alias Money.ExchangeRates

  # A `GenServer.server/0`: a pid, a locally registered atom, or a
  # `{:global, _}` / `{:via, _, _}` / `{atom, node}` tuple.
  defguardp is_retriever(name) when is_atom(name) or is_pid(name) or is_tuple(name)

  @doc deprecated: "Use `Supervisor.start_child/2` on your application's supervisor instead"
  @spec start(GenServer.name(), ExchangeRates.Config.t()) :: GenServer.on_start()
  def start(name \\ __MODULE__, config \\ ExchangeRates.config()) do
    GenServer.start_link(__MODULE__, %{config: config, name: name}, name: name)
  end

  @doc deprecated: "Use `Supervisor.terminate_child/2` on your application's supervisor instead"
  @spec stop(GenServer.server()) :: :ok
  def stop(retriever \\ __MODULE__) do
    GenServer.stop(retriever)
  end

  @doc deprecated: "Use `Supervisor.restart_child/2` on your application's supervisor instead"
  @spec restart(GenServer.name()) :: GenServer.on_start()
  def restart(retriever \\ __MODULE__) do
    if pid = GenServer.whereis(retriever), do: GenServer.stop(pid)
    start(retriever)
  end

  @doc deprecated: "Use `Supervisor.delete_child/2` on your application's supervisor instead"
  @spec delete(GenServer.server()) :: :ok
  def delete(retriever \\ __MODULE__) do
    stop(retriever)
  end

  @doc false
  @spec start_link(Keyword.t()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    config = Keyword.get(opts, :config, ExchangeRates.config())
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, %{config: config, name: name}, name: name)
  end

  @doc """
  Forces retrieval of the latest exchange rates

  Sends a message to the exchange rate retrieval worker to request
  current rates be retrieved and stored.

  Returns:

  * `{:ok, rates}` if exchange rates request is successfully sent.

  * `{:error, reason}` if the request cannot be sent.

  This function does not return exchange rates, for that see
  `Money.ExchangeRates.latest_rates/0` or
  `Money.ExchangeRates.historic_rates/1`.

  """
  @spec latest_rates(GenServer.server()) ::
          {:ok, ExchangeRates.t()} | {:error, {Exception.t(), binary}}
  def latest_rates(retriever \\ __MODULE__) do
    case GenServer.whereis(retriever) do
      nil -> {:error, exchange_rate_service_error()}
      pid -> GenServer.call(pid, :latest_rates)
    end
  end

  @doc """
  Forces retrieval of historic exchange rates for a single date

  * `date` is a `t:Date.t/0` or any date-compatible map or struct (`t:Calendar.date/0`) or

  * a `Date.Range.t` created by `Date.range/2` that specifies a
    range of dates to retrieve

  Returns:

  * `{:ok, rates}` if exchange rates request is successfully sent.

  * `{:error, reason}` if the request cannot be sent.

  Sends a message to the exchange rate retrieval worker to request
  historic rates for a specified date or range be retrieved and
  stored.

  This function does not return exchange rates, for that see
  `Money.ExchangeRates.latest_rates/0` or
  `Money.ExchangeRates.historic_rates/1`.

  """

  @spec historic_rates(Calendar.date()) ::
          {:ok, ExchangeRates.t()} | {:error, {Exception.t(), binary}}
  @spec historic_rates(Date.Range.t()) ::
          [{:ok, ExchangeRates.t()} | {:error, {Exception.t(), binary}}]
          | {:error, {Exception.t(), binary}}
  def historic_rates(date_or_range) when is_map(date_or_range) do
    historic_rates(__MODULE__, date_or_range)
  end

  @spec historic_rates(GenServer.server(), Calendar.date()) ::
          {:ok, ExchangeRates.t()} | {:error, {Exception.t(), binary}}
  def historic_rates(retriever, %Date{calendar: Calendar.ISO} = date)
      when is_retriever(retriever) do
    case GenServer.whereis(retriever) do
      nil -> {:error, exchange_rate_service_error()}
      pid -> GenServer.call(pid, {:historic_rates, date})
    end
  end

  def historic_rates(retriever, %{year: year, month: month, day: day})
      when is_retriever(retriever) do
    case Date.new(year, month, day) do
      {:ok, date} -> historic_rates(retriever, date)
      error -> error
    end
  end

  @spec historic_rates(GenServer.server(), Date.Range.t()) ::
          [{:ok, ExchangeRates.t()} | {:error, {Exception.t(), binary}}]
          | {:error, {Exception.t(), binary}}
  def historic_rates(retriever, %Date.Range{} = range) do
    case GenServer.whereis(retriever) do
      nil -> {:error, exchange_rate_service_error()}
      _pid -> for date <- range, do: historic_rates(retriever, date)
    end
  end

  @doc """
  Forces retrieval of historic exchange rates for a range of dates

  * `from` is a `t:Date.t/0` or any date-compatible map or struct (`t:Calendar.date/0`).

  * `to` is a `t:Date.t/0` or any date-compatible map or struct (`t:Calendar.date/0`).

  Returns:

  * `{:ok, rates}` if exchange rates request is successfully sent.

  * `{:error, reason}` if the request cannot be sent.

  Sends a message to the exchange rate retrieval process for each
  date in the range `from`..`to` to request historic rates be
  retrieved.

  """
  @spec historic_rates(Calendar.date(), Calendar.date()) ::
          [{:ok, ExchangeRates.t()} | {:error, {Exception.t(), binary}}]
          | {:error, {Exception.t(), binary}}
  def historic_rates(from, to) when is_map(from) and is_map(to) do
    historic_rates(__MODULE__, from, to)
  end

  @spec historic_rates(GenServer.server(), Calendar.date(), Calendar.date()) ::
          [{:ok, ExchangeRates.t()} | {:error, {Exception.t(), binary}}]
          | {:error, {Exception.t(), binary}}
  def historic_rates(
        retriever,
        %Date{calendar: Calendar.ISO} = from,
        %Date{calendar: Calendar.ISO} = to
      ) do
    range = Date.range(from, to)
    historic_rates(retriever, range)
  end

  def historic_rates(retriever, %{year: y1, month: m1, day: d1}, %{year: y2, month: m2, day: d2}) do
    with {:ok, from} <- Date.new(y1, m1, d1),
         {:ok, to} <- Date.new(y2, m2, d2) do
      historic_rates(retriever, from, to)
    end
  end

  @doc """
  Returns `true` if the latest exchange rates are available in the cache,
  `false` otherwise.

  Returns `false` when the retriever is not running, even if the cache table
  still exists.
  """
  @spec latest_rates_available?(GenServer.server()) :: boolean
  def latest_rates_available?(retriever \\ __MODULE__) do
    case GenServer.whereis(retriever) do
      nil -> false
      pid -> GenServer.call(pid, :latest_rates_available?)
    end
  end

  @doc """
  Returns the timestamp of the last successful exchange rate retrieval.

  Returns:

  * `{:ok, datetime}` if rates have been retrieved at least once.

  * `{:error, reason}` if the retriever is not running or no retrieval has
    occurred yet.

  """
  @spec last_updated(GenServer.server()) :: {:ok, DateTime.t()} | {:error, {Exception.t(), binary}}
  def last_updated(retriever \\ __MODULE__) do
    case GenServer.whereis(retriever) do
      nil -> {:error, exchange_rate_service_error()}
      pid -> GenServer.call(pid, :last_updated)
    end
  end

  @doc """
  Updates the configuration for the Exchange Rate
  Service

  """
  @spec reconfigure(GenServer.name(), ExchangeRates.Config.t()) ::
          ExchangeRates.Config.t() | {:error, {module(), String.t()}}
  def reconfigure(retriever \\ __MODULE__, %ExchangeRates.Config{} = config) do
    case GenServer.whereis(retriever) do
      nil -> {:error, exchange_rate_service_error()}
      pid -> GenServer.call(pid, {:reconfigure, config})
    end
  end

  @doc """
  Returns the current configuration of the Exchange Rates
  Retrieval service

  """
  @spec config(GenServer.name()) ::
          ExchangeRates.Config.t() | {:error, {module(), String.t()}}
  def config(retriever \\ __MODULE__) do
    case GenServer.whereis(retriever) do
      nil -> {:error, exchange_rate_service_error()}
      pid -> GenServer.call(pid, :config)
    end
  end

  @doc deprecated:
         "Use `Money.ExchangeRates.HTTP` or the HTTP client of your preference directly instead"
  @spec retrieve_rates(charlist() | String.t(), ExchangeRates.Config.t()) ::
          {:ok, map() | :not_modified} | {:error, term()}
  def retrieve_rates(url, config) when is_list(url) do
    url
    |> List.to_string()
    |> retrieve_rates(config)
  end

  def retrieve_rates(url, config) when is_binary(url) do
    url
    |> ExchangeRates.HTTP.get(verify_peer: Map.get(config, :verify_peer, true))
    |> process_response(config)
  end

  defp process_response({:ok, body}, config) when is_binary(body) or is_list(body) do
    {:ok, config.api_module.decode_rates(body)}
  end

  defp process_response({:ok, :not_modified}, _config) do
    {:ok, :not_modified}
  end

  defp process_response({:error, reason}, _config) do
    {:error, reason}
  end

  #
  # Server implementation
  #

  @impl true
  def init(%{config: config, name: name} = state) do
    :erlang.process_flag(:trap_exit, true)
    cache = call_cache_module(config, :init, [name])
    state = Map.put(state, :cache, cache)

    if is_integer(config.retrieve_every) do
      log(config, :info, log_init_message(config.retrieve_every))
      schedule_latest_rates_fetch(0)
    end

    if config.preload_historic_rates do
      log(config, :info, "Preloading historic rates for #{inspect(config.preload_historic_rates)}")
      schedule_historic_rates_preload(config.preload_historic_rates, state)
    end

    {:ok, state}
  end

  @impl true
  def terminate(:normal, state) do
    call_cache_module(state.config, :terminate, [state.cache])
  end

  @impl true
  def terminate(:shutdown, state) do
    call_cache_module(state.config, :terminate, [state.cache])
  end

  @impl true
  def terminate(other, _state) do
    Logger.error("[ExchangeRates.Retriever] Terminate called with unhandled #{inspect(other)}")
  end

  @impl true
  def handle_call(:latest_rates, _from, state) do
    {:reply, retrieve_latest_rates(state), state}
  end

  @impl true
  def handle_call({:historic_rates, date}, _from, state) do
    {:reply, retrieve_historic_rates(date, state), state}
  end

  def handle_call(:latest_rates_available?, _from, state) do
    {:reply, match?({:ok, _rates}, call_cache_module(state.config, :latest_rates, [state.cache])),
     state}
  end

  def handle_call(:last_updated, _from, state) do
    {:reply, call_cache_module(state.config, :last_updated, [state.cache]), state}
  end

  @impl true
  def handle_call({:reconfigure, new_configuration}, _from, state) do
    call_cache_module(state.config, :terminate, [state.cache])
    {:ok, new_state} = init(%{config: new_configuration, name: state.name})
    {:reply, new_state.config, new_state}
  end

  @impl true
  def handle_call(:config, _from, state) do
    {:reply, state.config, state}
  end

  @impl true
  def handle_call(:stop, _from, state) do
    {:stop, :normal, :ok, state}
  end

  @impl true
  def handle_call({:stop, reason}, _from, state) do
    {:stop, reason, :ok, state}
  end

  @impl true
  def handle_info(:scheduled_latest_rates_fetch, state) do
    fetch_latest_rates(state)
    schedule_latest_rates_fetch(state.config.retrieve_every)
    {:noreply, state}
  end

  @impl true
  def handle_info({:historic_rates, %Date{calendar: Calendar.ISO} = date}, state) do
    retrieve_historic_rates(date, state)
    {:noreply, state}
  end

  @impl true
  def handle_info(:stop, state) do
    {:stop, :normal, state}
  end

  @impl true
  def handle_info({:stop, reason}, state) do
    {:stop, reason, state}
  end

  @impl true
  def handle_info(message, state) do
    Logger.error("Invalid message for ExchangeRates.Retriever: #{inspect(message)}")
    {:noreply, state}
  end

  defp retrieve_latest_rates(state) do
    case call_cache_module(state.config, :latest_rates, [state.cache]) do
      {:ok, rates} -> {:ok, rates}
      {:error, _reason} -> fetch_latest_rates(state)
    end
  end

  defp fetch_latest_rates(%{config: config} = state) do
    case call_api_module(config, :get_latest_rates, [config]) do
      {:ok, :not_modified} ->
        log(config, :success, "Retrieved latest exchange rates successfully. Rates unchanged.")
        call_cache_module(config, :latest_rates, [state.cache])

      {:ok, rates} ->
        retrieved_at = DateTime.utc_now()
        call_cache_module(config, :store_latest_rates, [state.cache, rates, retrieved_at])
        run_callback(config, :latest_rates_retrieved, [rates, retrieved_at])
        log(config, :success, "Retrieved latest exchange rates successfully")
        {:ok, rates}

      {:error, reason} ->
        log(config, :failure, "Could not retrieve latest exchange rates: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp retrieve_historic_rates(date, state) do
    case call_cache_module(state.config, :historic_rates, [state.cache, date]) do
      {:ok, rates} -> {:ok, rates}
      {:error, _reason} -> fetch_historic_rates(date, state)
    end
  end

  defp fetch_historic_rates(date, %{config: config} = state) do
    case call_api_module(config, :get_historic_rates, [date, config]) do
      {:ok, :not_modified} ->
        log(config, :success, "Historic exchange rates for #{Date.to_string(date)} unchanged")
        call_cache_module(config, :historic_rates, [state.cache, date])

      {:ok, rates} ->
        call_cache_module(config, :store_historic_rates, [state.cache, rates, date])
        run_callback(config, :historic_rates_retrieved, [rates, date])

        log(
          config,
          :success,
          "Retrieved historic exchange rates for #{Date.to_string(date)} successfully"
        )

        {:ok, rates}

      {:error, reason} ->
        log(
          config,
          :failure,
          "Could not retrieve historic exchange rates " <>
            "for #{Date.to_string(date)}: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  # Calls a `Money.ExchangeRates.Cache` operation on `cache_module`. `args` is
  # the argument list for the current, cache-taking arity (cache reference or
  # retriever name first); if `cache_module` doesn't export that arity it
  # falls back to the deprecated, module-wide singleton arity by dropping
  # that leading argument.
  defp call_cache_module(%{cache_module: cache_module}, fun, args) do
    Code.ensure_loaded!(cache_module)

    if function_exported?(cache_module, fun, length(args)) do
      apply(cache_module, fun, args)
    else
      apply(cache_module, fun, tl(args))
    end
  end

  # The API module is user-configured code that performs network requests and
  # decodes provider responses — a true system boundary, so `rescue` is
  # appropriate here. An exception raised there (for example while decoding a
  # malformed provider response) must not crash the retriever: `init/1`
  # schedules an immediate fetch after a restart, so a deterministic raise
  # would put the retriever into a rapid crash loop that can exhaust the
  # supervisor's restart intensity and take down the host application.
  defp call_api_module(config, function_name, arguments) do
    apply(config.api_module, function_name, arguments)
  rescue
    exception ->
      {:error,
       {Money.ExchangeRateError,
        "#{inspect(config.api_module)}.#{function_name} raised " <>
          "#{inspect(exception.__struct__)}: #{Exception.message(exception)}"}}
  end

  # Callbacks are user-configured code invoked after a successful retrieval —
  # also a system boundary. A raising callback must neither crash the
  # retriever nor discard the successfully retrieved (and already cached)
  # rates, so the exception is logged and retrieval continues.
  defp run_callback(config, function_name, arguments) do
    apply(config.callback_module, function_name, arguments)
  rescue
    exception ->
      log(
        config,
        :failure,
        "#{inspect(config.callback_module)}.#{function_name} raised " <>
          "#{inspect(exception.__struct__)}: #{Exception.message(exception)}"
      )

      :ok
  end

  defp schedule_latest_rates_fetch(delay_ms) when is_integer(delay_ms) do
    Process.send_after(self(), :scheduled_latest_rates_fetch, delay_ms)
  end

  defp schedule_historic_rates_preload(%Date.Range{} = date_range, state) do
    for date <- date_range do
      schedule_historic_rates_preload(date, state)
    end
  end

  # Don't retrieve historic rates if they are
  # already cached.  Note that this is only
  # called at retriever initialization, not
  # through the public api.
  #
  # This depends on:
  # 1. The cache is persistent, like Cache.Dets
  # 2. The assumption that historic rates don't change
  # A persistent cache will reduce the number of
  # external API calls and it means the cache
  # will survive restarts both intentional and
  # unintentional
  defp schedule_historic_rates_preload(%Date{calendar: Calendar.ISO} = date, state) do
    case call_cache_module(state.config, :historic_rates, [state.cache, date]) do
      {:ok, _rates} ->
        :ok

      {:error, _} ->
        Process.send(self(), {:historic_rates, date}, [])
    end
  end

  defp schedule_historic_rates_preload({%Date{} = from, %Date{} = to}, state) do
    schedule_historic_rates_preload(Date.range(from, to), state)
  end

  defp schedule_historic_rates_preload(date_string, state) when is_binary(date_string) do
    parts = String.split(date_string, "..")

    case parts do
      [date] ->
        schedule_historic_rates_preload(Date.from_iso8601(date), state)

      [from, to] ->
        schedule_historic_rates_preload(
          {Date.from_iso8601(from), Date.from_iso8601(to)},
          state
        )
    end
  end

  # Any non-numeric value, or non-date value means
  # we don't schedule work - ie there is no periodic
  # retrieval
  defp schedule_historic_rates_preload(_, _state) do
    :ok
  end

  @doc false
  @spec log(map(), atom(), String.t()) :: :ok | nil
  def log(%{log_levels: log_levels}, key, message) do
    case Map.get(log_levels, key) do
      nil ->
        nil

      log_level ->
        Logger.log(log_level, message)
    end
  end

  defp log_init_message(every) do
    {every, plural_every} = seconds(every)
    "Exchange Rates will be retrieved now and then every #{every} #{plural_every}."
  end

  defp seconds(milliseconds) do
    seconds = div(milliseconds, 1000)
    plural = if seconds == 1, do: "second", else: "seconds"

    {:ok, formatted_seconds} =
      Localize.Number.to_string(seconds)

    {formatted_seconds, plural}
  end

  defp exchange_rate_service_error do
    {Money.ExchangeRateError, "Exchange rate service does not appear to be running"}
  end
end
