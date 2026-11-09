defmodule Money.CurrencyTest do
  use ExUnit.Case

  doctest Money.Currency

  # A process locale lists only some currencies: `ady` lists neither the
  # Kuwaiti dinar nor the Bahraini dinar, each of three digits. Each test
  # runs in a process of its own, so the locale it sets ends with it.
  describe "a currency the process locale does not list" do
    test "is found with its own digits" do
      {:ok, _} = Localize.put_locale(:ady)

      for code <- [:KWD, :BHD] do
        refute match?({:ok, _}, Localize.Currency.currency_for_code(code, locale: :ady))

        assert {:ok, %Localize.Currency{code: ^code, digits: 3}} =
                 Money.Currency.currency_for_code(code)
      end
    end

    test "is rounded, converted and built as in a locale that lists it" do
      for code <- [:KWD, :BHD] do
        assert results_in(:ady, code) == results_in(:en, code), inspect(code)
      end

      {:ok, _} = Localize.put_locale(:ady)

      assert Money.round(Money.new(:KWD, Decimal.new("1.23456"))) ==
               Money.new(:KWD, Decimal.new("1.235"))
    end
  end

  defp results_in(locale, code) do
    {:ok, _} = Localize.put_locale(locale)
    money = Money.new(code, Decimal.new("1.23456"))

    [
      Money.round(money),
      Money.to_integer_exp(money),
      Money.from_integer(1234, code),
      Money.put_fraction(money, 0)
    ]
  end
end
