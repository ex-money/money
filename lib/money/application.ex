defmodule Money.Application do
  use Application
  require Logger

  def start(_type, args) do
    children = [
      Money.Currency.Store
      | exchange_rate_supervisor()
    ]

    opts =
      if args == [] do
        [strategy: :one_for_one, name: Money.Supervisor]
      else
        args
      end

    supervisor = Supervisor.start_link(children, opts)

    register_custom_currencies()

    supervisor
  end

  defp exchange_rate_supervisor do
    maybe_log_deprecation()

    if Money.get_env(:auto_start_exchange_rate_service, true, :boolean) do
      [Money.ExchangeRates.Supervisor]
    else
      []
    end
  end

  @doc false
  def register_custom_currencies do
    case Application.get_env(:ex_money, :custom_currencies) do
      nil ->
        :ok

      currencies when is_list(currencies) ->
        Enum.each(currencies, fn {code, options} ->
          case Money.Currency.new(code, options) do
            {:ok, _currency} ->
              :ok

            {:error, exception} ->
              Logger.warning(
                "Failed to register custom currency #{inspect(code)}: " <>
                  Exception.message(exception)
              )
          end
        end)
    end
  end

  @doc false
  def maybe_log_deprecation do
    case Application.fetch_env(:ex_money, :delay_before_first_retrieval) do
      {:ok, _} ->
        Logger.warning(
          "[ex_money] Configuration option :delay_before_first_retrieval is deprecated. " <>
            "Please remove it from your configuration."
        )

        Application.delete_env(:ex_money, :delay_before_first_retrieval)

      :error ->
        nil
    end

    case Application.fetch_env(:ex_money, :exchange_rate_service) do
      {:ok, start?} ->
        Logger.warning(
          "[ex_money] Configuration option :exchange_rate_service is deprecated " <>
            "in favour of :auto_start_exchange_rate_service.  Please " <>
            "update your configuration."
        )

        Application.put_env(:ex_money, :auto_start_exchange_rate_service, start?)
        Application.delete_env(:ex_money, :exchange_rate_service)

      :error ->
        nil
    end

    case Application.fetch_env(:ex_money, :auto_start_exchange_rate_service) do
      {:ok, true} ->
        Logger.warning(
          "[ex_money] Automatically starting the exchange rate service is deprecated. " <>
            "Set `auto_start_exchange_rate_service: false` and add " <>
            "`Money.ExchangeRates.Retriever` to your supervision tree."
        )

      {:ok, false} ->
        nil

      :error ->
        Logger.warning(
          "[ex_money] Automatically starting the exchange rate service is deprecated. " <>
            "Set `auto_start_exchange_rate_service: false` and, if you use the service, " <>
            "add `Money.ExchangeRates.Retriever` to your supervision tree."
        )
    end
  end
end
