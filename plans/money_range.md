# `Money.to_range_string/3` — formatting money ranges

**Status:** planning, last updated 2026-05-15

**Owner:** Money maintainers

## Goal

Add `Money.to_range_string/2,3` that formats a price range like `$20.00–$40.00` or `¥20～40` from two `Money.t()` values. Output uses the locale's CLDR range pattern (same one `Localize.Number.to_range_string/3` consumes from `miscPatterns.range`) and elides the currency symbol on the second value so the symbol is shared rather than duplicated — matching how human-written e-commerce prices typically read.

So:

```elixir
Money.to_range_string(Money.new(:USD, 20), Money.new(:USD, 40))
# => {:ok, "$20.00–40.00"}

Money.to_range_string(Money.new(:JPY, 20), Money.new(:JPY, 40), locale: "ja")
# => {:ok, "¥20～40"}

Money.to_range_string(Money.new(:EUR, 20), Money.new(:EUR, 40), locale: "fr")
# => {:ok, "20,00–40,00 €"}    # symbol shared at the end where French puts it
```

## Why share the symbol?

The native human-written form for nearly every locale shares the currency marker:

* English: `$20–40` reads naturally; `$20–$40` reads as machine output.
* Japanese: `¥20〜40` or `20〜40円` is canonical; `¥20〜¥40` is foreign-looking.
* French: `20–40 €` shares the trailing symbol; `20 €–40 €` is over-punctuated.
* German: `20–40 €` similarly.

CLDR ships only the locale-agnostic `range` pattern (`{0}–{1}` in en, `{0}～{1}` in ja, etc.) — it doesn't ship a currency-aware variant that knows to share. So the sharing is `Money`'s responsibility, sitting one layer above the per-value formatter.

## API

```elixir
@spec to_range_string(Money.t(), Money.t(), Keyword.t()) ::
        {:ok, String.t()} | {:error, {module(), String.t()}} | {:error, Exception.t()}
def to_range_string(money_start, money_end, options \\ [])

@spec to_range_string!(Money.t(), Money.t(), Keyword.t()) :: String.t() | no_return()
def to_range_string!(money_start, money_end, options \\ [])
```

No `Range`-struct overload — `Range` is integer-only in Elixir, and a `Money` range doesn't fit. The two-Money form is the only signature.

## Behaviour

1. Both `money_start` and `money_end` must have the same `currency`. If they differ, return `{:error, {Money.IncompatibleCurrencyError, "..."}}` — mixed-currency ranges are almost always a bug; the caller should explicitly convert before calling.

2. Format `money_start` via `Money.to_string(money_start, options)` — the user's `options` flow through unchanged. This handles `:locale`, `:format`, `:fractional_digits`, `:no_fraction_if_integer`, `:currency_symbol`, etc., exactly as per single-money formatting.

3. Format `money_end` via `Money.to_string(money_end, options_with_no_symbol)` where `options_with_no_symbol` is the caller's options with `currency_symbol: :none` forced (overriding any caller value). This is what produces the bare-number second endpoint that gets joined with the first formatted string.

4. If `money_start.amount == money_end.amount`, use the locale's `approximately` pattern (`~{0}` in en) wrapped around the formatted start value — matching `Localize.Number.to_range_string/3`'s collapse-to-approximately behaviour. The bare-second-value path is skipped.

5. Otherwise, fetch the locale's `range` pattern via the same code path `Localize.Number.to_range_string/3` uses (`Localize.Number.Format.misc_patterns_for/2`), then substitute `{0}` with `formatted_start` and `{1}` with `formatted_end` (the bare-number form). Return `{:ok, joined_string}`.

6. Same `:approximate` option `Localize.Number.to_range_string/3` accepts — when true, force the approximately pattern even if start ≠ end. Useful for "around $20" UX framing.

## Options

The function accepts every option `Money.to_string/2` accepts, plus:

* `:approximate` — boolean, default `false`. Forces the locale's approximately pattern wrapped around the formatted start value (the end value is ignored in this mode).

* `:locale` — passes through to both `Money.to_string` calls AND to the misc-pattern lookup that selects the range / approximately glyph.

Caller-supplied `currency_symbol:` is honoured **only on the start value**. The end value is unconditionally formatted with `currency_symbol: :none` regardless of what the caller passes — the design intent is symbol-sharing on the start. Document this clearly in the @doc; don't silently honour it on both endpoints.

If a caller genuinely wants both endpoints to carry the currency symbol (the current `Localize.Number.to_range_string/3` behaviour with `currency:`), they can call that lower-level function directly with two amounts and `currency: money.currency`. `Money.to_range_string` is opinionated about the symbol-sharing because that's the ergonomic value-add over the lower-level version.

## Implementation sketch

