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

  By default exchange rates are retrieved from
  [Open Exchange Rates](http://openexchangerates.org). The retrieval interval
  is configured via the `:exchange_rates_retrieve_every` key (milliseconds):

      config :ex_money,
        exchange_rates_retrieve_every: 300_000

  """

  use GenServer
  require Logger

  @doc deprecated: "Use `Supervisor.start_child/2` on your application's supervisor instead"
  def start(name \\ __MODULE__, config \\ Money.ExchangeRates.config()) do
    GenServer.start_link(__MODULE__, config, name: name)
  end

  @doc deprecated: "Use `Supervisor.terminate_child/2` on your application's supervisor instead"
  def stop(retriever \\ __MODULE__) do
    GenServer.stop(retriever)
  end

  @doc deprecated: "Use `Supervisor.restart_child/2` on your application's supervisor instead"
  def restart(retriever \\ __MODULE__) do
    if pid = GenServer.whereis(retriever), do: GenServer.stop(pid)
    start(retriever)
  end

  @doc deprecated: "Use `Supervisor.delete_child/2` on your application's supervisor instead"
  def delete(retriever \\ __MODULE__) do
    stop(retriever)
  end

  @doc false
  def start_link(opts \\ []) do
    config = Keyword.get(opts, :config, Money.ExchangeRates.config())
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, config, name: name)
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
  @spec latest_rates(GenServer.server()) :: {:ok, map()} | {:error, {Exception.t(), binary}}
  def latest_rates(retriever \\ __MODULE__) do
    case Process.whereis(retriever) do
      nil -> {:error, exchange_rate_service_error()}
      pid -> GenServer.call(pid, :latest_rates)
    end
  end

  @doc """
  Forces retrieval of historic exchange rates for a single date

  * `date` is a `Date.t` or any date-compatible map or struct (`Calendar.date/0`) or

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

  @spec historic_rates(Calendar.date()) :: {:ok, map()} | {:error, {Exception.t(), binary}}
  @spec historic_rates(Date.Range.t()) ::
          [{:ok, map()} | {:error, {Exception.t(), binary}}] | {:error, {Exception.t(), binary}}
  def historic_rates(date_or_range) when is_map(date_or_range) do
    historic_rates(__MODULE__, date_or_range)
  end

  @spec historic_rates(GenServer.server(), Calendar.date()) ::
          {:ok, map()} | {:error, {Exception.t(), binary}}
  def historic_rates(retriever, %Date{calendar: Calendar.ISO} = date)
      when is_atom(retriever) or is_pid(retriever) do
    case Process.whereis(retriever) do
      nil -> {:error, exchange_rate_service_error()}
      pid -> GenServer.call(pid, {:historic_rates, date})
    end
  end

  def historic_rates(retriever, %{year: year, month: month, day: day})
      when is_atom(retriever) or is_pid(retriever) do
    case Date.new(year, month, day) do
      {:ok, date} -> historic_rates(retriever, date)
      error -> error
    end
  end

  @spec historic_rates(GenServer.server(), Date.Range.t()) ::
          [{:ok, map()} | {:error, {Exception.t(), binary}}] | {:error, {Exception.t(), binary}}
  def historic_rates(retriever, %Date.Range{} = range) do
    case Process.whereis(retriever) do
      nil -> {:error, exchange_rate_service_error()}
      _pid -> for date <- range, do: historic_rates(retriever, date)
    end
  end

  @doc """
  Forces retrieval of historic exchange rates for a range of dates

  * `from` is a `Date.t` or any date-compatible map or struct (`Calendar.date/0`).

  * `to` is a `Date.t` or any date-compatible map or struct (`Calendar.date/0`).

  Returns:

  * `{:ok, rates}` if exchange rates request is successfully sent.

  * `{:error, reason}` if the request cannot be sent.

  Sends a message to the exchange rate retrieval process for each
  date in the range `from`..`to` to request historic rates be
  retrieved.

  """
  @spec historic_rates(Calendar.date(), Calendar.date()) ::
          [{:ok, map()} | {:error, {Exception.t(), binary}}] | {:error, {Exception.t(), binary}}
  def historic_rates(from, to) when is_map(from) and is_map(to) do
    historic_rates(__MODULE__, from, to)
  end

  @spec historic_rates(GenServer.server(), Calendar.date(), Calendar.date()) ::
          [{:ok, map()} | {:error, {Exception.t(), binary}}] | {:error, {Exception.t(), binary}}
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
    case Process.whereis(retriever) do
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
    case Process.whereis(retriever) do
      nil -> {:error, exchange_rate_service_error()}
      pid -> GenServer.call(pid, :last_updated)
    end
  end

  @doc """
  Updates the configuration for the Exchange Rate
  Service

  """
  def reconfigure(retriever \\ __MODULE__, %Money.ExchangeRates.Config{} = config) do
    GenServer.call(retriever, {:reconfigure, config})
  end

  @doc """
  Returns the current configuration of the Exchange Rates
  Retrieval service

  """
  def config(retriever \\ __MODULE__) do
    GenServer.call(retriever, :config)
  end

  @doc deprecated:
         "Use `Money.ExchangeRates.HTTP` or the HTTP client of your preference directly instead"
  def retrieve_rates(url, config) when is_list(url) do
    url
    |> List.to_string()
    |> retrieve_rates(config)
  end

  def retrieve_rates(url, config) when is_binary(url) do
    url
    |> Money.ExchangeRates.HTTP.get(verify_peer: Map.get(config, :verify_peer, true))
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

  @doc false
  def init(config) do
    :erlang.process_flag(:trap_exit, true)
    config.cache_module.init()

    if is_integer(config.retrieve_every) do
      log(config, :info, log_init_message(config.retrieve_every))
      schedule_latest_rates_fetch(0)
    end

    if config.preload_historic_rates do
      log(config, :info, "Preloading historic rates for #{inspect(config.preload_historic_rates)}")
      schedule_historic_rates_preload(config.preload_historic_rates, config.cache_module)
    end

    {:ok, config}
  end

  @doc false
  def terminate(:normal, config) do
    config.cache_module.terminate()
  end

  @doc false
  def terminate(:shutdown, config) do
    config.cache_module.terminate()
  end

  @doc false
  def terminate(other, _config) do
    Logger.error("[ExchangeRates.Retriever] Terminate called with unhandled #{inspect(other)}")
  end

  @doc false
  def handle_call(:latest_rates, _from, config) do
    {:reply, retrieve_latest_rates(config), config}
  end

  @doc false
  def handle_call({:historic_rates, date}, _from, config) do
    {:reply, retrieve_historic_rates(date, config), config}
  end

  def handle_call(:latest_rates_available?, _from, config) do
    {:reply, match?({:ok, _rates}, config.cache_module.latest_rates()), config}
  end

  def handle_call(:last_updated, _from, config) do
    {:reply, config.cache_module.last_updated(), config}
  end

  @doc false
  def handle_call({:reconfigure, new_configuration}, _from, config) do
    config.cache_module.terminate()
    {:ok, new_config} = init(new_configuration)
    {:reply, new_config, new_config}
  end

  @doc false
  def handle_call(:config, _from, config) do
    {:reply, config, config}
  end

  @doc false
  def handle_call(:stop, _from, config) do
    {:stop, :normal, :ok, config}
  end

  @doc false
  def handle_call({:stop, reason}, _from, config) do
    {:stop, reason, :ok, config}
  end

  @doc false
  def handle_info(:scheduled_latest_rates_fetch, config) do
    fetch_latest_rates(config)
    schedule_latest_rates_fetch(config.retrieve_every)
    {:noreply, config}
  end

  @doc false
  def handle_info({:historic_rates, %Date{calendar: Calendar.ISO} = date}, config) do
    retrieve_historic_rates(date, config)
    {:noreply, config}
  end

  @doc false
  def handle_info(:stop, config) do
    {:stop, :normal, config}
  end

  @doc false
  def handle_info({:stop, reason}, config) do
    {:stop, reason, config}
  end

  @doc false
  def handle_info(message, config) do
    Logger.error("Invalid message for ExchangeRates.Retriever: #{inspect(message)}")
    {:noreply, config}
  end

  defp retrieve_latest_rates(config) do
    case config.cache_module.latest_rates() do
      {:ok, rates} -> {:ok, rates}
      {:error, _reason} -> fetch_latest_rates(config)
    end
  end

  defp fetch_latest_rates(config) do
    case config.api_module.get_latest_rates(config) do
      {:ok, :not_modified} ->
        log(config, :success, "Retrieved latest exchange rates successfully. Rates unchanged.")
        config.cache_module.latest_rates()

      {:ok, rates} ->
        retrieved_at = DateTime.utc_now()
        config.cache_module.store_latest_rates(rates, retrieved_at)
        apply(config.callback_module, :latest_rates_retrieved, [rates, retrieved_at])
        log(config, :success, "Retrieved latest exchange rates successfully")
        {:ok, rates}

      {:error, reason} ->
        log(config, :failure, "Could not retrieve latest exchange rates: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp retrieve_historic_rates(date, config) do
    case config.cache_module.historic_rates(date) do
      {:ok, rates} -> {:ok, rates}
      {:error, _reason} -> fetch_historic_rates(date, config)
    end
  end

  defp fetch_historic_rates(date, config) do
    case config.api_module.get_historic_rates(date, config) do
      {:ok, :not_modified} ->
        log(config, :success, "Historic exchange rates for #{Date.to_string(date)} unchanged")
        config.cache_module.historic_rates(date)

      {:ok, rates} ->
        config.cache_module.store_historic_rates(rates, date)
        apply(config.callback_module, :historic_rates_retrieved, [rates, date])

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

  defp schedule_latest_rates_fetch(delay_ms) when is_integer(delay_ms) do
    Process.send_after(self(), :scheduled_latest_rates_fetch, delay_ms)
  end

  defp schedule_historic_rates_preload(%Date.Range{} = date_range, cache_module) do
    for date <- date_range do
      schedule_historic_rates_preload(date, cache_module)
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
  defp schedule_historic_rates_preload(%Date{calendar: Calendar.ISO} = date, cache_module) do
    case cache_module.historic_rates(date) do
      {:ok, _rates} ->
        :ok

      {:error, _} ->
        Process.send(self(), {:historic_rates, date}, [])
    end
  end

  defp schedule_historic_rates_preload({%Date{} = from, %Date{} = to}, cache_module) do
    schedule_historic_rates_preload(Date.range(from, to), cache_module)
  end

  defp schedule_historic_rates_preload(date_string, cache_module) when is_binary(date_string) do
    parts = String.split(date_string, "..")

    case parts do
      [date] ->
        schedule_historic_rates_preload(Date.from_iso8601(date), cache_module)

      [from, to] ->
        schedule_historic_rates_preload(
          {Date.from_iso8601(from), Date.from_iso8601(to)},
          cache_module
        )
    end
  end

  # Any non-numeric value, or non-date value means
  # we don't schedule work - ie there is no periodic
  # retrieval
  defp schedule_historic_rates_preload(_, _cache_module) do
    :ok
  end

  @doc false
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
