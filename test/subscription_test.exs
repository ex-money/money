defmodule MoneySubscriptionTest do
  use ExUnit.Case
  alias Money.Subscription
  alias Money.Subscription.Change
  alias Money.Subscription.Plan

  doctest Money.Subscription
  doctest Money.Subscription.Plan

  test "plan change at end of period has no credit and correct billing dates" do
    p1 = %{interval: :day, interval_count: 30, price: Money.new(:USD, 100)}
    p2 = %{interval: :day, interval_count: 30, price: Money.new(:USD, 200)}

    {:ok, changeset} =
      Money.Subscription.change_plan(p1, p2, current_interval_started: ~D[2018-03-01])

    assert changeset.first_billing_amount == Money.new(:USD, 200)
    assert changeset.first_interval_starts == ~D[2018-03-31]
    assert changeset.next_interval_starts == ~D[2018-04-30]
  end

  test "plan change on January 31th should preserve 31th even past february" do
    p1 = %{interval: :month, interval_count: 1, price: Money.new(:USD, 100)}
    p2 = %{interval: :month, interval_count: 1, price: Money.new(:USD, 200)}

    {:ok, changeset} =
      Money.Subscription.change_plan(
        p1,
        p2,
        current_interval_started: ~D[2018-01-30],
        first_interval_started: ~D[2017-12-31]
      )

    assert changeset.first_billing_amount == Money.new(:USD, 200)
    assert changeset.first_interval_starts == ~D[2018-02-28]
    assert changeset.next_interval_starts == ~D[2018-03-31]
  end

  test "plan change at 50% of period has no credit and correct billing dates" do
    p1 = %{interval: :day, interval_count: 30, price: Money.new(:USD, 100)}
    p2 = %{interval: :day, interval_count: 30, price: Money.new(:USD, 200)}

    {:ok, changeset} =
      Money.Subscription.change_plan(
        p1,
        p2,
        current_interval_started: ~D[2018-03-01],
        effective: ~D[2018-03-16]
      )

    assert changeset.first_billing_amount == Money.new(:USD, "150.00")
    assert changeset.first_interval_starts == ~D[2018-03-16]
    assert changeset.next_interval_starts == ~D[2018-04-15]
    assert changeset.credit_amount_applied == Money.new(:USD, "50.00")

    assert Money.compare!(
             Money.add!(changeset.credit_amount_applied, changeset.first_billing_amount),
             p2.price
           ) == :eq
  end

  test "should get days to add to subscription upgrade" do
    today = ~D[2018-02-14]

    old = %{
      price: Money.new(:CHF, Decimal.new(130)),
      interval: :month,
      interval_count: 3
    }

    new = %{
      price: Money.new(:CHF, Decimal.new(180)),
      interval: :month,
      interval_count: 6
    }

    assert {:ok,
            %Change{
              carry_forward: Money.zero(:CHF),
              credit_amount: Money.new(:CHF, "67.20"),
              credit_amount_applied: Money.zero(:CHF),
              credit_days_applied: 68,
              credit_period_ends: ~D[2018-04-22],
              next_interval_starts: ~D[2018-10-21],
              first_billing_amount: new.price,
              first_interval_starts: today
            }} ==
             Money.Subscription.change_plan(
               old,
               new,
               current_interval_started: ~D[2018-01-01],
               effective: today,
               prorate: :period
             )
  end

  test "should get days to add to subscription upgrade when upgrading the same day" do
    today = ~D[2018-01-01]

    old = %{
      price: Money.new(:CHF, Decimal.new(130)),
      interval: :month,
      interval_count: 3
    }

    new = %{
      price: Money.new(:CHF, Decimal.new(180)),
      interval: :month,
      interval_count: 6
    }

    assert {:ok,
            %Change{
              carry_forward: Money.zero(:CHF),
              credit_amount: Money.new(:CHF, Decimal.new("130.00")),
              credit_amount_applied: Money.zero(:CHF),
              credit_days_applied: 131,
              credit_period_ends: ~D[2018-05-11],
              next_interval_starts: ~D[2018-11-09],
              first_billing_amount: new.price,
              first_interval_starts: today
            }} ==
             Money.Subscription.change_plan(
               old,
               new,
               current_interval_started: today,
               effective: today,
               prorate: :period
             )
  end

  test "should get at least 1 day when subscription upgrade is from a very low subscription to a very high one" do
    today = ~D[2018-01-14]

    old = Money.Subscription.Plan.new!(Money.new(:CHF, Decimal.new("0.5")), :month)
    new = Money.Subscription.Plan.new!(Money.new(:CHF, Decimal.new(1000)), :month, 36)

    assert {:ok,
            %Change{
              carry_forward: Money.zero(:CHF),
              credit_amount: Money.new(:CHF, "0.30"),
              credit_amount_applied: Money.zero(:CHF),
              credit_days_applied: 1,
              credit_period_ends: ~D[2018-01-14],
              next_interval_starts: ~D[2021-01-15],
              first_billing_amount: new.price,
              first_interval_starts: today
            }} ==
             Money.Subscription.change_plan(
               old,
               new,
               current_interval_started: ~D[2018-01-01],
               effective: today,
               prorate: :period
             )
  end

  test "that a carry forward is generated when credit is greater than price" do
    p1 = Plan.new!(Money.new(:USD, 1000), :day, 20)
    p2 = Plan.new!(Money.new(:USD, 10), :day, 10)

    changeset =
      Subscription.change_plan(
        p1,
        p2,
        current_interval_started: ~D[2018-01-01],
        effective: ~D[2018-01-05]
      )

    assert changeset ==
             {:ok,
              %Change{
                carry_forward: Money.new(:USD, "-790.00"),
                credit_amount: Money.new(:USD, "800.00"),
                credit_amount_applied: Money.new(:USD, "10.00"),
                credit_days_applied: 0,
                credit_period_ends: nil,
                next_interval_starts: ~D[2018-01-15],
                first_billing_amount: Money.zero(:USD),
                first_interval_starts: ~D[2018-01-05]
              }}
  end

  test "that month rollover works at end of month when next month is shorter" do
    assert Money.Subscription.next_interval_starts(
             %{interval: :month, interval_count: 1},
             ~D[2018-01-31]
           ) == ~D[2018-02-28]
  end

  @tag :sub
  test "That we can create a subscription" do
    assert {:ok, _s1} = Subscription.new(Plan.new!(Money.new(:USD, 200), :month, 3), ~D[2018-01-01])
  end

  @tag :change
  test "We can change plan in a subscription" do
    p1 = Plan.new!(Money.new(:USD, 200), :month, 3)
    p2 = Plan.new!(Money.new(:USD, 200), :day, 90)
    today = ~D[2018-01-15]

    s1 = Subscription.new!(p1, ~D[2018-01-01])
    c1 = Subscription.change_plan!(s1, p2, today: today)

    assert c1.plans ==
             [
               {%Money.Subscription.Change{
                  carry_forward: Money.zero(:USD),
                  credit_amount: Money.zero(:USD),
                  credit_amount_applied: Money.zero(:USD),
                  credit_days_applied: 0,
                  credit_period_ends: nil,
                  first_billing_amount: Money.new(:USD, 200),
                  first_interval_starts: ~D[2018-04-01],
                  next_interval_starts: ~D[2018-06-30]
                },
                %Money.Subscription.Plan{
                  interval: :day,
                  interval_count: 90,
                  price: Money.new(:USD, 200)
                }},
               {%Money.Subscription.Change{
                  carry_forward: Money.zero(:USD),
                  credit_amount: Money.zero(:USD),
                  credit_amount_applied: Money.zero(:USD),
                  credit_days_applied: 0,
                  credit_period_ends: nil,
                  first_billing_amount: Money.new(:USD, 200),
                  first_interval_starts: ~D[2018-01-01],
                  next_interval_starts: ~D[2018-04-01]
                },
                %Money.Subscription.Plan{
                  interval: :month,
                  interval_count: 3,
                  price: Money.new(:USD, 200)
                }}
             ]

    # Confirm we can't add a second pending plan
    change_2 = Subscription.change_plan(c1, p1, today: today)

    assert {:error,
            {Subscription.PlanPending, "Can't change plan when a new plan is already pending"}} ==
             change_2
  end

  test "We can detect a pending plan" do
    p1 = Plan.new!(Money.new(:USD, 200), :month, 3)
    p2 = Plan.new!(Money.new(:USD, 200), :day, 90)

    s1 = Subscription.new!(p1, ~D[2018-01-01])
    c1 = Subscription.change_plan!(s1, p2)

    assert Subscription.plan_pending?(c1) == true
  end

  test "we can get current and latest plan" do
    p1 = Plan.new!(Money.new(:USD, 200), :month, 3)
    p2 = Plan.new!(Money.new(:USD, 200), :day, 90)

    s1 = Subscription.new!(p1, ~D[2018-01-01])
    c1 = Subscription.change_plan!(s1, p2)

    {_changes, current} = Subscription.current_plan(c1)
    assert current == p1

    {_changes, latest} = Subscription.latest_plan(c1)
    assert latest == p2
  end

  test "current interval start date when the plan's starts earlier than today" do
    today = ~D[2018-01-10]
    start_date = ~D[2017-01-01]
    plan = Plan.new!(Money.new(:USD, 100), :month, 1)

    assert Subscription.current_interval_start_date(
             {%Change{first_interval_starts: start_date}, plan},
             today: today
           ) == ~D[2018-01-01]
  end

  test "current interval start date when today is within the plan's first interval" do
    today = ~D[2018-01-10]
    start_date = ~D[2018-01-01]
    plan = Plan.new!(Money.new(:USD, 100), :month, 1)

    assert Subscription.current_interval_start_date(
             {%Change{first_interval_starts: start_date}, plan},
             today: today
           ) == ~D[2018-01-01]
  end

  test "current interval start date when today is earlier than the plan's start date" do
    today = ~D[2018-01-10]
    start_date = ~D[2019-01-01]
    plan = Plan.new!(Money.new(:USD, 100), :month, 1)

    assert Subscription.current_interval_start_date(
             {%Change{first_interval_starts: start_date}, plan},
             today: today
           ) ==
             {:error,
              {Subscription.NoCurrentPlan, "The plan is not current for #{inspect(start_date)}"}}
  end

  describe "pending plan management" do
    test "cancel_pending_plan/2 removes a pending plan" do
      p1 = Plan.new!(Money.new(:USD, 100), :month, 1)
      p2 = Plan.new!(Money.new(:USD, 200), :month, 1)

      subscription = Subscription.new!(p1, ~D[2026-01-01])
      changed = Subscription.change_plan!(subscription, p2, today: ~D[2026-01-15])

      assert Subscription.plan_pending?(changed, today: ~D[2026-01-15])

      cancelled = Subscription.cancel_pending_plan(changed, today: ~D[2026-01-15])
      assert length(cancelled.plans) == 1
      refute Subscription.plan_pending?(cancelled, today: ~D[2026-01-15])
    end

    test "cancel_pending_plan/2 is a no-op when no plan is pending" do
      p1 = Plan.new!(Money.new(:USD, 100), :month, 1)
      subscription = Subscription.new!(p1, ~D[2026-01-01])

      assert Subscription.cancel_pending_plan(subscription, today: ~D[2026-01-15]) ==
               subscription
    end

    test "change_plan!/3 raises when a plan is already pending" do
      p1 = Plan.new!(Money.new(:USD, 100), :month, 1)
      p2 = Plan.new!(Money.new(:USD, 200), :month, 1)
      p3 = Plan.new!(Money.new(:USD, 300), :month, 1)

      subscription =
        Subscription.new!(p1, ~D[2026-01-01])
        |> Subscription.change_plan!(p2, today: ~D[2026-01-15])

      assert_raise Money.Subscription.PlanPending, fn ->
        Subscription.change_plan!(subscription, p3, today: ~D[2026-01-15])
      end
    end
  end

  describe "current_plan_start_date/1" do
    test "returns nil when the subscription has no plans" do
      assert Subscription.current_plan_start_date(%{plans: []}) == nil
    end
  end

  describe "change_plan effective option variants" do
    test "effective: :immediately prorates from today" do
      p1 = %{interval: :day, interval_count: 30, price: Money.new(:USD, 100)}
      p2 = %{interval: :day, interval_count: 30, price: Money.new(:USD, 200)}

      {:ok, immediate} =
        Subscription.change_plan(
          p1,
          p2,
          current_interval_started: ~D[2026-01-01],
          effective: :immediately,
          today: ~D[2026-01-16]
        )

      {:ok, dated} =
        Subscription.change_plan(
          p1,
          p2,
          current_interval_started: ~D[2026-01-01],
          effective: ~D[2026-01-16],
          today: ~D[2026-01-16]
        )

      assert immediate == dated
    end

    test "a missing required option raises ArgumentError" do
      p1 = %{interval: :day, interval_count: 30, price: Money.new(:USD, 100)}
      p2 = %{interval: :day, interval_count: 30, price: Money.new(:USD, 200)}

      assert_raise ArgumentError, ~r/change_plan requires the option/, fn ->
        Subscription.change_plan(p1, p2, effective: ~D[2026-01-16])
      end
    end
  end

  describe "next_interval_starts/3 interval variants" do
    test "week intervals advance by seven days per count" do
      assert Subscription.next_interval_starts(
               %{interval: :week, interval_count: 2},
               ~D[2026-01-01]
             ) == ~D[2026-01-15]
    end

    test "year intervals advance the year by the count" do
      assert Subscription.next_interval_starts(
               %{interval: :year, interval_count: 3},
               ~D[2026-01-01]
             ) == ~D[2029-01-01]
    end
  end

  describe "Plan constructor and formatting error paths" do
    # `:fortnight` and the integer price are deliberately invalid. Route the
    # calls through apply/3 so the set-theoretic type checker does not flag
    # the intentionally incompatible arguments.
    test "Plan.new!/3 raises for an invalid plan definition" do
      assert_raise Money.Invalid, fn ->
        apply(Plan, :new!, [Money.new(:USD, 100), :fortnight])
      end
    end

    test "Plan.new/3 returns an error for a non-money price" do
      assert {:error, {Money.Invalid, _}} = apply(Plan, :new, [100, :month])
    end

    test "Plan.to_string!/2 raises when the plan cannot be formatted" do
      plan = Plan.new!(Money.new(:USD, 100), :month)

      assert_raise Localize.InvalidLocaleError, fn ->
        Plan.to_string!(plan, locale: "not a locale!!")
      end
    end
  end

  describe "Plan.to_string/2 format option" do
    setup do
      {:ok, plan: Plan.new!(Money.new(:USD, 10), :year)}
    end

    test ":format selects the unit width", %{plan: plan} do
      assert Plan.to_string(plan, locale: :de, format: :narrow) == {:ok, "10,00 $/J"}
    end

    test ":style is accepted as a deprecated alias for :format", %{plan: plan} do
      assert Plan.to_string(plan, locale: :de, style: :narrow) ==
               Plan.to_string(plan, locale: :de, format: :narrow)
    end

    test ":format takes precedence over the deprecated :style", %{plan: plan} do
      assert Plan.to_string(plan, locale: :de, style: :long, format: :narrow) ==
               Plan.to_string(plan, locale: :de, format: :narrow)
    end
  end
end
