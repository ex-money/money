defmodule Money.ExchangeRates.RetrieverTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Money.ExchangeRates.Retriever

  doctest Retriever

  # A `Money.ExchangeRates.Cache` implementation using only the deprecated,
  # arity-0 (module-wide singleton) callbacks, to prove the retriever still
  # works against a cache module written for the pre-named-retriever API.
  # Static, cache-always-misses values keep this focused on dispatch, not
  # on being a real cache.
  defmodule LegacyCacheMock do
    @moduledoc false
    @behaviour Money.ExchangeRates.Cache

    @impl true
    def init, do: :ok

    @impl true
    def terminate, do: :ok

    @impl true
    def latest_rates, do: {:error, {Money.ExchangeRateError, "No exchange rates were found"}}

    @impl true
    def historic_rates(_date),
      do: {:error, {Money.ExchangeRateError, "No exchange rates were found"}}

    @impl true
    def last_updated, do: {:error, {Money.ExchangeRateError, "Last updated date is not known"}}

    @impl true
    def store_latest_rates(_rates, _retrieved_at), do: :ok

    @impl true
    def store_historic_rates(_rates, _date), do: :ok
  end

  setup do
    Application.put_env(:ex_money, :exchange_rates_http_client, Money.ExchangeRatesHttpMock)
    start_supervised!(Retriever)

    on_exit(fn -> Application.delete_env(:ex_money, :exchange_rates_http_client) end)

    {:ok, config: Money.ExchangeRates.default_config()}
  end

  describe "retrieve_rates/2" do
    test "returns decoded rates on success", %{config: config} do
      assert {:ok, rates} = Retriever.retrieve_rates("http://success.example.com", config)

      assert rates == %{
               AUD: Decimal.from_float(1.5),
               EUR: Decimal.from_float(0.9),
               USD: Decimal.from_float(1.0)
             }
    end

    test "returns an error tuple on HTTP failure", %{config: config} do
      assert {:error, {Money.ExchangeRateError, ":nxdomain"}} =
               Retriever.retrieve_rates("http://error.example.com", config)
    end
  end

  describe "historic_rates/1" do
    test "returns rates for a single date" do
      assert Retriever.historic_rates(~D[2017-01-01]) ==
               {:ok, %{AUD: Decimal.new("0.5"), EUR: Decimal.new("1.1"), USD: Decimal.new("0.7")}}
    end

    test "returns an error for a date with no available rates" do
      assert Retriever.historic_rates(~D[2017-01-03]) ==
               {:error, {Money.ExchangeRateError, "No exchange rates for 2017-01-03 were found"}}
    end

    test "returns an error when the service is not running" do
      stop_supervised(Retriever)

      assert Retriever.historic_rates(~D[2017-01-01]) ==
               {:error,
                {Money.ExchangeRateError, "Exchange rate service does not appear to be running"}}
    end

    test "returns a list of results for each date in the range" do
      range = Date.range(~D[2017-01-01], ~D[2017-01-02])

      assert Retriever.historic_rates(range) ==
               [
                 {:ok,
                  %{AUD: Decimal.new("0.5"), EUR: Decimal.new("1.1"), USD: Decimal.new("0.7")}},
                 {:ok, %{AUD: Decimal.new("0.4"), EUR: Decimal.new("0.9"), USD: Decimal.new("0.6")}}
               ]
    end

    test "returns an error when the service is not running for a range" do
      stop_supervised(Retriever)

      range = Date.range(~D[2017-01-01], ~D[2017-01-02])

      assert Retriever.historic_rates(range) ==
               {:error,
                {Money.ExchangeRateError, "Exchange rate service does not appear to be running"}}
    end

    test "returns mixed results for a range that includes a date with no available rates" do
      range = Date.range(~D[2017-01-02], ~D[2017-01-03])

      assert Retriever.historic_rates(range) == [
               {:ok, %{AUD: Decimal.new("0.4"), EUR: Decimal.new("0.9"), USD: Decimal.new("0.6")}},
               {:error, {Money.ExchangeRateError, "No exchange rates for 2017-01-03 were found"}}
             ]
    end

    test "accepts any date-compatible struct for a single date" do
      assert Retriever.historic_rates(~N[2017-01-01 00:00:00]) ==
               {:ok, %{AUD: Decimal.new("0.5"), EUR: Decimal.new("1.1"), USD: Decimal.new("0.7")}}
    end

    test "returns an error for an invalid date-compatible struct" do
      assert Retriever.historic_rates(%{year: 2017, month: 13, day: 1}) == {:error, :invalid_date}
    end
  end

  describe "historic_rates/2" do
    test "returns a list of results for each date in the range" do
      assert Retriever.historic_rates(~D[2017-01-01], ~D[2017-01-02]) ==
               [
                 {:ok,
                  %{AUD: Decimal.new("0.5"), EUR: Decimal.new("1.1"), USD: Decimal.new("0.7")}},
                 {:ok, %{AUD: Decimal.new("0.4"), EUR: Decimal.new("0.9"), USD: Decimal.new("0.6")}}
               ]
    end

    test "a range of one date returns a single-element list" do
      assert Retriever.historic_rates(~D[2017-01-01], ~D[2017-01-01]) ==
               [{:ok, %{AUD: Decimal.new("0.5"), EUR: Decimal.new("1.1"), USD: Decimal.new("0.7")}}]
    end

    test "accepts any date-compatible struct" do
      from = ~N[2017-01-01 00:00:00]
      to = ~N[2017-01-02 00:00:00]

      assert [{:ok, _rates1}, {:ok, _rates2}] = Retriever.historic_rates(from, to)
    end

    test "includes error tuples for dates with no available rates" do
      assert [
               {:ok, _rates},
               {:error, {Money.ExchangeRateError, "No exchange rates for 2017-01-03 were found"}}
             ] = Retriever.historic_rates(~D[2017-01-02], ~D[2017-01-03])
    end

    test "returns an error when the service is not running" do
      stop_supervised(Retriever)

      assert Retriever.historic_rates(~D[2017-01-01], ~D[2017-01-02]) ==
               {:error,
                {Money.ExchangeRateError, "Exchange rate service does not appear to be running"}}
    end

    test "returns an error for an invalid from date" do
      assert Retriever.historic_rates(%{year: 2017, month: 13, day: 1}, ~N[2017-01-02 00:00:00]) ==
               {:error, :invalid_date}
    end

    test "returns an error for an invalid to date" do
      assert Retriever.historic_rates(~N[2017-01-01 00:00:00], %{year: 2017, month: 13, day: 1}) ==
               {:error, :invalid_date}
    end
  end

  describe "reconfigure/1" do
    setup do
      {:ok, config: Retriever.config()}
    end

    test "config/0 reflects the updated field after reconfigure", %{config: config} do
      new_config = %{config | callback_module: Money.ExchangeRatesCallbackMock}

      Retriever.reconfigure(new_config)

      assert Retriever.config().callback_module == Money.ExchangeRatesCallbackMock
    end

    test "only the changed field differs from the previous config", %{config: config} do
      new_log_levels = %{success: :debug, failure: :error, info: :debug}
      new_config = %{config | log_levels: new_log_levels}

      Retriever.reconfigure(new_config)

      running = Retriever.config()
      assert running.log_levels == new_log_levels
      assert running.api_module == config.api_module
      assert running.cache_module == config.cache_module
    end
  end

  describe "config/1 and reconfigure/2 when the retriever is not running" do
    test "config/1 returns an error tuple rather than exiting" do
      assert Retriever.config(:no_such_retriever) ==
               {:error,
                {Money.ExchangeRateError, "Exchange rate service does not appear to be running"}}
    end

    test "reconfigure/2 returns an error tuple rather than exiting" do
      config = Money.ExchangeRates.default_config()

      assert Retriever.reconfigure(:no_such_retriever, config) ==
               {:error,
                {Money.ExchangeRateError, "Exchange rate service does not appear to be running"}}
    end
  end

  describe "deprecated lifecycle API" do
    test "start/2 starts a named retriever, restart/1 replaces it and delete/1 stops it" do
      # These functions link the retriever to the test process; trap exits so
      # their normal shutdowns arrive as messages rather than killing the test.
      Process.flag(:trap_exit, true)
      name = :deprecated_api_retriever

      assert {:ok, pid1} = Retriever.start(name)
      assert Process.whereis(name) == pid1

      assert {:ok, pid2} = Retriever.restart(name)
      assert pid2 != pid1
      assert Process.alive?(pid2)

      assert :ok = Retriever.delete(name)
      refute Process.whereis(name)
    end
  end

  describe "lifecycle messages" do
    setup do
      Process.flag(:trap_exit, true)
      {:ok, pid} = Retriever.start(:"lifecycle_#{System.unique_integer([:positive])}")
      {:ok, pid: pid}
    end

    test "handle_info(:stop) stops the retriever normally", %{pid: pid} do
      ref = Process.monitor(pid)
      send(pid, :stop)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
    end

    test "handle_info({:stop, reason}) stops with the given reason", %{pid: pid} do
      ref = Process.monitor(pid)
      send(pid, {:stop, :shutdown})
      assert_receive {:DOWN, ^ref, :process, ^pid, :shutdown}
    end

    test "handle_call(:stop) stops via a synchronous call", %{pid: pid} do
      ref = Process.monitor(pid)
      assert :ok = GenServer.call(pid, :stop)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
    end

    test "an unknown message is logged and the retriever keeps running", %{pid: pid} do
      log =
        capture_log(fn ->
          send(pid, :an_unexpected_message)
          # Synchronise on the mailbox so the message is processed before we assert.
          _ = :sys.get_state(pid)
        end)

      assert log =~ "Invalid message for ExchangeRates.Retriever"
      assert Process.alive?(pid)
    end
  end

  defp start_named(config) do
    name = :"cov_#{System.unique_integer([:positive])}"
    pid = start_supervised!({Retriever, [name: name, config: config]}, id: name)
    # Synchronise on init having fully run (including any self-sent messages).
    _ = :sys.get_state(pid)
    {name, pid}
  end

  describe "backwards compatibility with a legacy singleton cache module" do
    test "latest_rates and historic_rates still work against an old, arity-0 cache module" do
      config = %{Money.ExchangeRates.default_config() | cache_module: LegacyCacheMock}
      {name, _pid} = start_named(config)

      assert {:ok, %{USD: _}} = Retriever.latest_rates(name)
      assert {:ok, _rates} = Retriever.historic_rates(name, ~D[2017-01-01])
    end
  end

  describe "a retriever registered under a non-atom name" do
    setup do
      registry = :"via_registry_#{System.unique_integer([:positive])}"
      start_supervised!({Registry, keys: :unique, name: registry})
      {:ok, registry: registry}
    end

    test "the public lookup API accepts the {:via, ...} name", %{registry: registry} do
      name = {:via, Registry, {registry, :rates}}
      pid = start_supervised!({Retriever, name: name}, id: :retriever_rates)

      assert GenServer.whereis(name) == pid

      refute Retriever.latest_rates_available?(name)

      assert {:ok, %{USD: _}} = Retriever.latest_rates(name)
      assert Retriever.latest_rates_available?(name)
      assert {:ok, %DateTime{}} = Retriever.last_updated(name)

      assert Retriever.historic_rates(name, ~D[2017-01-01]) ==
               {:ok, %{AUD: Decimal.new("0.5"), EUR: Decimal.new("1.1"), USD: Decimal.new("0.7")}}

      assert [{:ok, _}, {:ok, _}] =
               Retriever.historic_rates(name, ~D[2017-01-01], ~D[2017-01-02])
    end

    test "keeps its cache isolated from another named retriever", %{registry: registry} do
      foo = {:via, Registry, {registry, :foo}}
      bar = {:via, Registry, {registry, :bar}}
      start_supervised!({Retriever, name: foo}, id: :retriever_foo)
      start_supervised!({Retriever, name: bar}, id: :retriever_bar)

      # Populate only the foo retriever's cache; the bar retriever must not see it.
      assert {:ok, _rates} = Retriever.latest_rates(foo)

      assert Retriever.latest_rates_available?(foo)
      refute Retriever.latest_rates_available?(bar)
    end
  end

  describe "startup scheduling and preload" do
    test "a retrieval interval logs the init message and fetches on demand" do
      config = %{
        Money.ExchangeRates.default_config()
        | retrieve_every: 60_000,
          log_levels: %{success: :info, failure: :warning, info: :info}
      }

      log =
        capture_log(fn ->
          {name, _pid} = start_named(config)
          assert {:ok, %{USD: _}} = Retriever.latest_rates(name)
        end)

      # Exercises log/3 (with a configured level), log_init_message/1 and seconds/1.
      assert log =~ "Exchange Rates will be retrieved"
    end

    # Each preload shape drives a different `schedule_historic_rates_preload/2`
    # clause during init. Starting the retriever exercises the clause; the
    # retriever must come up and stay running.
    for {label, preload} <- [
          {"a single date", ~D[2017-01-01]},
          {"a date range", Date.range(~D[2017-01-01], ~D[2017-01-02])},
          {"a {from, to} tuple", {~D[2017-01-01], ~D[2017-01-02]}},
          {"an ISO date string", "2017-01-01"},
          {"an ISO date range string", "2017-01-01..2017-01-02"},
          {"an unrecognised value (no preload)", :not_a_date}
        ] do
      test "preload_historic_rates accepts #{label}" do
        config = %{
          Money.ExchangeRates.default_config()
          | preload_historic_rates: unquote(Macro.escape(preload))
        }

        {name, _pid} = start_named(config)
        assert Process.alive?(GenServer.whereis(name))
      end
    end
  end
end
