defmodule Money.ExchangeRates.Callback do
  @moduledoc """
  Default exchange rates retrieval callback module.

  When exchange rates are successfully retrieved, the function
  `latest_rates_retrieved/2` or `historic_rates_retrieved/2` is
  called to perform any desired serialization or processing.
  """

  @doc """
  Invoked after the latest exchange rates are successfully retrieved from an external
  data source.
  """
  @callback latest_rates_retrieved(%{}, DateTime.t()) :: :ok

  @doc """
  Invoked after historic exchange rates are successfully retrieved from an external
  data source.
  """
  @callback historic_rates_retrieved(%{}, Date.t()) :: :ok

  @doc """
  Callback function invoked when the latest exchange rates are retrieved.
  """
  @spec latest_rates_retrieved(%{}, DateTime.t()) :: :ok
  def latest_rates_retrieved(_rates, _retrieved_at) do
    :ok
  end

  @doc """
  Callback function invoked when historic exchange rates are retrieved.
  """
  @spec historic_rates_retrieved(%{}, Date.t()) :: :ok
  def historic_rates_retrieved(_rates, _date) do
    :ok
  end
end
