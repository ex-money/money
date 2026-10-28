defmodule Money.Subscription.Change do
  @moduledoc """
  Defines the structure of a plan changeset.

  * `:first_interval_starts` which is the start date of the first interval for the new
    plan

  * `:first_billing_amount` is the amount to be billed, net of any credit, at
    the `:first_interval_starts`

  * `:next_interval_starts` is the start date of the next interval after the
    first interval including any `credit_days_applied`

  * `:credit_amount` is the amount of unconsumed credit of the current plan

  * `:credit_amount_applied` is the amount of credit applied to the new plan. If
    the `:prorate` option is `:price` (the default) the `:first_billing_amount`
    is the plan `:price` reduced by the `:credit_amount_applied`. If the `:prorate`
    option is `:period` then the `:first_billing_amount` is the plan `price` and
    the `:next_interval_date` is extended by the `:credit_days_applied`
    instead.

  * `:credit_days_applied` is the number of days credit applied to the first
    interval by adding days to the `:first_interval_starts` date.

  * `:credit_period_ends` is the date on which any applied credit is consumed or `nil`

  * `:carry_forward` is any amount of credit carried forward to a subsequent period.
    If non-zero this amount is a negative `Money.t`. It is non-zero when the credit
    amount for the current plan is greater than the price of the new plan.  In
    this case the `:first_billing_amount` is zero.

  """

  @typedoc "A plan change record struct."
  @type t :: %__MODULE__{
          first_billing_amount: Money.t(),
          first_interval_starts: Date.t(),
          next_interval_starts: Date.t(),
          credit_amount_applied: Money.t(),
          credit_amount: Money.t(),
          credit_days_applied: non_neg_integer(),
          credit_period_ends: Date.t() | nil,
          carry_forward: Money.t()
        }

  @doc """
  A struct defining the changes between two plans.
  """
  defstruct first_billing_amount: nil,
            first_interval_starts: nil,
            next_interval_starts: nil,
            credit_amount_applied: nil,
            credit_amount: nil,
            credit_days_applied: 0,
            credit_period_ends: nil,
            carry_forward: nil
end
