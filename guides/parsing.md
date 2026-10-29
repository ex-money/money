# Parsing money

`Money.parse/2` reads a string that holds one amount of money, such as `"$1,234.56"`, `"1.234,56 €"` or `"100 Swiss francs"`, into a `t:Money.t/0`. `Money.new/3` reads a string amount, such as `"1.234,56"`, with the separators of a locale. Both are built on `Localize.Number.Parser.parse_currency_amount/2` and `Localize.Number.Parser.parse/2`, which read the text with the locale's CLDR data.

The rule behind every decision in this guide is that money is never guessed. A string that could be read as two different amounts, or in two different currencies, is refused with an error rather than read as one of them. Failing to parse is always better than returning the wrong money.

## Quick start

```elixir
iex> Money.parse("USD 100")
Money.new(:USD, "100")

iex> Money.parse("$1,234.56", locale: "en")
Money.new(:USD, "1234.56")

iex> Money.parse("1.234,56 €", locale: "de")
Money.new(:EUR, "1234.56")

iex> Money.parse("CHF 1’234.56", locale: "de-CH")
Money.new(:CHF, "1234.56")

iex> Money.parse("100 Euro", locale: "de")
Money.new(:EUR, "100")
```

The `:locale` option decides how the text is read. Without it, `Localize.get_locale/0` is used.

## Finding the currency

The currency may come before or after the amount, with or without a space between them. It may be written as:

* **An ISO 4217 code** — `"USD 100"`, `"100 usd"`. Codes are matched in any case.

* **A symbol** — `"$1,234.56"` in `en`, `"$au 12346"` in `fr`.

* **A name, singular or plural** — `"100 euros"` in `en`, `"dollar australien 12346"` in `fr`. Names are matched in any case.

* **A digital token** — when the optional `:digital_token` dependency is installed, by its short name, long name or symbol: `"BTC 1.5"`, `"₿1.5"`. A name is read when one token alone has it, or one native token among those that do: `"BTC"` is Bitcoin, though wrapped bitcoins on other chains share the name.

Currency text is compared after Unicode NFKC normalization, as CLDR's loose matching asks, so a fullwidth `"＄"` is the dollar and `ja` `"¥1000"` is the yen, which `ja` writes `"￥"`.

```elixir
iex> Money.parse("$au 12346", locale: "fr")
Money.new(:AUD, "12346")

iex> Money.parse("¥1000", locale: "ja")
Money.new(:JPY, "1000")

iex> Money.parse("BTC 1.5")
Money.new("BTC", "1.5")

iex> Money.parse("Q9PB7XDNF 1.5")
Money.new("Q9PB7XDNF", "1.5")
```

### Currency text that is refused

Some currency text names more than one currency, or a currency only in a context the string does not carry. It is refused, with `Money.UnknownCurrencyError` unless said otherwise:

* **A symbol several currencies share** — `"$"` in `fr` is the narrow symbol of the Canadian, US, Australian and other dollars, so `"$2.00"` is refused there. Write `"2,00 $US"`, or the code.

* **Another country's narrow abbreviation** — CLDR writes a currency's narrow symbol only where the context makes the currency clear, so an amount reads a letter abbreviation only for the locale's own currency. Swiss `"15 Rp."` is 15 Rappen, not 15 rupiah, though `de-CH` gives the rupiah the narrow symbol `"Rp"`. A currency sign such as `"€"` or `"₹"` is different: it is read in any locale where it names one currency, there and in CLDR's root data, so `en-AU` `"€5"` and `de-CH` `"€ 15.40"` are euros.

* **A currency sign several currencies share** — `"¥"` is the yen and the yuan, `"₩"` both wons, and in `en-AU` `"£"` the pound and five others, so outside the locales whose own currency it is, such a sign is refused. `bg` writes the South Korean won `"KRW"`, but `"₩5"` is still refused there.

* **A historic currency's symbol** — symbols are reused, so a currency no longer in use is read only by its code or its name. A Russian `"6 300 Р"` is not the ruble of 1991–1998, whose symbol is `"р."`; `"100 RUR"` reads.

* **A symbol that a digital token shares** — with `:digital_token` installed, text such as `"₮"` names both the Mongolian tugrik and Tether, so it is refused with `Money.ParseError`, except in a locale whose own currency it names: `mn` `"₮5"` is the tugrik.

* **A token name several tokens share** — `"ETH"` names thirteen native tokens (Ethereum Ether and one per layer-two chain), and `"USDT"`, `"USDC"` and `"DAI"` one token per chain, so they are refused rather than read as whichever is first in digital_token's index. Write the token identifier of the one you mean: `Money.parse("Q9PB7XDNF 5")` or `Money.new("Q9PB7XDNF", 5)`. An identifier has digits in it, so a space separates it from the number, and an amount that also reads another way is refused: Terra's short names are `"LUNA"` and `"LUNA2"`, so `fr` `"LUNA2 234"` is 234 Terra and 2 234 Terra, and is neither.

