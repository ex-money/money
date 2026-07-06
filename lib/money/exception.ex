defmodule Money.UnknownCurrencyError do
  defexception [:message]

  @impl true
  def exception(message) do
    %__MODULE__{message: message}
  end
end

defmodule Money.CurrencyAlreadyDefinedError do
  defexception [:currency]

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{currency: currency}) do
    "The currency #{inspect(currency)} is already defined."
  end
end

defmodule Money.CurrencyNotSavedError do
  defexception [:currency]

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{currency: currency}) do
    "The currency #{inspect(currency)} could not be saved. Ensure Money.Currency.Store is started."
  end
end

defmodule Money.InvalidCurrencyError do
  defexception [:message]

  @impl true
  def exception(message) do
    %__MODULE__{message: message}
  end
end

defmodule Money.FormatError do
  defexception [:message]

  @impl true
  def exception(message) do
    %__MODULE__{message: message}
  end
end

defmodule Money.ExchangeRateError do
  defexception [:message]

  @impl true
  def exception(message) do
    %__MODULE__{message: message}
  end
end

defmodule Money.InvalidAmountError do
  defexception [:message]

  @impl true
  def exception(message) do
    %__MODULE__{message: message}
  end
end

defmodule Money.InvalidDigitsError do
  defexception [:message]

  @impl true
  def exception(message) do
    %__MODULE__{message: message}
  end
end

# Public exception module; the name is part of the API and cannot be renamed
# to the `…Error` convention without a breaking change.
# credo:disable-for-next-line Credo.Check.Consistency.ExceptionNames
defmodule Money.Invalid do
  defexception [:message]

  @impl true
  def exception(message) do
    %__MODULE__{message: message}
  end
end

defmodule Money.ParseError do
  defexception [:message]

  @impl true
  def exception(message) do
    %__MODULE__{message: message}
  end
end

# Public exception module; the name is part of the API and cannot be renamed
# to the `…Error` convention without a breaking change.
# credo:disable-for-next-line Credo.Check.Consistency.ExceptionNames
defmodule Money.Subscription.NoCurrentPlan do
  defexception [:message]

  @impl true
  def exception(message) do
    %__MODULE__{message: message}
  end
end

defmodule Money.Subscription.PlanError do
  defexception [:message]

  @impl true
  def exception(message) do
    %__MODULE__{message: message}
  end
end

defmodule Money.Subscription.DateError do
  defexception [:message]

  @impl true
  def exception(message) do
    %__MODULE__{message: message}
  end
end

# Public exception module; the name is part of the API and cannot be renamed
# to the `…Error` convention without a breaking change.
# credo:disable-for-next-line Credo.Check.Consistency.ExceptionNames
defmodule Money.Subscription.PlanPending do
  defexception [:message]

  @impl true
  def exception(message) do
    %__MODULE__{message: message}
  end
end
