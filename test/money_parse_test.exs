defmodule MoneyTest.Parse do
  use ExUnit.Case

  describe "Money.parse/2 " do
    test "parses with currency code in front" do
      assert Money.parse("USD 100") == Money.new(:USD, 100)
      assert Money.parse("USD100") == Money.new(:USD, 100)
      assert Money.parse("USD 100 ") == Money.new(:USD, 100)
      assert Money.parse("USD100 ") == Money.new(:USD, 100)
      assert Money.parse("USD 100.00") == Money.new(:USD, "100.00")
    end

    test "parses with a single digit amount" do
      assert Money.parse("USD 1") == Money.new(:USD, 1)
      assert Money.parse("USD1") == Money.new(:USD, 1)
      assert Money.parse("USD9") == Money.new(:USD, 9)
    end

    test "parses with currency code out back" do
      assert Money.parse("100 USD") == Money.new(:USD, 100)
      assert Money.parse("100USD") == Money.new(:USD, 100)
      assert Money.parse("100 USD ") == Money.new(:USD, 100)
      assert Money.parse("100USD ") == Money.new(:USD, 100)
      assert Money.parse("100.00USD") == Money.new(:USD, "100.00")
    end

    @tag :digital_token
    test "parses digital tokens" do
      assert Money.new("BTC", "100") == Money.parse("100 BTC")
      assert Money.new("BTC", "100") == Money.parse("100 Bitcoin")
      assert Money.new("BTC", "100") == Money.parse("BTC 100")
      assert Money.new("BTC", "100") == Money.parse("Bitcoin 100")
    end

    test "parsing with currency strings that are not codes" do
      assert Money.parse("australian dollar 12346.45") == Money.new(:AUD, "12346.45")
      assert Money.parse("12346.45 australian dollars") == Money.new(:AUD, "12346.45")
      assert Money.parse("12346.45 Australian Dollars") == Money.new(:AUD, "12346.45")
      assert Money.parse("12 346 dollar australien", locale: "fr") == Money.new(:AUD, 12_346)
    end

    test "parses with locale specific separators" do
      assert Money.parse("100,00USD", locale: "de") == Money.new(:USD, "100.00")
    end

    test "parses euro (unicode symbol)" do
      assert Money.parse("99.99€") == Money.new(:EUR, "99.99")
    end

    test "currency filtering" do
      assert Money.parse("100 French francs") == Money.new(:FRF, 100)

      assert Money.parse("100 French francs", currency_filter: [:current]) ==
               {:error,
                {Money.UnknownCurrencyError,
                 "The currency \"French francs\" is unknown or not supported"}}
    end

    test "fuzzy matching of currencies" do
      assert Money.parse("100 eurosports", fuzzy: 0.8) == Money.new(:EUR, 100)

      assert Money.parse("100 eurosports", fuzzy: 0.9) ==
               {:error,
                {Money.UnknownCurrencyError,
                 "The currency \"eurosports\" is unknown or not supported"}}
    end

    # A form's empty field is cast with `Money.parse/2`, and ex_money_sql and
    # others match this error.
    test "a string with no amount reports the currency and an empty amount" do
      for string <- ["", "   ", " "] do
        assert Money.parse(string) ==
                 {:error, {Money.Invalid, "Unable to create money from :USD and \"\""}},
               inspect(string)
      end

      assert Money.parse("", locale: "de") ==
               {:error, {Money.Invalid, "Unable to create money from :EUR and \"\""}}

      assert Money.parse("USD") ==
               {:error, {Money.Invalid, "Unable to create money from :USD and \"\""}}

      assert Money.parse("", default_currency: false) ==
               {:error,
                {Money.Invalid,
                 "A currency code, symbol or description must be specified but was not found in \"\""}}
    end

    # Before 6.3.0 a tie went to the first name alphabetically: `fr`
    # "100 dollars" read as the Fiji dollar.
    test "a fuzzy match is refused where two currencies are equally close" do
      assert Money.parse("100 dollars", locale: "fr", fuzzy: 0.8) ==
               {:error,
                {Money.UnknownCurrencyError, "The currency \"dollars\" is unknown or not supported"}}

      assert {:error, {Money.UnknownCurrencyError, _message}} =
               Money.parse("kr 100", locale: "en", fuzzy: 0.8)
    end

    test "parsing fails if no currency and no default currency" do
      assert Money.parse("100", default_currency: false) ==
               {:error,
                {Money.Invalid,
                 "A currency code, symbol or description must be specified but was not found in \"100\""}}
    end

    test "parse with locale determining currency" do
      assert Money.parse("100", locale: "en") == Money.new(:USD, 100)
      assert Money.parse("100", locale: "de") == Money.new(:EUR, 100)
    end

    test "parse with a default currency" do
      assert Money.parse("100", default_currency: :USD) == Money.new(:USD, 100)
      assert Money.parse("100", default_currency: "USD") == Money.new(:USD, 100)
      assert Money.parse("100", default_currency: "australian dollars") == Money.new(:AUD, 100)
    end

    test "with locale overrides" do
      # A locale that has a regional override. The regional override
      # takes precedence and hence the currency is USD
      assert Money.parse("100", locale: "zh-Hans-u-rg-uszzzz") == Money.new(:USD, 100)

      # A locale that has a regional override and a currency
      # override uses the currency override as precedent over
      # the regional override. In this case, EUR
      assert Money.parse("100", locale: "zh-Hans-u-rg-uszzzz-cu-eur") == Money.new(:EUR, 100)
    end

    # Before 6.3.0 "($-127.54)" read as 127.54 dollars. Others read it as
    # -127.54, a negative marked twice, so it is refused.
    test "a sign inside accounting parentheses is refused" do
      assert Money.parse("($-127.54)", locale: "en") ==
               {:error, {Money.Invalid, "Unable to create money from :USD and \"(-127.54)\""}}
    end

    test "parse with negative numbers" do
      assert Money.parse("-127,54 €", locale: "fr") == Money.new(:EUR, "-127.54")
      assert Money.parse("-127,54€", locale: "fr") == Money.new(:EUR, "-127.54")

      assert Money.parse("€ 127,54-", locale: "nl") == Money.new(:EUR, "-127.54")
      assert Money.parse("€127,54-", locale: "nl") == Money.new(:EUR, "-127.54")

      assert Money.parse("($127.54)", locale: "en") == Money.new(:USD, "-127.54")

      assert Money.parse("CHF -127.54", locale: "de-CH") == Money.new(:CHF, "-127.54")
      assert Money.parse("-127.54 CHF", locale: "de-CH") == Money.new(:CHF, "-127.54")

      assert Money.parse("kr-127,54", locale: "da") == Money.new(:DKK, "-127.54")
      assert Money.parse("kr -127,54", locale: "da") == Money.new(:DKK, "-127.54")
    end

    test "de locale" do
      assert Money.parse("1.127,54 €", locale: "de") == Money.new(:EUR, "1127.54")
    end

    test "Round trip parsing" do
      assert Money.parse("1 127,54 €", locale: "fr") ==
               Money.new!(:EUR, "1127.54")
               |> Money.to_string!(locale: "fr")
               |> Money.parse(locale: "fr")
    end

    test "parsing strings that have `.` in them" do
      assert Money.parse("4.200,00 kr.", locale: "da") == Money.new(:DKK, "4200.00")
    end

    test "parse a string that has RTL markers" do
      assert Money.parse("\u200F1.234,56\u00A0د.م.\u200F", locale: "ar-MA") ==
               Money.new(:MAD, "1234.56")
    end

    test "a decimal mark may open or close the amount" do
      assert Money.parse(".5 USD", locale: "en") == Money.new(:USD, "0.5")
      assert Money.parse("5.USD", locale: "en") == Money.new(:USD, "5")
      assert Money.parse("5. USD", locale: "en") == Money.new(:USD, "5")
      assert Money.parse("USD 5.", locale: "en") == Money.new(:USD, "5")
      assert Money.parse("kr.5", locale: "da") == Money.new(:DKK, "5")
    end

    # Before 6.3.0 "$.50" read as fifty dollars: the period was taken as
    # part of the currency. It is the currency's only when CLDR writes the
    # currency with it, as `da` writes "kr."; otherwise it is the number's
    # decimal mark, or the amount is ambiguous and refused.
    # `de-AT` and `fr-CH` write a currency amount with other separators than a
    # plain number. Either is read, and `Money.new/3` reads a string amount the
    # same way. Both of `de-AT`'s sets mark the fraction with a comma, and the
    # euro's groups with a period, so a period is never its decimal point:
    # "100.00 EUR", which read as 100 euros before 6.3.0, is refused, as in `de`.
    test "de-AT and fr-CH amounts, read with either set of separators" do
      for {string, locale, currency, amount} <- [
            {"€ 1.234,56", "de-AT", :EUR, "1234.56"},
            {"1.234 EUR", "de-AT", :EUR, "1234"},
            {"1'234,56 CHF", "fr-CH", :CHF, "1234.56"},
            {"1'234.56 CHF", "fr-CH", :CHF, "1234.56"},
            {"100,00 CHF", "fr-CH", :CHF, "100.00"}
          ] do
        assert Money.parse(string, locale: locale) == Money.new(currency, amount),
               "#{locale} #{inspect(string)}"
      end

      assert Money.parse("100.00 EUR", locale: "de-AT") ==
               {:error, {Money.Invalid, "Unable to create money from :EUR and \"100.00\""}}

      assert Money.new(:EUR, "1.234", locale: "de-AT") == Money.new(:EUR, "1234")

      assert Money.new(:CHF, "1'234,56", locale: "fr-CH") == Money.new(:CHF, "1234.56")
    end

    test "a mark between the currency and the digits" do
      assert Money.parse("$.50", locale: "en") == Money.new(:USD, "0.50")
      assert Money.parse("USD.50", locale: "en") == Money.new(:USD, "0.50")
      assert Money.parse("Fr.5", locale: "de-CH") == Money.new(:CHF, "5")

      for {string, locale} <- [{"kr.5", "nb"}, {"€.5", "de"}] do
        assert Money.parse(string, locale: locale) ==
                 {:error, {Money.ParseError, "Could not parse #{inspect(string)}."}}
      end
    end

    # Before 6.3.0 these read as the wrong amount: the locale's grouping
    # separator was deleted wherever it stood, so "0.5 EUR" in `de` was 5.
    test "refuses an amount whose separators the locale does not write" do
      for {string, locale, amount} <- [
            {"0.5 EUR", "de", "0.5"},
            {"EUR 1.5", "de", "1.5"},
            {"1234.56 EUR", "de", "1234.56"},
            {"1,234.56 EUR", "de", "1,234.56"},
            {"0,5 USD", "en", "0,5"},
            {"1234,56 USD", "en", "1234,56"},
            {"1,2,3 USD", "en", "1,2,3"},
            {"1.234,56 USD", "en", "1.234,56"},
            {"USD 1 2", "en", "1 2"},
            {"1.23 EUR", "de", "1.23"},
            {"1,23 USD", "en", "1,23"}
          ] do
        [currency] = Regex.run(~r/[A-Z]{3}/, string)

        assert Money.parse(string, locale: locale) ==
                 {:error,
                  {Money.Invalid, "Unable to create money from :#{currency} and #{inspect(amount)}"}},
               "#{locale} #{inspect(string)}"
      end
    end

    test "Parse a money string that uses a non-breaking-space for a separator" do
      assert Money.parse("US$30\u00A0000,00", locale: :en_ZA, separators: :standard) ==
               Money.new(:USD, "30000.00")
    end

    # A period that is neither of the locale's separators is the decimal point
    # where it can be nothing else, as before 6.3.0.
    test "a period that is neither of the locale's separators reads where it can only be a decimal point" do
      assert Money.parse("100.00 €", locale: "fr") == Money.new(:EUR, "100.00")
      assert Money.parse("0.5 kr", locale: "sv") == Money.new(:SEK, "0.5")
      assert Money.new(:EUR, "10.50", locale: "fr") == Money.new(:EUR, "10.50")
    end

    # Before 6.3.0 "1.234 €" in `fr` read as 1.234 euros, where one who groups
    # with a period means 1234.
    test "a period that is neither of the locale's separators is refused where it could group" do
      for {string, locale, currency} <- [
            {"1.234 €", "fr", :EUR},
            {"1.234 kr", "sv", :SEK},
            {"1.234 zł", "pl", :PLN}
          ] do
        assert Money.parse(string, locale: locale) ==
                 {:error,
                  {Money.Invalid, "Unable to create money from #{inspect(currency)} and \"1.234\""}},
               "#{locale} #{inspect(string)}"
      end
    end

    # Swiss "Fr. –.15" and Dutch "€ -,50" write a dash for the zero before the
    # decimal mark, where a minus would stand. Before 6.3.0 they read as
    # negative amounts; they are refused until the convention is settled.
    test "a minus before a decimal mark with no digit ahead of it is refused" do
      for {string, locale} <- [
            {"Fr. –.15", "fr-CH"},
            {"Fr. -.15", "de-CH"},
            {"€ -,50", "nl"},
            {"-$.50", "en"},
            {"-.50 USD", "en"}
          ] do
        assert {:error, {Money.Invalid, _message}} = Money.parse(string, locale: locale),
               "#{locale} #{inspect(string)}"
      end

      assert Money.new(:USD, "-.5", locale: "en") ==
               {:error, {Money.Invalid, "Unable to create money from :USD and \"-.5\""}}

      assert Money.parse("$.50", locale: "en") == Money.new(:USD, "0.50")
    end

    # Before 6.3.0 a Swiss "15 Rp." (15 Rappen) read as 15 rupiah: `de-CH` gives
    # the rupiah the narrow symbol "Rp". A narrow letter abbreviation is now
    # read only for the locale's own currency.
    test "a narrow letter abbreviation is read only for the locale's own currency" do
      assert {:error, {Money.UnknownCurrencyError, _message}} =
               Money.parse("15 Rp.", locale: "de-CH")

      assert Money.parse("Rp 15.000", locale: "id") == Money.new(:IDR, "15000")
      assert Money.parse("100 Kč", locale: "cs") == Money.new(:CZK, "100")
      assert Money.parse("Fr. 5.-", locale: "de-CH") == Money.new(:CHF, "5")
    end

    # A currency sign naming one currency is read in any locale: `en-AU` writes
    # the euro "EUR" and its narrow symbol "€", and `de-CH` writes the euro
    # "EUR" only. A sign several currencies share is refused: `bg` leaves "₩"
    # to the North Korean won, but root gives it to both wons.
    test "a currency sign is read where it names one currency" do
      assert Money.parse("€1.00", locale: "en-AU") == Money.new(:EUR, "1.00")
      assert Money.parse("€1.00", locale: "es-MX") == Money.new(:EUR, "1.00")
      assert Money.parse("€ 15.40", locale: "de-CH") == Money.new(:EUR, "15.40")

      assert {:error, {Money.UnknownCurrencyError, _message}} =
               Money.parse("₩100", locale: "bg")

      assert {:error, {Money.UnknownCurrencyError, _message}} =
               Money.parse("¥100", locale: "en-AU")
    end

    # Currency text is matched after NFKC normalization, as TR35's loose
    # matching asks; the number is not, so a footnoted price is refused.
    test "currency text is matched after NFKC normalization, the number is not" do
      assert Money.parse("¥1", locale: "ja") == Money.new(:JPY, "1")
      assert Money.parse("＄1.00", locale: "en") == Money.new(:USD, "1.00")
      assert {:error, {Money.ParseError, _message}} = Money.parse("$5²", locale: "en")
    end

    # Before 6.3.0 a "$" several of the locale's currencies share read as
    # the New Zealand dollar. It names no one currency, so it is refused.
    test "a symbol several of the locale's currencies share is refused" do
      for locale <- ["fr", "es", "nl", "pt-PT"] do
        assert Money.parse("$2", locale: locale) ==
                 {:error,
                  {Money.UnknownCurrencyError, "The currency \"$\" is unknown or not supported"}},
               locale
      end

      assert Money.parse("2,00 $US", locale: "fr") == Money.new(:USD, "2.00")
      assert Money.parse("$2.00", locale: "en") == Money.new(:USD, "2.00")
    end

    # Before 6.3.0 `de` "73,460 €" read as 73.46 euros. Three fraction digits
    # in a currency of fewer may be a thousands group, so it is refused.
    test "three fraction digits after a single mark in a currency of fewer are refused" do
      for {string, locale} <- [{"73,460 €", "de"}, {"$59.568", "en"}, {"USD 1.234", "en"}] do
        assert {:error, {Money.Invalid, _message}} = Money.parse(string, locale: locale),
               "#{locale} #{inspect(string)}"
      end

      assert Money.parse("1.234,567 €", locale: "de") == Money.new(:EUR, "1234.567")
      assert Money.parse("0,123 €", locale: "de") == Money.new(:EUR, "0.123")
      assert Money.parse("KWD 1.234", locale: "en") == Money.new(:KWD, "1.234")
    end

    # Before 6.3.0 a Russian "6 300 Р" read as the ruble of 1991–1998 (RUR),
    # whose symbol "р." it folds to. A historic currency is read by its code
    # or name only.
    test "a historic currency is read by its code or name, not its symbol" do
      assert {:error, {Money.UnknownCurrencyError, _message}} =
               Money.parse("6 300 Р", locale: "ru")

      assert Money.parse("100 RUR", locale: "ru") == Money.new(:RUR, "100")
      assert Money.parse("100 ₽", locale: "ru") == Money.new(:RUB, "100")
    end

    # A Swiss whole-franc price writes a dash for its fraction.
    for locale <- ["de-CH", "fr-CH", "it-CH"],
        {string, amount} <- [
          {"CHF 5.-", "5"},
          {"CHF 5.\u2013", "5"},
          {"5.\u2013 CHF", "5"},
          {"Fr. 5.-", "5"},
          {"Fr. 5.--", "5"},
          {"CHF 1'234.\u2013", "1234"},
          {"CHF -5.-", "-5"},
          {"(CHF 5.-)", "-5"}
        ] do
      test "#{locale} reads #{inspect(string)} as CHF #{amount}" do
        assert Money.parse(unquote(string), locale: unquote(locale)) ==
                 Money.new(:CHF, unquote(amount))
      end
    end
  end
end