```elixir
iex> Money.parse("$2.00", locale: "fr")
{:error,
 {Money.UnknownCurrencyError, "The currency \"$\" is unknown or not supported"}}

iex> Money.parse("2,00 $US", locale: "fr")
Money.new(:USD, "2.00")

iex> Money.parse("15 Rp.", locale: "de-CH")
{:error,
 {Money.UnknownCurrencyError,
  "The currency \"Rp.\" is unknown or not supported"}}

iex> Money.parse("Rp 15.000", locale: "id")
Money.new(:IDR, "15000")

iex> Money.parse("6 300 Р", locale: "ru")
{:error,
 {Money.UnknownCurrencyError, "The currency \"Р\" is unknown or not supported"}}

iex> Money.parse("100 RUR", locale: "ru")
Money.new(:RUR, "100")
```

## Reading the amount

The amount is read with the separators the locale uses for that currency, and its groups must be the sizes the locale writes. `de` groups with a period and marks decimals with a comma; `fr` groups with a space; `de-CH` groups with an apostrophe.

```elixir
iex> Money.parse("1 234,56 €", locale: "fr")
Money.new(:EUR, "1234.56")

iex> Money.parse("1.234,567 €", locale: "de")
Money.new(:EUR, "1234.567")
```

`de-AT` and `fr-CH` write a currency amount with other separators than a plain number. Either set is read, and text the two would read as different amounts is refused.

```elixir
iex> Money.parse("€ 1.234,56", locale: "de-AT")
Money.new(:EUR, "1234.56")

iex> Money.parse("1'234,56 CHF", locale: "fr-CH")
Money.new(:CHF, "1234.56")
```

### Signs

A minus may stand before the currency, between the currency and the amount, or after the amount, and the parentheses of an accounting format make an amount negative. The Unicode minus `"−"` reads as a minus. A Swiss whole amount written with a dash for its fraction, `"5.–"`, reads as a whole amount.

```elixir
iex> Money.parse("-$1,234.56", locale: "en")
Money.new(:USD, "-1234.56")

iex> Money.parse("($1,234.56)", locale: "en")
Money.new(:USD, "-1234.56")

iex> Money.parse("€ 127,54-", locale: "nl")
Money.new(:EUR, "-127.54")

iex> Money.parse("kr-127,54", locale: "da")
Money.new(:DKK, "-127.54")

iex> Money.parse("−1 234,56 kr", locale: "sv")
Money.new(:SEK, "-1234.56")

iex> Money.parse("CHF 5.–", locale: "de-CH")
Money.new(:CHF, "5")
```

A decimal mark may open the amount, so `"$.50"` is fifty cents.

```elixir
iex> Money.parse("$.50", locale: "en")
Money.new(:USD, "0.50")
```

### Amounts that are refused

An amount that could be read as two different amounts is refused with `Money.Invalid`:

* **Groups the locale does not write** — `de` `"1.23 EUR"` is not 123 euros.

* **A period that could group thousands** — in `fr`, which groups with a space, `"1.234 €"` could be 1.234 or 1234 euros.

* **Three fraction digits in a currency of fewer** — one to three digits, a decimal mark and three more may be a thousands group written with other separators. German `"1,599 €"` is a fuel price, but a shop writing English separators means 1599. Such an amount is refused for any currency of fewer than three decimal places, in every locale: `de` `"73,460 €"`, `en` `"$59.568"`. An amount under one, such as `"0,123 €"`, and one with a group separator, such as `"1.234,567 €"`, have one reading and are read.

* **Another locale's separators** — `en` `"USD 1.234,56"`.

* **A sign and parentheses together** — `"($-5)"` is -5 dollars to some readers and 5 to others.

* **A minus before a bare decimal mark** — Swiss `"Fr. –.15"` and Dutch `"€ -,50"` write a dash for the zero, so `"-$.50"` could be -0.50 or 0.50.

```elixir
iex> Money.parse("1.23 EUR", locale: "de")
{:error, {Money.Invalid, "Unable to create money from :EUR and \"1.23\""}}

iex> Money.parse("1.234 €", locale: "fr")
{:error, {Money.Invalid, "Unable to create money from :EUR and \"1.234\""}}

iex> Money.parse("73,460 €", locale: "de")
{:error, {Money.Invalid, "Unable to create money from :EUR and \"73,460\""}}

iex> Money.parse("$59.568", locale: "en")
{:error, {Money.Invalid, "Unable to create money from :USD and \"59.568\""}}

iex> Money.parse("($-5)", locale: "en")
{:error, {Money.Invalid, "Unable to create money from :USD and \"(-5)\""}}
```

