if Code.ensure_loaded?(DigitalToken) do
  defmodule Money.DigitalToken.Test do
    use ExUnit.Case, async: true

    test "Creating digital token money" do
      assert %Money{} = Money.new("BTC", "100")
      assert %Money{} = Money.new("X9J9K872S", 100)
      assert %Money{} = Money.new("Terra", 100)
      assert %Money{} = Money.new("4H95J0R2X", "100.234235")
    end

    test "Formatting digital token" do
      assert {:ok, "₿100.234235"} = Money.to_string(Money.new("BTC", "100.234235"))
    end

    # A token amount is written in the root locale's form, "₿1.234", in every
    # locale. It is read with the locale's separators and the root locale's,
    # and refused where the two differ, so it never reads as another amount.
    describe "token amounts and symbols" do
      test "a token's symbol names it, so what to_string/2 writes parses back" do
        {:ok, btc} = DigitalToken.validate_token("BTC")
        money = Money.new(btc, "1.234")
        {:ok, string} = Money.to_string(money)

        assert Money.parse(string, locale: "en") == money
        assert Money.parse(string, locale: "fr") == money
      end

      test "a token amount reads where the locale and the root agree or only one reads" do
        {:ok, btc} = DigitalToken.validate_token("BTC")

        for {string, locale, amount} <- [
              {"₿1234.56", "de", "1234.56"},
              {"₿0.00012345", "de", "0.00012345"},
              {"1,5 BTC", "de", "1.5"},
              {"1,234.56 BTC", "de", "1234.56"}
            ] do
          assert Money.parse(string, locale: locale) == Money.new(btc, amount),
                 "#{locale} #{inspect(string)}"
        end

        assert Money.new(btc, "1234.56", locale: "de") == Money.new(btc, "1234.56")
        assert Money.new(btc, "1,5", locale: "de") == Money.new(btc, "1.5")
      end

      # `₮` is Tether's symbol and the tugrik's in CLDR, so it names neither.
      test "a symbol that names a token and an ISO 4217 currency is refused" do
        assert Money.parse("₮5", locale: "en") ==
                 {:error, {Money.ParseError, "Could not parse \"₮5\"."}}

        assert Money.parse("MNT 5", locale: "en") == Money.new(:MNT, "5")
      end

      # In a locale whose own currency a symbol names, that currency takes it.
      test "a symbol a token shares is the locale's own currency there" do
        assert Money.parse("₮5", locale: "mn") == Money.new(:MNT, "5")
        assert Money.parse("K5", locale: "my") == Money.new(:MMK, "5")
      end

      # A name names a token when one token alone has it, or one native token
      # among those that do: "BTC" is Bitcoin, though wrapped bitcoins on
      # other chains share the name. "ETH" names thirteen native tokens and
      # "USDT" one per chain, so neither is read as whichever came first.
      test "a token name several tokens share is refused" do
        assert Money.parse("BTC 1", locale: "en") == Money.new("4H95J0R2X", "1")
        assert Money.parse("SOL 5", locale: "en") == Money.new("20J63Z4N3", "5")

        for name <- ["ETH", "USDT", "USDC"] do
          assert {:error, {Money.UnknownCurrencyError, message}} =
                   Money.parse("#{name} 5", locale: "en")

          assert message =~ "digital tokens"

          assert {:error, {Money.UnknownCurrencyError, ^message}} = Money.new(name, 5)
        end

        assert Money.new("Q9PB7XDNF", 5) == Money.new("Q9PB7XDNF", "5")
      end

      # An identifier has digits in it, so a space separates it from the
      # amount, and an amount that also reads another way is refused.
      test "a token identifier names its token" do
        for {string, locale, token_id, amount} <- [
              {"Q9PB7XDNF 5", "en", "Q9PB7XDNF", "5"},
              {"5 Q9PB7XDNF", "en", "Q9PB7XDNF", "5"},
              {"X9J9K872S 1.5", "en", "X9J9K872S", "1.5"},
              {"Q9PB7XDNF 1,5", "de", "Q9PB7XDNF", "1.5"},
              {"-4H95J0R2X 2", "en", "4H95J0R2X", "-2"}
            ] do
          assert Money.parse(string, locale: locale) == Money.new(token_id, amount),
                 "#{locale} #{inspect(string)}"
        end

        for string <- ["Q9PB7XDNF5", "5Q9PB7XDNF"] do
          assert {:error, {Money.ParseError, _}} = Money.parse(string, locale: "en")
        end

        # Terra's short names are "LUNA" and "LUNA2", so `fr` "LUNA2 234" is
        # 234 Terra and 2 234 Terra.
        assert Money.parse("LUNA2 234", locale: "en") == Money.new("NGXHD2ZFQ", "234")
        assert Money.parse("LUNA 2 234", locale: "fr") == Money.new("NGXHD2ZFQ", "2234")
        assert {:error, {Money.ParseError, _}} = Money.parse("LUNA2 234", locale: "fr")
      end

      # An inspected token amount is an expression that gives the same money.
      test "a token amount inspects as the name or identifier that reads it back" do
        for token_id <- ["4H95J0R2X", "Q9PB7XDNF", "X9J9K872S", "SS42KQQFF"] do
          money = Money.new(token_id, "5")
          {inspected, _binding} = Code.eval_string(inspect(money))
          assert inspected == money, token_id
        end

        assert inspect(Money.new("4H95J0R2X", 5)) == ~s|Money.new("BTC", "5")|
        assert inspect(Money.new("Q9PB7XDNF", 5)) == ~s|Money.new("Q9PB7XDNF", "5")|
      end

      # 20 ISO 4217 codes are also a token's short name, `EUR` among them.
      test "an ISO 4217 code names its currency, not a token of the same short name" do
        assert Money.parse("EUR 5", locale: "en") == Money.new(:EUR, "5")
        assert Money.parse("5 NOK", locale: "en") == Money.new(:NOK, "5")
        assert Money.parse("5", locale: "en", default_currency: :EUR) == Money.new(:EUR, "5")
      end

      test "a token amount the two read differently is refused" do
        {:ok, btc} = DigitalToken.validate_token("BTC")

        assert {:error, {Money.Invalid, _}} = Money.parse("₿1.234", locale: "de")
        assert {:error, {Money.Invalid, _}} = Money.parse("1,234 BTC", locale: "de")
        assert {:error, {Money.Invalid, _}} = Money.new(btc, "1.234", locale: "de")
      end
    end
  end
end
