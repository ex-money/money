defmodule Money.CustomCurrencyTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  # Idempotent currency creation for setup blocks. Tests in this
  # module register currencies in the global Store, which persists
  # across tests, so re-running (e.g. with `mix test --stale`) or
  # multiple tests sharing a code would otherwise hit
  # CurrencyAlreadyDefinedError.
  defp ensure_currency(code, options) do
    case Money.Currency.new(code, options) do
      {:ok, currency} -> currency
      {:error, %Money.CurrencyAlreadyDefinedError{}} -> Money.Currency.Store.get(code)
    end
  end

  # ── Currency code normalization ───────────────────────────────

  describe "code form and normalization" do
    test "accepts an atom code" do
      assert {:ok, %Localize.Currency{code: :XAT1}} =
               Money.Currency.new(:XAT1, name: "Atom One")
    end

    test "accepts a binary code" do
      assert {:ok, %Localize.Currency{code: :XBN1}} =
               Money.Currency.new("XBN1", name: "Binary One")
    end

    test "accepts a lowercase atom and normalizes to uppercase" do
      assert {:ok, %Localize.Currency{code: :XAT2}} =
               Money.Currency.new(:xat2, name: "Lower Atom")
    end

    test "accepts a lowercase binary and normalizes to uppercase" do
      assert {:ok, %Localize.Currency{code: :XBN2}} =
               Money.Currency.new("xbn2", name: "Lower Binary")
    end

    test "accepts a mixed-case code and normalizes to uppercase" do
      assert {:ok, %Localize.Currency{code: :XMIX}} =
               Money.Currency.new("XmIx", name: "Mixed")
    end
  end

  # ── Valid code formats ────────────────────────────────────────

  describe "accepted code formats" do
    test "3-char private-use code (X[A-Z]{2})" do
      assert {:ok, %Localize.Currency{code: :XAA}} =
               Money.Currency.new(:XAA, name: "Private AA")
    end

    test "4-char custom code" do
      assert {:ok, %Localize.Currency{code: :QFF1}} =
               Money.Currency.new(:QFF1, name: "Frequent Flyer")
    end

    test "10-char custom code (maximum length)" do
      assert {:ok, %Localize.Currency{code: :LONGESTCOD}} =
               Money.Currency.new(:LONGESTCOD, name: "Longest")
    end

    test "custom code with digits after first letter" do
      assert {:ok, %Localize.Currency{code: :A1B2C3}} =
               Money.Currency.new(:A1B2C3, name: "Alphanumeric")
    end
  end

  # ── Rejected code formats ─────────────────────────────────────

  describe "rejected code formats" do
    test "rejects an ISO 4217 code (atom)" do
      assert {:error, %Money.CurrencyAlreadyDefinedError{currency: :USD}} =
               Money.Currency.new(:USD, name: "Duplicate USD")
    end

    test "rejects an ISO 4217 code (binary)" do
      assert {:error, %Money.CurrencyAlreadyDefinedError{currency: :EUR}} =
               Money.Currency.new("EUR", name: "Duplicate EUR")
    end

    test "rejects an ISO 4217 private-use precious-metal code (XAU)" do
      assert {:error, %Money.CurrencyAlreadyDefinedError{currency: :XAU}} =
               Money.Currency.new(:XAU, name: "Gold Dupe")
    end

    test "rejects a duplicate custom code" do
      ensure_currency(:XDUP, name: "First")

      assert {:error, %Money.CurrencyAlreadyDefinedError{currency: :XDUP}} =
               Money.Currency.new(:XDUP, name: "Second")
    end

    test "rejects a 2-character code (too short)" do
      assert {:error, %Money.UnknownCurrencyError{}} =
               Money.Currency.new(:AB, name: "Too Short")
    end

    test "rejects an 11-character code (too long)" do
      assert {:error, %Money.UnknownCurrencyError{}} =
               Money.Currency.new(:ABCDEFGHIJK, name: "Too Long")
    end

    test "rejects a code starting with a digit" do
      assert {:error, %Money.UnknownCurrencyError{}} =
               Money.Currency.new(:"1ABC", name: "Digit Prefix")
    end

    test "rejects a code containing a hyphen" do
      assert {:error, %Money.UnknownCurrencyError{}} =
               Money.Currency.new(:"X-Y", name: "Hyphen")
    end

    test "rejects a code containing a space" do
      assert {:error, %Money.UnknownCurrencyError{}} =
               Money.Currency.new(:"X Y", name: "Space")
    end
  end

  # ── Option defaults ───────────────────────────────────────────

  describe "option defaults" do
    test "requires a :name option" do
      assert {:error, %Money.InvalidCurrencyError{}} = Money.Currency.new(:XNOM1)
    end

    test "requires a :name option when other options provided" do
      assert {:error, %Money.InvalidCurrencyError{}} =
               Money.Currency.new(:XNOM2, digits: 4)
    end

    test ":digits defaults to 2" do
      {:ok, currency} = Money.Currency.new(:XDIG, name: "Digits Default")
      assert currency.digits == 2
    end

    test ":symbol defaults to the uppercase code as a string" do
      {:ok, currency} = Money.Currency.new(:XSYM, name: "Symbol Default")
      assert currency.symbol == "XSYM"
    end

    test ":narrow_symbol defaults to :symbol when :symbol is given" do
      {:ok, currency} = Money.Currency.new(:XNSY, name: "Narrow", symbol: "N$")
      assert currency.narrow_symbol == "N$"
    end

    test ":narrow_symbol defaults to nil when :symbol is not given" do
      {:ok, currency} = Money.Currency.new(:XNSN, name: "Narrow Nil")
      assert currency.narrow_symbol == nil
    end

    test ":alt_code defaults to code" do
      {:ok, currency} = Money.Currency.new(:XALC, name: "AltCode")
      assert currency.alt_code == :XALC
    end

    test ":cash_digits defaults to :digits" do
      {:ok, currency} = Money.Currency.new(:XCSH, name: "Cash", digits: 4)
      assert currency.cash_digits == 4
    end

    test ":tender defaults to false" do
      {:ok, currency} = Money.Currency.new(:XTND, name: "Tender Default")
      assert currency.tender == false
    end

    test ":count defaults to %{other: name}" do
      {:ok, currency} = Money.Currency.new(:XCNT, name: "Count Default")
      assert currency.count == %{other: "Count Default"}
    end

    test ":iso_digits is set from :digits" do
      {:ok, currency} = Money.Currency.new(:XISO, name: "ISO", digits: 8)
      assert currency.iso_digits == 8
    end
  end

  # ── Full options round-trip ───────────────────────────────────

  describe "full options" do
    test "all options propagate to the struct" do
      {:ok, currency} =
        Money.Currency.new(:XFUL,
          name: "Full Currency",
          digits: 8,
          symbol: "F$",
          narrow_symbol: "F",
          round_nearest: 5,
          alt_code: :XFALT,
          cash_digits: 2,
          cash_round_nearest: 1,
          tender: true,
          count: %{one: "Ful", other: "Fuls"}
        )

      assert %Localize.Currency{
               code: :XFUL,
               alt_code: :XFALT,
               name: "Full Currency",
               symbol: "F$",
               narrow_symbol: "F",
               digits: 8,
               rounding: 5,
               cash_digits: 2,
               cash_rounding: 1,
               iso_digits: 8,
               tender: true,
               count: %{one: "Ful", other: "Fuls"}
             } = currency
    end

    test ":round_nearest populates the :rounding field" do
      {:ok, currency} = Money.Currency.new(:XROU, name: "Round", round_nearest: 25)
      assert currency.rounding == 25
    end

    test ":cash_round_nearest populates the :cash_rounding field" do
      {:ok, currency} =
        Money.Currency.new(:XCRO, name: "CashRound", cash_round_nearest: 10)

      assert currency.cash_rounding == 10
    end
  end

  # ── Registry integration ──────────────────────────────────────

  describe "registry integration" do
    setup do
      ensure_currency(:XREG, name: "Registry")
      :ok
    end

    test "appears in Money.known_currencies" do
      assert :XREG in Money.known_currencies()
    end

    test "appears in Money.Currency.private_currencies" do
      assert %Localize.Currency{code: :XREG} = Money.Currency.private_currencies()[:XREG]
    end

    test "appears in Money.Currency.private_currency_codes" do
      assert :XREG in Money.Currency.private_currency_codes()
    end

    test "is returned by Money.Currency.currency_for_code/1" do
      assert {:ok, %Localize.Currency{code: :XREG}} =
               Money.Currency.currency_for_code(:XREG)
    end
  end

  # ── Money API integration ────────────────────────────────────

  describe "Money API integration" do
    setup do
      ensure_currency(:XMON, name: "Money API", digits: 2)
      :ok
    end

    test "Money.new/2 accepts the custom currency" do
      assert Money.new(:XMON, 100) == Money.new(:XMON, "100")
    end

    test "Money.new/2 normalizes lowercase input to the registered uppercase code" do
      money = Money.new(:xmon, 100)
      assert money.currency == :XMON
    end

    test "Money.round/1 respects the custom :digits" do
      ensure_currency(:XRN1, name: "Round1", digits: 3)

      assert Money.round(Money.new(:XRN1, "100.12345")) ==
               Money.new(:XRN1, "100.123")
    end

    test "Money.round/1 applies custom :round_nearest" do
      # :round_nearest is an integer increment at the 10^(-digits) scale
      # (matching the CLDR convention). With digits: 2 and round_nearest: 5,
      # the effective rounding increment is 5 * 0.01 = 0.05.
      ensure_currency(:XRN2, name: "Round2", digits: 2, round_nearest: 5)

      assert Money.round(Money.new(:XRN2, "100.12")) ==
               Money.new(:XRN2, "100.10")
    end

    test "Money.split/2 respects the custom :digits" do
      ensure_currency(:XSPL, name: "Split", digits: 4)

      {whole, remainder} = Money.split(Money.new(:XSPL, "100"), 3)
      assert whole == Money.new(:XSPL, "33.3333")
      assert remainder == Money.new(:XSPL, "0.0001")
    end
  end

  # ── Startup registration ──────────────────────────────────────

  describe "application startup registration" do
    test "currencies from :custom_currencies config are registered" do
      previous = Application.get_env(:ex_money, :custom_currencies)

      Application.put_env(:ex_money, :custom_currencies, [
        {:XST1, [name: "Startup One", digits: 3]},
        {:XST2, [name: "Startup Two", symbol: "S2$"]}
      ])

      try do
        assert :ok = Money.Application.register_custom_currencies()

        assert %Localize.Currency{code: :XST1, digits: 3} =
                 Money.Currency.Store.get(:XST1)

        assert %Localize.Currency{code: :XST2, symbol: "S2$"} =
                 Money.Currency.Store.get(:XST2)
      after
        if previous do
          Application.put_env(:ex_money, :custom_currencies, previous)
        else
          Application.delete_env(:ex_money, :custom_currencies)
        end
      end
    end

    test "errors during startup are logged but do not crash" do
      previous = Application.get_env(:ex_money, :custom_currencies)

      Application.put_env(:ex_money, :custom_currencies, [
        # ISO collision — should log a warning
        {:USD, [name: "Bad Dupe"]},
        # Valid currency — should still register after the bad one
        {:XSTK, [name: "Survives Bad Neighbor"]}
      ])

      try do
        log =
          capture_log(fn ->
            assert :ok = Money.Application.register_custom_currencies()
          end)

        assert log =~ "Failed to register custom currency :USD"

        assert %Localize.Currency{code: :XSTK} = Money.Currency.Store.get(:XSTK)
      after
        if previous do
          Application.put_env(:ex_money, :custom_currencies, previous)
        else
          Application.delete_env(:ex_money, :custom_currencies)
        end
      end
    end

    test "missing :custom_currencies config is a no-op" do
      previous = Application.get_env(:ex_money, :custom_currencies)
      Application.delete_env(:ex_money, :custom_currencies)

      try do
        assert :ok = Money.Application.register_custom_currencies()
      after
        if previous do
          Application.put_env(:ex_money, :custom_currencies, previous)
        end
      end
    end
  end

  # ── Formatting ────────────────────────────────────────────────

  describe "Money.to_string/2 with a custom currency" do
    test "formats a custom currency using its registered symbol" do
      ensure_currency(:XFMT, name: "Formatted", symbol: "ş", digits: 2)

      assert {:ok, formatted} = Money.to_string(Money.new(:XFMT, "1234.5"))
      assert formatted == "ş 1,234.50"
    end

    test "to_string!/2 formats a custom currency" do
      ensure_currency(:XFMB, name: "Formatted Bang", symbol: "ß", digits: 2)

      assert Money.to_string!(Money.new(:XFMB, "10")) == "ß 10.00"
    end

    test "honours the registered :digits for a custom currency" do
      ensure_currency(:XFM4, name: "Four Digits", symbol: "Ω", digits: 4)

      assert {:ok, formatted} = Money.to_string(Money.new(:XFM4, "1"))
      assert formatted == "Ω 1.0000"
    end

    test "still formats ISO currencies via locale-aware resolution" do
      assert {:ok, "$1,234.50"} = Money.to_string(Money.new(:USD, "1234.5"))
    end
  end
end