Text that is not one amount of money is refused with `Money.ParseError`. The number itself is never normalized, so the footnote of `"$5²"` is not read as a digit.

```elixir
iex> Money.parse("$5²", locale: "en")
{:error, {Money.ParseError, "Could not parse \"$5²\"."}}

iex> Money.parse("100 USD and 5 EUR")
{:error, {Money.ParseError, "Could not parse \"100 USD and 5 EUR\"."}}
```

## Options

### A default currency

A string with no currency takes the locale's currency, or the one given as `:default_currency`. With `default_currency: false` it is an error.

```elixir
iex> Money.parse("100", locale: "en")
Money.new(:USD, "100")

iex> Money.parse("100", default_currency: :EUR)
Money.new(:EUR, "100")

iex> Money.parse("100", default_currency: false)
{:error,
 {Money.Invalid,
  "A currency code, symbol or description must be specified but was not found in \"100\""}}
```

### Choosing the currencies to match

`:only` and `:except` take currency codes or the currency types `:current`, `:historic`, `:tender`, `:unannotated` and `:all`.

```elixir
iex> Money.parse("100 euro", only: [:EUR, :USD])
Money.new(:EUR, "100")

iex> Money.parse("100 euro", except: [:EUR])
{:error,
 {Money.UnknownCurrencyError,
  "The currency \"euro\" is unknown or not supported"}}
```

### Fuzzy matching

`:fuzzy` takes a number between `0.0` and `1.0`, and a currency name at least that close by `String.jaro_distance/2` is matched. Numbers above `0.8` keep false matches rare. Currency text that two currencies match equally closely is refused: `fr` `"dollars"` is as close to the Fiji dollar as to the Rhodesian dollar.

```elixir
iex> Money.parse("100 eurosports", fuzzy: 0.8)
Money.new(:EUR, "100")

iex> Money.parse("100 dollars", locale: "fr", fuzzy: 0.8)
{:error,
 {Money.UnknownCurrencyError,
  "The currency \"dollars\" is unknown or not supported"}}
```

## String amounts in `Money.new/3`

`Money.new/3` reads a string amount with the `:locale`'s separators for the currency, by the same rules for groups and signs as `Money.parse/2`.

```elixir
iex> Money.new(:EUR, "1.234,56", locale: "de")
Money.new(:EUR, "1234.56")

iex> Money.new(:EUR, "1234.56", locale: "de")
{:error, {Money.Invalid, "Unable to create money from :EUR and \"1234.56\""}}
```

The three-fraction-digit rule does not apply to `Money.new/3`. A string amount given to it is usually a decimal a program produced, not text a person wrote, so `Money.new(:USD, "1.234")` is 1.234 dollars where `Money.parse("USD 1.234")` is refused.

```elixir
iex> Money.new(:USD, "1.234")
Money.new(:USD, "1.234")

iex> Money.parse("USD 1.234")
{:error, {Money.Invalid, "Unable to create money from :USD and \"1.234\""}}
```

A program that holds a decimal string should pass it to `Money.new/3` with a locale whose decimal mark is a period, such as `"en"`, or convert it with `Decimal.new/1` first.

## Errors

`Money.parse/2` returns `{:error, {exception_module, message}}`:

* **`Money.UnknownCurrencyError`** — the currency text names no currency, or names more than one.

* **`Money.Invalid`** — the currency was found but the amount cannot be read with the locale's separators for it, or the string names no currency and there is no default.

* **`Money.ParseError`** — the string is not one amount of money, or its currency text names both an ISO 4217 currency and a digital token.

A locale that is not installed is refused before any of these, with the `Localize.LocaleNotFoundInCacheError` exception itself, as `Money.new/3` returns an invalid locale. Formatting falls back to a parent locale's data or to English when a locale is missing, but parsing cannot: with English data `en-AU` `"$5"` would be US dollars. Install the locales you parse with `mix localize.download_locales`, or set `config :localize, allow_runtime_locale_download: true`.

## Changes in 6.3.0

Parsing moved onto Localize in ex_money 6.3.0, which reads what Localize formats in a locale's own style, and stopped guessing. Some strings that 6.2 read are now refused, because 6.2 read them as the wrong amount or could have meant another: `de` `"1.5 EUR"` was 15 euros, `en` `"$.75"` was 75 dollars, and `fr-CH` `"1.00 fr."` was the Rwandan franc. Each change is listed in the [changelog](https://hexdocs.pm/ex_money/changelog.html).
