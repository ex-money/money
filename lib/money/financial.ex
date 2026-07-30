defmodule Money.Financial do
  @moduledoc """
  A set of financial functions, primarily related to discounted cash flows.

  Some of the algorithms are from [finance formulas](http://www.financeformulas.net)
  """
  alias Localize.Utils.Math

  @doc """
  Calculates the future value for a present value, an interest rate
  and a number of periods.

  * `present_value` is a %Money{} representation of the present value

  * `interest_rate` is a float representation of an interest rate.  For
  example, 12% would be represented as `0.12`

  * `periods` in an integer number of periods

  ### Returns

  * the future value as a `t:Money.t/0`.

  ### Examples

      iex> Money.Financial.future_value Money.new(:USD, 10000), 0.08, 1
      Money.new(:USD, "10800.00")

      iex> Money.Financial.future_value Money.new(:USD, 10000), 0.04, 2
      Money.new(:USD, "10816.0000")

      iex> Money.Financial.future_value Money.new(:USD, 10000), 0.02, 4
      Money.new(:USD, "10824.32160000")

  """
  @spec future_value(Money.t(), number, number) :: Money.t()
  @one Decimal.new(1)

  def future_value(%Money{amount: amount} = money, interest_rate, periods)
      when is_number(interest_rate) and is_number(periods) do
    fv =
      interest_rate
      |> Decimal.from_float()
      |> Decimal.add(@one)
      |> Math.power(periods)
      |> Decimal.mult(amount)

    %{money | amount: fv}
  end

  @doc """
  Calculates the future value for a list of cash flows and an interest rate.

  * `flows` is a list of tuples representing a cash flow.  Each flow is
  represented as a tuple of the form `{period, %Money{}}`

  * `interest_rate` is a float representation of an interest rate.  For
  example, 12% would be represented as `0.12`

  ### Returns

  * the future value as a `t:Money.t/0`.

  ### Examples

      iex> Money.Financial.future_value([{4, Money.new(:USD, 10000)}, {5, Money.new(:USD, 10000)}, {6, Money.new(:USD, 10000)}], 0.13)
      Money.new(:USD, "34069.00000000000000000000000000000")

      iex> Money.Financial.future_value [{0, Money.new(:USD, 5000)},{1, Money.new(:USD, 2000)}], 0.12
      Money.new(:USD, "7600.000000000000000000000000000000")

  """
  @spec future_value(list({number, Money.t()}), number) :: Money.t()

  def future_value(flows, interest_rate)

  def future_value([{period, %Money{}} | _other_flows] = flows, interest_rate)
      when is_integer(period) and is_number(interest_rate) do
    {max_period, _} = Enum.max(flows)

    present_value(flows, interest_rate)
    |> future_value(interest_rate, max_period)
  end

  @doc """
  Calculates the present value for future value, an interest rate
  and a number of periods

  * `future_value` is a %Money{} representation of the future value

  * `interest_rate` is a float representation of an interest rate.  For
  example, 12% would be represented as `0.12`

  * `periods` in an integer number of periods

  ### Returns

  * the present value as a `t:Money.t/0`.

  ### Examples

      iex> Money.Financial.present_value Money.new(:USD, 100), 0.08, 2
      Money.new(:USD, "85.73388203017832647462277091906722")

      iex> Money.Financial.present_value Money.new(:USD, 1000), 0.10, 20
      Money.new(:USD, "148.6436280241436864020760472258494")

  """
  @spec present_value(Money.t(), number, number) :: Money.t()

  def present_value(%Money{amount: amount} = money, interest_rate, periods)
      when is_number(interest_rate) and is_number(periods) and periods >= 0 do
    pv_1 =
      interest_rate
      |> Decimal.from_float()
      |> Decimal.add(@one)
      |> Math.power(periods)

    %{money | amount: Decimal.div(amount, pv_1)}
  end

  @doc """
  Calculates the present value for a list of cash flows and an interest rate.

  * `flows` is a list of tuples representing a cash flow.  Each flow is
  represented as a tuple of the form `{period, %Money{}}`

  * `interest_rate` is a float representation of an interest rate.  For
  example, 12% would be represented as `0.12`

  ### Returns

  * the present value as a `t:Money.t/0`.

  ### Examples

      iex> Money.Financial.present_value([{4, Money.new(:USD, 10000)}, {5, Money.new(:USD, 10000)}, {6, Money.new(:USD, 10000)}], 0.13)
      Money.new(:USD, "16363.97191111964880256655144582667")

      iex> Money.Financial.present_value [{0, Money.new(:USD, -1000)},{1, Money.new(:USD, -4000)}], 0.1
      Money.new(:USD, "-4636.363636363636363636363636363636")

  """
  @spec present_value(list({integer, Money.t()}), number) :: Money.t()
  def present_value(flows, interest_rate)

  def present_value([{period, %Money{}} | _other_flows] = flows, interest_rate)
      when is_integer(period) and is_number(interest_rate) do
    validate_same_currency!(flows)
    do_present_value(flows, interest_rate)
  end

  defp do_present_value({period, %Money{} = flow}, interest_rate)
       when is_integer(period) and is_number(interest_rate) do
    present_value(flow, interest_rate, period)
  end

  defp do_present_value([{period, %Money{}} = flow | []], interest_rate)
       when is_integer(period) and is_number(interest_rate) do
    do_present_value(flow, interest_rate)
  end

  defp do_present_value([{period, %Money{}} = flow | other_flows], interest_rate)
       when is_integer(period) and is_number(interest_rate) do
    do_present_value(flow, interest_rate)
    |> Money.add!(do_present_value(other_flows, interest_rate))
  end

  @doc """
  Calculates the net present value of an initial investment, a list of
  cash flows and an interest rate.

  * `flows` is a list of tuples representing a cash flow.  Each flow is
  represented as a tuple of the form `{period, %Money{}}`

  * `interest_rate` is a float representation of an interest rate.  For
  example, 12% would be represented as `0.12`

  * `investment` is a %Money{} struct representing the initial investment

  ### Returns

  * the net present value as a `t:Money.t/0`.

  ### Examples

      iex> flows = [{0, Money.new(:USD, 5000)},{1, Money.new(:USD, 2000)},{2, Money.new(:USD, 500)},{3, Money.new(:USD,10_000)}]
      iex> Money.Financial.net_present_value flows, 0.08, Money.new(:USD, 100)
      Money.new(:USD, "15118.84367220444038002337042117563")
      iex> Money.Financial.net_present_value flows, 0.08
      Money.new(:USD, "15218.84367220444038002337042117563")

  """
  @spec net_present_value(list({integer, Money.t()}), number) :: Money.t()

  def net_present_value([{period, %Money{currency: currency}} | _] = flows, interest_rate)
      when is_integer(period) and is_number(interest_rate) do
    net_present_value(flows, interest_rate, Money.zero(currency))
  end

  @spec net_present_value(list({integer, Money.t()}), number, Money.t()) :: Money.t()
  def net_present_value([{period, %Money{}} | _] = flows, interest_rate, %Money{} = investment)
      when is_integer(period) and is_number(interest_rate) do
    validate_same_currency!(investment, flows)

    present_value(flows, interest_rate)
    |> Money.sub!(investment)
  end

  @doc """
  Calculates the net present value of an initial investment, a recurring
  payment, an interest rate and a number of periods

  * `investment` is a %Money{} struct representing the initial investment

  * `future_value` is a %Money{} representation of the future value

  * `interest_rate` is a float representation of an interest rate.  For
    example, 12% would be represented as `0.12`

  * `periods` in an integer number of a period

  ### Returns

  * the net present value as a `t:Money.t/0`.

  ### Examples

      iex> Money.Financial.net_present_value(Money.new(:USD, 10000), 0.13, 2)
      Money.new(:USD, "7831.466833737959119743127887853395")

      iex> Money.Financial.net_present_value(Money.new(:USD, 10000), 0.13, 2, Money.new(:USD, 100))
      Money.new(:USD, "7731.466833737959119743127887853395")

  """
  @spec net_present_value(Money.t(), float, number) :: Money.t()
  def net_present_value(%Money{currency: currency} = future_value, interest_rate, periods) do
    net_present_value(future_value, interest_rate, periods, Money.new(currency, 0))
  end

  @spec net_present_value(Money.t(), float, number, Money.t()) :: Money.t()
  def net_present_value(%Money{} = future_value, interest_rate, periods, %Money{} = investment) do
    present_value(future_value, interest_rate, periods)
    |> Money.sub!(investment)
  end

  @doc """
  Calculates the interal rate of return for a given list of cash flows.

  ### Arguments

  * `flows` is a list of tuples representing a cash flow.  Each flow is
    represented as a tuple of the form `{period, %Money{}}`

  ### Returns

  * the internal rate of return as a `float`.

  """
  @spec internal_rate_of_return(list({integer, Money.t()})) :: float()
  def internal_rate_of_return([{_period, %Money{}} | _other_flows] = flows) do
    # estimate_m = sum_of_inflows(flows)
    # |> Kernel./(abs(Math.to_float(amount)))
    # |> :math.pow(2 / (number_of_flows(flows) + 1))
    # |> Kernel.-(1)

    # estimate_n = :math.pow(1 + estimate_m, )

    estimate_n = 0.2
    estimate_m = 0.1

    do_internal_rate_of_return(flows, estimate_m, estimate_n)
  end

  @irr_precision 0.000001
  defp do_internal_rate_of_return(flows, estimate_m, estimate_n) do
    npv_n = net_present_value(flows, estimate_n).amount |> Math.to_float()
    npv_m = net_present_value(flows, estimate_m).amount |> Math.to_float()

    if abs(npv_n - npv_m) > @irr_precision do
      estimate_o = estimate_n - (estimate_n - estimate_m) / (npv_n - npv_m) * npv_n
      do_internal_rate_of_return(flows, estimate_n, estimate_o)
    else
      estimate_n
    end
  end

  @doc """
  Calculates the effective interest rate for a given present value,
  a future value and a number of periods.

  ### Arguments

  * `present_value` is a %Money{} representation of the present value

  * `future_value` is a %Money{} representation of the future value

  * `periods` is an integer number of a period

  ### Returns

  * the effective interest rate per period as a `t:Decimal.t/0`.

  ### Examples

      iex> Money.Financial.interest_rate Money.new(:USD, 10000), Money.new(:USD, 10816), 2
      Decimal.new("0.04")

      iex> Money.Financial.interest_rate Money.new(:USD, 10000), Money.new(:USD, "10824.3216"), 4
      Decimal.new("0.02")

  """
  @spec interest_rate(Money.t(), Money.t(), number) :: Decimal.t()
  def interest_rate(
        %Money{currency: pv_currency, amount: pv_amount} = _present_value,
        %Money{currency: fv_currency, amount: fv_amount} = _future_value,
        periods
      )
      when pv_currency == fv_currency and is_integer(periods) and periods > 0 do
    fv_amount
    |> Decimal.div(pv_amount)
    |> Math.root(periods)
    |> Decimal.sub(@one)
  end

  @doc """
  Calculates the number of periods between a present value and
  a future value with a given interest rate.

  ### Arguments

  * `present_value` is a %Money{} representation of the present value

  * `future_value` is a %Money{} representation of the future value

  * `interest_rate` is a float representation of an interest rate.  For
  example, 12% would be represented as `0.12`

  ### Returns

  * the number of periods as a `t:Decimal.t/0`.

  ### Examples

      iex> Money.Financial.periods Money.new(:USD, 1500), Money.new(:USD, 2000), 0.005
      Decimal.new("57.68013595323872502502238366926834")

  """
  @spec periods(Money.t(), Money.t(), float) :: Decimal.t()
  def periods(
        %Money{currency: pv_currency, amount: pv_amount} = _present_value,
        %Money{currency: fv_currency, amount: fv_amount} = _future_value,
        interest_rate
      )
      when pv_currency == fv_currency and is_float(interest_rate) and interest_rate > 0 do
    Decimal.div(
      Math.log(Decimal.div(fv_amount, pv_amount)),
      Math.log(Decimal.add(@one, Decimal.from_float(interest_rate)))
    )
  end

  @doc """
  Calculates the payment for a given loan or annuity given a
  present value, an interest rate and a number of periods.

  ### Arguments

  * `present_value` is a %Money{} representation of the present value

  * `interest_rate` is a float representation of an interest rate.  For
  example, 12% would be represented as `0.12`

  * `periods` is an integer number of periods

  ### Returns

  * the payment per period as a `t:Money.t/0` in the currency of
    `present_value`.

  ### Examples

      iex> Money.Financial.payment Money.new(:USD, 100), 0.12, 20
      Money.new(:USD, "13.38787800396606622792492298818559")

  """
  @spec payment(Money.t(), float, number) :: Money.t()
  def payment(
        %Money{amount: pv_amount} = present_value,
        interest_rate,
        periods
      )
      when is_float(interest_rate) and interest_rate > 0 and is_number(periods) and periods > 0 do
    interest_rate = Decimal.from_float(interest_rate)
    p1 = Decimal.mult(pv_amount, interest_rate)
    p2 = Decimal.sub(@one, Decimal.add(@one, interest_rate) |> Math.power(-periods))
    %{present_value | amount: Decimal.div(p1, p2)}
  end

  defp validate_same_currency!(%Money{} = flow, flows) do
    validate_same_currency!([{0, flow} | flows])
  end

  defp validate_same_currency!(flows) do
    number_of_currencies =
      flows
      |> Enum.map(fn {_period, %Money{currency: currency}} -> currency end)
      |> Enum.uniq()
      |> Enum.count()

    if number_of_currencies > 1 do
      raise ArgumentError,
        message:
          "More than one currency found in cash flows; " <>
            "implicit currency conversion is not supported.  Cash flows: " <> inspect(flows)
    end
  end
end