```elixir
def to_range_string(money_start, money_end, options \\ [])

def to_range_string(
      %Money{currency: c, amount: a} = money_start,
      %Money{currency: c, amount: b} = _money_end,
      options
    ) do
  approximate = Keyword.get(options, :approximate, false)

  cond do
    approximate or Decimal.equal?(a, b) ->
      format_approximately(money_start, options)

    true ->
      format_range(money_start, _money_end, options)
  end
end

def to_range_string(%Money{currency: c1}, %Money{currency: c2}, _options) do
  {:error,
   {Money.IncompatibleCurrencyError,
    "to_range_string requires both Money values to share a currency, got #{inspect(c1)} and #{inspect(c2)}"}}
end

defp format_range(money_start, money_end, options) do
  end_options = Keyword.put(options, :currency_symbol, :none)
  locale = Keyword.get(options, :locale, Localize.get_locale())

  with {:ok, formatted_start} <- to_string(money_start, options),
       {:ok, formatted_end} <- to_string(money_end, end_options),
       {:ok, language_tag} <- Localize.validate_locale(locale),
       {:ok, number_system} <- Localize.Number.System.number_system_from_locale(language_tag),
       {:ok, patterns} <- Localize.Number.Format.misc_patterns_for(language_tag, number_system) do
    result = Localize.Substitution.substitute([formatted_start, formatted_end], patterns.range)
    {:ok, IO.iodata_to_binary(result)}
  end
end

defp format_approximately(money, options) do
  locale = Keyword.get(options, :locale, Localize.get_locale())

  with {:ok, formatted} <- to_string(money, options),
       {:ok, language_tag} <- Localize.validate_locale(locale),
       {:ok, number_system} <- Localize.Number.System.number_system_from_locale(language_tag),
       {:ok, patterns} <- Localize.Number.Format.misc_patterns_for(language_tag, number_system) do
    result = Localize.Substitution.substitute([formatted], patterns.approximately)
    {:ok, IO.iodata_to_binary(result)}
  end
end
```

The `format_range` and `format_approximately` helpers are direct mirrors of the corresponding paths in `Localize.Number.to_range_string/3` (lib/localize/number.ex around lines 261–283), with the only difference being that the `end_options` hard-set `currency_symbol: :none`. Rather than duplicating the misc-patterns lookup, consider lifting `Localize.Number.to_range_string/3` to expose an internal `format_pair_with_separator/4` helper that takes two pre-formatted strings — but only if the duplication actually bothers us; the lookup is two lines.

## Doctests

```elixir
iex> Money.to_range_string(Money.new(:USD, 20), Money.new(:USD, 40))
{:ok, "$20.00–40.00"}

iex> Money.to_range_string(Money.new(:USD, 20), Money.new(:USD, 40), no_fraction_if_integer: true)
{:ok, "$20–40"}

iex> Money.to_range_string(Money.new(:JPY, 20), Money.new(:JPY, 40), locale: "ja")
{:ok, "¥20～40"}

iex> Money.to_range_string(Money.new(:EUR, 20), Money.new(:EUR, 40), locale: "fr")
{:ok, "20,00–40,00 €"}

iex> Money.to_range_string(Money.new(:USD, 20), Money.new(:USD, 20))
{:ok, "~$20.00"}

iex> Money.to_range_string(Money.new(:USD, 20), Money.new(:USD, 40), approximate: true)
{:ok, "~$20.00"}

iex> Money.to_range_string(Money.new(:USD, 20), Money.new(:EUR, 40))
{:error, {Money.IncompatibleCurrencyError, "to_range_string requires both Money values to share a currency, got :USD and :EUR"}}
```

The French case is the load-bearing test — it confirms that the trailing `€` on the start endpoint is preserved while the second endpoint omits the currency, and that the locale-correct decimal comma and locale-correct dash glyph appear correctly.

## Testing

* **Doctests** above cover the happy paths (en, ja, fr, equal endpoints, approximate, mismatched currency).
* **Property test**: for any `(currency, amount, options)` triple, `to_range_string(m, m, options)` produces the same output as `Localize.Number.to_range_string(m.amount, m.amount, options)` wrapped with the approximately pattern — the equal-endpoint collapse is just the `Money.to_string` of one value through the `~{0}` pattern.
* **Locale coverage**: explicit assertions for `en`, `en-GB`, `fr`, `fr-CH`, `de`, `ja`, `ar` (RTL), `bn` (non-Latin digits) — confirms the misc-patterns lookup picks up locale-correct dashes (`–` vs `—` vs `〜` vs `～`) and that the currency-symbol elision works for currencies whose symbol is suffixed (€) as well as prefixed ($, ¥).
* **Plural-form test** for the equal-endpoint approximately path with currencies whose name varies by count (the `:format → :long` path that produces `"1 US dollar"` vs `"5 US dollars"`).

## Open questions

* **Should we accept a `Money.Range.t()` struct as a third overload?** If/when Money introduces its own `Range` struct (not the Elixir built-in), `to_range_string(%Money.Range{})` becomes natural. Defer until that struct exists.

* **Should `:currency_symbol` on the second endpoint be configurable?** Some callers may genuinely want both symbols — e.g. when the start and end currencies differ in some future variant of this function that converts and shows both. Current plan: hard-code `:none` for the end. Reconsider only if a real use case appears.

* **Spacing around the dash for spaced-currency locales.** In French, single-money output is `20,00 €` with a no-break space. The range pattern for fr is `{0}–{1}` (no spaces around the dash). Concatenating gives `20,00 €–40,00 €` for the non-shared case and `20,00–40,00 €` for the shared case — the second is the desired output. Confirm visually that the no-break space lands correctly on the right end and not on the dash.

* **`Decimal.equal?/2` for the equal-endpoint collapse** — Money amounts are Decimals; equality must be value-based, not struct-equality (so `Decimal.new("20")` and `Decimal.new("20.00")` compare equal). Use `Decimal.equal?/2`, not `==`.

## Phasing

Single phase, ~half-day implementation:

1. Add `to_range_string/2,3` and `to_range_string!/2,3` to `Money`.
2. Add the helpers (or factor out `Localize.Number.to_range_string/3`'s pattern-lookup if the duplication bothers us).
3. Add `Money.IncompatibleCurrencyError` if it doesn't already exist (check first).
4. Doctests + locale-coverage tests.
5. Update README with one money-range example.
