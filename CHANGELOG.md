# Changelog

**Note** `ex_money` 5.17.0 and later is supported on Elixir 1.12 and later versions only.

## Money v6.0.0

This is the changelog for Money v6.0.0 released on May 8th, 2026. For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/money/tags)

## Enhancements

* Supports `Decimal` version 3.0.0.

## Money v6.0.0-rc.0

This is the changelog for Money v6.0.0 released on April 2nd, 2026. For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/money/tags)

This is a major release that replaces the `ex_cldr` family of dependencies with the new `localize` package. See the [Migration from 5.x to 6.0](#migration-from-5x-to-60) section in the README for upgrade instructions.

### Breaking Changes

* The `ex_cldr`, `ex_cldr_numbers`, and `ex_cldr_units` dependencies have been replaced by `localize`.

* The CLDR backend system has been removed entirely. There is no longer a need to define a backend module (e.g. `MyApp.Cldr`) or configure `use Cldr, providers: [Money]`. The `Money.Backend` module has been deleted.

* The `:backend` option has been removed from all public functions including `Money.new/3`, `Money.to_string/2`, `Money.parse/2`, and `Money.localize/2`. Locale resolution now uses `Localize.get_locale/0` by default.

* The `Money.default_backend!/0` and `Money.default_backend/0` functions have been removed.

* The `Money.cldr_backend_provider/1` callback has been removed.

* The configuration keys `default_cldr_backend` (in `:ex_money`) and `default_backend` (in `:ex_cldr`) are no longer used.

* Error messages from currency validation have changed. For example, `"The currency :ZZZ is unknown"` is now `"The currency :ZZZ is not known."` (the message comes from `Localize.UnknownCurrencyError`).

* `gringotts` support is removed.

* Currency lists returned by `Money.Currency.known_current_currencies/0`, `Money.Currency.known_historic_currencies/0`, and `Money.Currency.known_tender_currencies/0` have been updated to reflect newer CLDR data. Some currencies have moved between current and historic status.

### Enhancements

* All CLDR functionality is now provided by the single `localize` package, simplifying the dependency tree and removing the need for compile-time backend configuration.

* Custom currencies are now managed in `ex_money` rather than `localize`. See `Money.Currency.new`.

* Locale management is now handled at runtime via `Localize.get_locale/0` and `Localize.put_locale/1`, consistent with how `Gettext` manages locales.

* `digital_token` is now an explicit optional dependency rather than a transitive dependency through `ex_cldr`.

* The `Money.Subscription.Plan.to_string/2` function now uses `Localize.Unit` for compound currency-per-unit formatting.

### Migration from 5.x

See the [Migration from 5.x to 6.0](#migration-from-5x-to-60) section in the README for detailed upgrade instructions.

## Money v5.24.2

This is the changelog for Money v5.24.2 released on January 30th, 2026.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/money/tags)

### Bug Fixes

* Fix deprecated map.field notation in `Money.parse_decimal/4`. Thanks to @oliver-kriska for the PR. Closes #191.

## Money v5.24.1

This is the changelog for Money v5.24.1 released on January 20th, 2026.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/money/tags)

### Bug Fixes

* Fixes casting a binary currency code that is both a valid ISO4217 currency code and a valid digital currency short code (for example, "TRY"). Precedence is given to returning the ISO4217 code (this was not the case in v5.24.0).

## Money v5.24.0 (deprecated and retired)

This is the changelog for Money v5.24.0 released on January 18th, 2026.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/money/tags)

### Bug Fixes

* Fixes compile warnings on Elixir 1.20.

* Fix examples in README.md to align with the current `inspect/2` output. Thanks very much to @carlgleisner for the PR (and apologies for the long delayed merge). Closes #188.

### Enhancements

* Add `Money.spread/3` to proportionally allocate (that is, spread) a money amount amongst a list of amounts or integers. Thanks to @jdewar for the PR and great patience. Closes #175.

* Add support for custom currency codes. A custom currency code is created with `Cldr.Currency.new/2` and is distinguised from an ISO4217 code by being at least 4 characters long (ISO4217 codes are always 3 characters long). The first character must be a Latin alphabetic character. The additional characters must be Latin alphanumeric characters.

## Money v5.23.0

This is the changelog for Money v5.23.0 released on January 15th, 2026.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/money/tags)

### Enhancements

* Adds `Money.sum!/2`. Thanks to @andreas-ementio for the PR. Closes #187.

## Money v5.22.0

This is the changelog for Money v5.22.0 released on August 15th, 2025.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/money/tags)

### Enhancements

* Adds `Money.Subscription.Plan.to_string/2` to return a localized string representation of a subscription plan. The implementation is conditional on [ex_cldr_units](https://hex.pm/packages/ex_cldr_units) being configured as a dependency in `mix.exs` and `Cldr.Unit` being added as a provider in the CLDR backend module. Thanks to @peaceful-james for the suggestion. Closes #186.

## Money v5.21.0

This is the changelog for Money v5.21.0 released on March 30th, 2025.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/money/tags)

### Enhancements

* Add `JSON.Encoder` implementation to support serializing money types with Elixir's JSON module. Thanks to @jfpedroza for the PR. Closes #182.

## Money v5.20.0

This is the changelog for Money v5.20.0 released on March 18th, 2025.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/money/tags)

### Soft Deprecation

* The option `:fractional_digits` for `Money.from_integer/3` has been deprecated in favour of `:currency_digits` for consistency with `Money.round/2` and functions in [ex_cldr_numbers](https://hex.pm/packages/ex_cldr_numbers). `:fractional_digits` will continue to be supported for an indefinite period.

### Bug Fixes

* Ensure `Money.split/3` always returns a remainder that is greater than or equal to 0. Thanks to @jdewar for the report and @coladarci, @Wigny for their collaboration. Closes #173.

* Allow a [non-breaking-space](https://en.wikipedia.org/wiki/Non-breaking_space) to be part of a number string. Some locales (like `en-ZA`) will format numbers with a nbsp when using standard separators for that locale.

* Fix documentation for `Money.ExchangeRates` replacing `:exchange_rate_service` with `:auto_start_exchange_rate_service`. Thanks to @cw789 for the PR. Closes #174.

### Enhancements

* Update to [CLDR 47](https://cldr.unicode.org/downloads/cldr-47) data including update to ISO 4217 currency information.

* Support passing rounding options to `Money.split/3`.

## Money v5.19.2

This is the changelog for Money v5.19.2 released on February 13th, 2025.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/money/tags)

### Bug Fixes

* Fix using Elixir 1.18's JSON module in `ex_money` (specifically decoding exchange rates). Thanks to @allenwyma and @maikelthedev for the report. Closes #176.

* Document `currency_symbol: :none` option for `Money.to_string/2`. This option formats the money amount without a currency symbol. This may be useful for UI forms that separate the currency and the amount for input. Requires [ex_cldr_numbers version 2.33.6](https://hex.pm/packages/ex_cldr_numbers/2.33.6) or later.

* Fix parsing money strings that contain trailing [RTL markers](https://en.wikipedia.org/wiki/Implicit_directional_marks). Requires [ex_cldr_currencies version 2.16.4](https://hex.pm/packages/ex_cldr_currencies/2.16.4) or later.

## Money v5.19.1

This is the changelog for Money v5.19.1 released on January 22nd, 2025.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/money/tags)

### Bug Fixes

* Fixes `Money.within/3` when `min` and `max` are the same. Thanks to @joewunderlich for the report. Closes #177.

## Money v5.19.0

This is the changelog for Money v5.19.0 released on January 1st, 2025.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/money/tags)

### Deprecations

* `Money.default_backend/0` is soft deprecated in favor of `Money.default_backend!/0` whose naming better expresses the side effect of an exception being raised if no default backend is configured.

### Bug Fixes

* Surface an error exception if, when starting the exchange rates service, no `Money.default_backend!/0` is configured.

## Money v5.18.0

This is the changelog for Money v5.18.0 released on September 18th, 2024.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/money/tags)

### Enhancements

* Adds `min/2`, `max/2`, `min!/2`, `max!/2`, `clamp/3`, `clamp!/3`, `negate/1`, `negate!/1` and `within?/3`.

## Money v5.17.2

This is the changelog for Money v5.17.2 released on September 18th, 2024.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/money/tags)

### Bug Fixes

* Fix implementation of `Money.exclude_protocol_implementation/1` for `Jason.Encoder`. Thanks to @wkirschbaum for the PR. Closes #171.

### Enhancements

* Add  `Money.exclude_protocol_implementation/1` for `String.Chars`. Thanks to @wkirschbaum for the PR. Closes #172.

## Money v5.17.1

This is the changelog for Money v5.17.1 released on September 6th, 2024.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/money/tags)

### Bug Fixes

* Update `poison` optional dependency to allow `~> 6.0`.

* Update `stream_data` test dependency to `~> 1.0`.

### Enhancements

* Improve specs and broaden dialyzer configuration.

## Money v5.17.0

This is the changelog for Money v5.17.0 released on May 28th, 2024.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/money/tags)

### Bug Fixes

* Fixes warnings on Elixir 1.17.

## Money v5.16.1

This is the changelog for Money v5.16.1 released on April 23rd, 2024.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/money/tags)

### Bug Fixes

* `Money.sum/2` default exchange rates is always `%{}` even if the exchange rate server is not running. Thanks to @haste for the report. Closes #168.

## Money v5.16.0

This is the changelog for Money v5.16.0 released on April 21st, 2024.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/money/tags)

### Bug Fixes

* When parsing numbers, use the localized number system separators where they exist. Thanks to @pshoukry for the report. Closes #167.

* Surface errors when starting the exchange rates retriever. Thanks to @danschultzer for the PR. Closes #165.

### Enhancements

* Update to [CLDR 45.0](https://cldr.unicode.org/index/downloads/cldr-45) data.

* Return structured errors for `Money.ExchangeRates.latest_rates/0`, `Money.ExchangeRates.historic_rates/1`, `Money.ExchangeRates.last_updated/0` and `Money.ExchangeRates.latest_rates_available?/0` when the exchange rates retrieval process is not running.

## Money v5.15.4

This is the changelog for Money v5.15.4 released on March 1st, 2024.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/money/tags)

### Bug Fixes

* Fix exchange rate conversions for digital tokens. Thanks much to @ddanschultzer for the PR. Closes 164.

### Enhancements

* Format the exchange rate retrieval interval used in the init message using the default `cldr` backend configured for `:ex_money`.

## Money v5.15.3

This is the changelog for Money v5.15.3 released on January 4th, 2024.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/money/tags)

### Bug Fixes

* Add `or ~> 4.0` for `:phoenix_html` dependency. Thanks to @wkirschbaum for the PR. Closes #161.

## Money v5.15.2

This is the changelog for Money v5.15.2 released on November 3rd, 2023.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/money/tags)

### Bug Fixes

* Fix compilation warnings on doctests on Elixir 1.16.

## Money v5.15.1

This is the changelog for Money v5.15.1 released on October 10th, 2023.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/money/tags)

### Bug Fixes

* Fixes the exchange rate retriever, removing the double retrieval loop.  Thanks to @dbernheisel for the report. Closes #152.

## Money v5.15.0

This is the changelog for Money v5.15.0 released on July 24th, 2023.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/money/tags)

### Enhancements

* Adds an option `:no_fraction_if_integer` to `Money.to_string/2`. If `truthy` this option will set `fractional_digits: 0` if `money` is an integer value. This may be helpful in cases where integer money amounts such as `Money.new(:USD, 1234)` should be formatted as `$1,234` rather than `$1,234.00`.

## Money v5.14.1

This is the changelog for Money v5.14.1 released on July 23rd, 2023.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/money/tags)

### Bug Fixes

* Fix `Logger.warn/1` warnings by moving to `Logger.warning/1`.

* Fix failing test case.

## Money v5.14.0

This is the changelog for Money v5.14.0 released on April 29th, 2023.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/money/tags)

### Enhancements

* Adds `Money.integer?/1` to return a boolean indicatng if a money amount is an integer value (ie has no significant fractional digits).

## Money v5.13.0

This is the changelog for Money v5.13.0 released on April 28th, 2023.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/money/tags)

### Enhancements

* Updates to [ex_cldr version 2.37.0](https://hex.pm/packages/ex_cldr/2.37.0) which includes data from [CLDR release 43](https://cldr.unicode.org/index/downloads/cldr-43)

* Tests now assume Decimal ~> 2.0 since the `Inspect` protocol implementation now emits executable code examples.

## Money v5.12.4

This is the changelog for Money v5.12.4 released on March 30th, 2023.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/money/tags)

**Note** `ex_money 5.12.4` is supported on Elixir 1.10 and later versions only. It also requires `ex_cldr_numbers 2.25` or later.

### Bug Fixes

* Delegates http requests (used in exchange rates retrieval) to `Cldr.Http.get_with_headers/2`. This centralizes all HTTP get requests for all `ex_cldr_*` libraries to this one function which can then be reviewed and managed for security concerns.

## Money v5.12.3

This is the changelog for Money v5.12.3 released on October 13th, 2022.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/money/tags)

**Note** `ex_money 5.12.3` is supported on Elixir 1.10 and later versions only. It also requires `ex_cldr_numbers 2.25` or later.

### Bug Fixes

* Fix `NaN` and `Inf` amount detection to be compatible with Decimal 1.x and 2.x. Thanks to @Lostkobrakai for the PR. Closes #144.

## Money v5.12.2

This is the changelog for Money v5.12.2 released on October 13th, 2022.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/money/tags)

**Note** `ex_money 5.12.2` is supported on Elixir 1.10 and later versions only. It also requires `ex_cldr_numbers 2.25` or later.

### Bug Fixes

* Don't create "NaN" or "Inf" valued Money structs. Thanks for @coladarci for the report. Closes #143.

## Money v5.12.1

This is the changelog for Money v5.12.1 released on August 27th, 2022.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/money/tags)

**Note** `ex_money 5.12.1` is supported on Elixir 1.10 and later versions only. It also requires `ex_cldr_numbers 2.25` or later.

### Bug Fixes

* Removes compile-time warnings for Elixir 1.14 (use `Application.compile_env/2`, not `Application.get_env/2`)

## Money v5.12.0

This is the changelog for Money v5.12.0 released on June 8th, 2022.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/money/tags)

**Note** `ex_money 5.12.0` is supported on Elixir 1.10 and later versions only. It also requires `ex_cldr_numbers 2.25` or later.

### Enhancements

* Add `Money.localize/2` to convert a money amount into the currency in affect for the given locale.

## Money v5.11.0

This is the changelog for Money v5.11.0 released on May 14th, 2022.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/money/tags)

**Note** `ex_money 5.11.0` is supported on Elixir 1.10 and later versions only. It also requires `ex_cldr_numbers 2.25` or later.

### Enhancements

* Adds support for [ISO 24165 Digital Tokens (crypto currency)](https://www.iso.org/standard/80601.html). Digital Token-based money behaves the same as currency-based money with the following exceptions due to limited data availability:

  * Digital token names are not localized (there is no localised data available in CLDR)
  * Digital token names are not pluralized (also because there is no localised data available)
  * Digital token amounts are never rounded (there is no data available to standardise on rounding rules or the number of fractional digits to round to)

## Money v5.10.0

This is the changelog for Money v5.10.0 released on April 6th, 2022.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/money/tags)

**Note** `ex_money 5.10.0` is supported on Elixir 1.10 and later versions only. It also requires `ex_cldr_numbers 2.25` or later.

### Enhancements

* Add `Money.zero?/1`, `Money.positive?/1` and `Money.negative?/1`. Thanks to @emaiax for the PR.

* Update [CLDR](https://cldr.unicode.org) to [release 41](https://cldr.unicode.org/index/downloads/cldr-41) in [ex_cldr version 2.28.0](https://hex.pm/packages/ex_cldr/2.28.0) and [ex_cldr_numbers 2.26.0](https://hex.pm/packages/ex_cldr_numbers/2.26.0).

## Money v5.9.0

This is the changelog for Money v5.9.0 released on February 21st, 2022.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/money/tags)

**Note** `ex_money 5.9.0` is supported on Elixir 1.10 and later versions only. It also requires `ex_cldr_numbers 2.25` or later.

### Enhancements

* Updates to [ex_cldr version 2.26.0](https://hex.pm/packages/ex_cldr/2.26.0) and [ex_cldr_numbers version 2.25.0](https://hex.pm/packages/ex_cldr_numbers/2.25.0) which use atoms for locale names and rbnf locale names. This is consistent with other elements of `t:Cldr.LanguageTag` where atoms are used when the cardinality of the data is fixed and relatively small and strings where the data is free format.

* Adjusts the output of `Money.inspect/2` to be executable code. Instead of `#Money<:USD, 100>` the output will be `Money.new(:USD, "100")`. This improved developer experience by allowing for copy/paste of `inspect/2` results into `iex`. It is also in line with similar changes being made in `elixir`, `Decimal` and others.

* Add documentation for `:currency_symbol` option for `Money.to_string/2`. Although its an option that is passed through to `Cldr.Number.to_string/3`, its very relevant to `t:Money` formatting.

## Money v5.8.0

This is the changelog for Money v5.8.0 released on January 31st, 2022.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/money/tags)

**Note** `ex_money 5.8.0` is supported on Elixir 1.10 and later versions only. It also requires `ex_cldr_numbers 2.23` or later.

### Enhancements

* Adds configuration option `:exclude_protocol_implementations` to omit generating implementations for one or more protocols from the list `Jason.Encoder`, `JSON.Encoder`, `Phoneix.HTML.Safe` and `Gringotts.Money`. Thanks to @jgough-playoxygen for the [suggestion](https://elixirforum.com/t/cldr-number-custom-formatter/45520).

## Money v5.7.4

This is the changelog for Money v5.7.4 released on December 23rd, 2021.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/money/tags)

**Note** `ex_money 5.7.4` is supported on Elixir 1.10 and later versions only. It also requires `ex_cldr_numbers 2.23` or later.

### Bug Fixes

* Fix `Money.to_integer_exp/1` when `t:Money` has a negative amount.  Thanks to @hamptokr for the report and the PR.

## Money v5.7.3

This is the changelog for Money v5.7.3 released on December 19th, 2021.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/money/tags)

**Note** `ex_money 5.7.3` is supported on Elixir 1.10 and later versions only. It also requires `ex_cldr_numbers 2.23` or later.

### Bug Fixes

* Fixes retrieving exchange rates on OTP releases before OTP 22.  Thanks to @fbettag for the report, collaboration and patience.

## Money v5.7.2

This is the changelog for Money v5.7.2 released on December 17th, 2021.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/money/tags)

**Note** `ex_money 5.7.2` is supported on Elixir 1.10 and later versions only. It also requires `ex_cldr_numbers 2.23` or later.

### Bug Fixes

* Fix spec for `Money.from_integer/3`. Thanks to @jdewar for the report.

### Enhancements

* Support a `:fractional_digits` option for `Money.from_integer/3` and improve the documentation.

## Money v5.7.1

This is the changelog for Money v5.7.1 released on December 8th, 2021.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/money/tags)

**Note** `ex_money 5.7.1` is supported on Elixir 1.10 and later versions only. It also requires `ex_cldr_numbers 2.23` or later.

### Bug Fixes

* Fix dialyzer warnings on Elixir 1.12 and 1.13

* Replace `use Mix.Config` with `import Config` in configuration files since the former is deprecated.

## Money v5.7.0

This is the changelog for Money v5.7.0 released on October 28th, 2021.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/money/tags)

### Enhancements

* Updates to support [CLDR release 40](https://cldr.unicode.org/index/downloads/cldr-40) via [ex_cldr version 2.24](https://hex.pm/packages/ex_cldr/2.24.0)

### Deprecations

* Don't call deprecated `Cldr.Config.get_locale/2`, use `Cldr.Locale.Loader.get_locale/2` instead.

## Money v5.6.0

This is the changelog for Money v5.6.0 released on August 31st, 2021.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/money/tags)

### Enhancements

* Adds `Money.to_currency_code/1` to return the currency code part of a `t:Money`. Thanks to @Adzz for the proposal. Closes #130.

## Money v5.5.5

This is the changelog for Money v5.5.5 released on August 15th, 2021.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/money/tags)

### Bug Fixes

* Allow either `phoenix_html` version 2.x or 3.x. Thanks to @seantanly for the PR. Closes #129.

## Money v5.5.4

This is the changelog for Money v5.5.4 released on June 17th, 2021.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/money/tags)

### Bug Fixes

* Support `t:Cldr.Number.Format.Options` as an argument to `Money.to_string/2`.  Thanks to @jeroenvisser101 for the PR. Closes #127.

## Money v5.5.3

This is the changelog for Money v5.5.3 released on May 7th, 2021.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/money/tags)

### Bug Fixes

* Fixes parsing money when a currency string has a "." in it such as "kr.". Thanks for the report to @Doerge. Closes #125.

## Money v5.5.2

This is the changelog for Money v5.5.2 released on April 14th, 2021.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/money/tags)

### Bug Fixes

* Fix exception message when describing the requirement for a default backend configuration. Thanks to @holandes22 for the report. Closes #124.

## Money v5.5.1

This is the changelog for Money v5.5.1 released on February 18th, 2021.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/money/tags)

### Bug Fixes

* Fix formatting a `t:Money` that has no `:format_options` key. That can happen if re-hydrating a `t:Money` using `:erlang.binary_to_term/1` from an older version of `ex_money` that doesn't have the `:format_options` key in the struct.  Thanks to @coladarci. Fixes #123.

## Money v5.5.0

This is the changelog for Money v5.5.0 released on February 10th, 2021.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/money/tags)

### Enhancements

* Adds format options to `t:Money` to allow per-money formatting options to be applied with the `String.Chars` protocol. Thanks to @morinap for the feature request.

* Adds `Money.put_format_options/2`

## Money v5.4.1

This is the changelog for Money v5.4.1 released on January 7th, 2021.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/money/tags)

### Bug Fixes

* Update `stream_data` to remove stacktrace warning

* Use `Cldr.default_backend!/0` instead of deprecated `Cldr.default_backend/0` in tests. Closes #120. Thanks to @darwintantuco.

## Money v5.4.0

This is the changelog for Money v5.4.0 released on November 1st, 2020.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/money/tags)

### Enhancements

* Add support for [CLDR 38](http://cldr.unicode.org/index/downloads/cldr-38)

## Money v5.3.2

This is the changelog for Money v5.3.2 released on September 30th, 2020.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/money/tags)

### Bug Fixes

* Fix docs for `Money.div!/2`

* Update `cldr_utils` which implements a shim for `Decimal` to support both version `1.9` and `2.0`.

## Money v5.3.1

This is the changelog for Money v5.3.1 released on September 26th, 2020.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/money/tags)

### Bug Fixes

* Support `nimble_parsec` versions that match `~> 0.5 or ~> 1.0`

## Money v5.3.0

This is the changelog for Money v5.3.0 released on September 5th, 2020.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/money/tags)

### Bug Fixes

* Fix parsing money amounts to use Unicode definition of whitespace (set `[:Zs:]`). Thanks to @Sanjibukai for the report.

### Enhancements

* Add `Money.sum/2` to sum a list of `Money`, converting them if required.

## Money v5.2.1

This is the changelog for Money v5.2.1 released on June 23rd, 2020.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/money/tags)

### Enhancements

* Configure the `Money.Application` supervisor via the arguments to `Money.Application.start/2` and configure defaults in `mix.exs`. This permits different restart strategies and names.

* Add `Money.ExchangeRates.Supervisor.default_supervisor/0` to return the name of the default supervisor which is `Money.Supervisor`

* Change `Money.ExchangeRates.Supervisor.stop/0` to become `Money.ExchangeRates.Supervisor.stop/{0, 1}` allowing the supervisor name to be passed in. The default is `Money.ExchangeRates.Supervisor.default_supervisor/0`

### Bug Fixes

* Add back the name of the Application supervisor, `Money.Supervisor`. Thanks for the report of the regression to @jeroenvisser101. Fixes #117.

## Money v5.2.0

This is the changelog for Money v5.2.0 released on May 30th, 2020.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/money/tags)

### Enhancements

* Adds a configuration option `:verify_peer` which is a boolean that determines whether to verify the client certificate for any exchange rate service API call. The default is `true`. This option should not be changed without a very clear understanding of the security implications. This option will remain undocumented but supported for now.

### Bug fixes

* Handle expired certificate errors on the exchange rates API service and log them. Thanks to @coladarci. Fixes #116

## Money v5.1.0

This is the changelog for Money v5.1.0 released on May 26th, 2020.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/money/tags)

### Enhancements

* Extract default currency from locale when calling `Money.parse/2` on a money string. The updated docs now say:

  * `:default_currency` is any valid currency code or `false`
    that will used if no currency code, symbol or description is
    indentified in the parsed string. The default is `nil`
    which means that the default currency associated with
    the `:locale` option will be used. If `false` then the
    currency assocated with the `:locale` option will not be
    used and an error will be returned if there is no currency
    in the string being parsed.

* Add certificate verification for exchange rate retrieval

## Money v5.0.2

This is the changelog for Money v5.0.2 released on April 29th, 2020.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/money/tags)

### Bug Fixes

* Update the application supervisor spec

## Money v5.0.1

This is the changelog for Money v5.0.1 released on January 28th, 2020.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/money/tags)

### Bug Fixes

* Make `nimble_parsec` a required dependency since it is required for parsing money amounts. Thanks to @jonnystoten for the report.

## Money v5.0.0

This is the changelog for Money v5.0.0 released on January 21st, 2020.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/money/tags)

### Breaking changes

* Elixir 1.10 introduces semantic sorting for stucts that depends on the availability of a `compare/2` function that returns `:lt`, `:eq` or `:gt`.  Therefore in this release of `ex_money` the functions `compare/2` and `compare!/2` are swapped with `cmp/2` and `cmp!/2` in order to conform with this expectation. Now `compare/2` will return `:eq`, `:lt` or `:gt`. And `cmp/2` return `-1`, `0` or `1`.

* Deprecate `Money.reduce/1` in favour of `Money.normalize/1` to be consistent with `Decimal` versions `1.9` and later.

It is believed and tested that `Money` version `5.0.0` is compatible with all versions of `Decimal` from `1.6` up to the as-yet-unreleased `2.0`.

### Support of Elixir 1.10 Enum sorting

From Elixir verison `1.10.0`, several functions in the `Enum` module can use the `Money.compare/2` function to simplify sorting. For example:

```
iex> list = [Money.new(:USD, 100), Money.new(:USD, 200)]
[#Money<:USD, 100>, #Money<:USD, 200>]
iex> Enum.sort list, Money
[#Money<:USD, 100>, #Money<:USD, 200>]
iex> Enum.sort list, {:asc, Money}
[#Money<:USD, 100>, #Money<:USD, 200>]
iex> Enum.sort list, {:desc, Money}
[#Money<:USD, 200>, #Money<:USD, 100>]
```
**Note that `Enum.sort/2` will sort money amounts even when the currencies are incompatible. In this case the order of the result is not predictable. It is the developers responsibility to filter the list to compatible currencies prior to sorting. This is a limitation of the `Enum.sort/2` implementation.**

### Notes on Decimal version support

* `ex_money` version `5.0.0` is compatible with `Decimal` versions from `1.6` onwards. In `Decimal` version `2.0` the same changes to `compare/2` and `cmp/2` will occur and in `Decimal` version `1.9`, `Decimal.cmp/2` is deprecated.  `ex_money` version `5.0.0` detects these different versions of `Decimal` and therefore remains compatability with `Decimal` back to version `1.6`.

## Money v4.4.2

This is the changelog for Money v4.4.2 released on January 2nd, 2020.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/money/tags)

### Bug Fixes

* Remove calls to `Code.ensure_compiled?/1` since it is deprecated in Elixir 1.10. Use instead `Cldr.Config.ensure_compiled?/1` which is added as a private API in `Cldr` version 2.12.0. This version of `Cldr` now becomes the minimum version required.

* Remove spurious entries in `.dialyzer_ignore_warnings` - no entries are required and dialyzer is happy.

## Money v4.4.1

This is the changelog for Money v4.4.1 released on November 10th, 2019.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/money/tags)

### Bug Fixes

* Fixes money parsing error. Thanks to @Doerge. Closes #112.

## Money v4.4.0

This is the changelog for Money v4.4.0 released on November 6th, 2019.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/money/tags)

### Breaking Change

* `Money.parse/2` until this release supported the `:currency_filter` option. It allowed for currencies to be filtered based upon their attributes (`:all`, `:current`, `:historic`, `:tender`, `:annotated`). When multiple attributes were passed in a list, a currency had to meet all of these attributes. From this release onwards, multiple attributes items are `or`ed, not `and`ed. It is expected this option is used extremely rarely and therefore of limited impact.

### Enhancements

* `Money.parse/2` now includes the option `:default_currency` which allows for parsing a number only (without a currency code) and it will be tagged with the `:default_currency`.
```elixir
  iex> Money.parse("100")
  {:error,
   {Money.Invalid,
    "A currency code, symbol or description must be specified but was not found in \"100\""}}
  iex> Money.parse("100", default_currency: :USD)
  #Money<:USD, 100>
```

* Add `:only` and `:except` options to `Money.parse/2` to specify which currency codes or currency attributes are permitted.  `:only` and `:except` replace the option `:currency_filter` which is now deprecated. If provided, `:currency_filter` is interpreted as `:only`. An example:
```elixir
  iex> Money.parse("100 usd", only: :current, except: :USD)
  {:error,
   {Money.UnknownCurrencyError,
    "The currency \"usd\" is unknown or not supported"}}
```

* `Money.parse/2` now supports negative money amounts.
```elixir
  iex> Money.parse("chf -100")
  #Money<:CHF, -100>

  iex> Money.parse("(chf 100)")
  #Money<:CHF, -100>
```
* The money parser has been rewritten using [nimble_parsec](https://hex,pm.packages/nimble_parsec)

## Money v4.3.0

This is the changelog for Money v4.3.0 released on September 8th, 2019.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/money/tags)

### Enhancements

* Adds a `Money` backend in the same spirit as other libraries that leverge [ex_cldr](https://hex,pm/packages/ex_cldr). Thanks to @Lostkobrakai. Closes #108. All of the functions in the `Money` module may also be called on a backend module `<backend>.Money.fun` without having to specify a backend module since this is implicit.

### Bug Fixes

* `Money.new!/3` replaces `Money.new!/2` to accept options. Thanks to @Lostkobrakai. Closes #109.

## Money v4.2.2

This is the changelog for Money v4.2.2 released on September 7th, 2019.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/money/tags)

### Bug Fixes

* Use `Keyword.get_lazy` when the default is `Cldr.default_backend/0` to avoid exceptions when no default backend is configured. Thanks to @Lostkobrakai. Closes #108.

## Money v4.2.1

This is the changelog for Money v4.2.1 released on September 2nd, 2019.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/money/tags)

### Bug Fixes

* Fixes parsing of money amount that have a single digit amount. Closes #107.  Thanks to @njwest

## Money v4.2.0

This is the changelog for Money v4.2.0 released on 21 August, 2019.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/money/tags)

### Bug Fixes

* Move the `Money.Migration` module to [ex_money_ecto](https://hex.pm/packages/ex_money_sql) where it belongs

### Enhancements

* `Money.default_backend/0` will now either use the backend configured under the `:default_cldr_backend` key of `ex_money` or `Cldr.default_backend/0`. In either case an exeption will be raised if no default backend is configured.

## Money v4.1.0

This is the changelog for Money v4.1.0 released on July 13th, 2019.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/money/tags)

### Enhancements

* Adds `Money.abs/1`. Thanks to @jeremyjh.

* Improve `@doc` consistency using `## Arguments` not `## Options`.

## Money v4.0.0

This is the changelog for Money v4.0.0 released on July 8th, 2019.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/money/tags)

### Breaking Changes

* Functions related to the serialization of money types have been extracted to the library [ex_money_sql](https://hex.pm/packages/ex_money_sql).  For applications using the dependency `ex_money` that *do not* require serialization no changes are required.  For applications using serialization, the dependency should be changed to `ex_money_sql` (which in turn depends on `ex_money`).

* Supports Elixir 1.6 and later only

## Money v3.4.4

This is the changelog for Money v3.4.4 released on June 2nd, 2019.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/money/tags)

### Enhancements

* Supports passing an `Cldr.Number.Formation.Options.t` as alternative to a `Keyword.t` for options to `Money.to_string/2`.  Performance is doubled when using pre-validated options which is useful if formatting is being executed in a tight loop.

An example of this usage is:

```elixir
  iex> money = Money.new(:USD, 100)

  # Apply any options required as a keyword list
  # Money will take care of managing the `:currency` option
  iex> options = []

  iex> {:ok, options} = Cldr.Number.Format.Options.validate_options(0, backend, options)
  iex> Money.to_string(money, options)
```

The `0` in `validate_options` is used to determine the sign of the amount because that can influence formatting - for example the accounting format often uses `(1234)` as its format.  If you know your amounts are always positive, just use `0`.

If the use case may have both positive and negative amounts, generate two option sets (one with the positive number and one with the negative).  Then use the appropriate option set.  For example:

```elixir
  iex> money = Money.new(:USD, 1234)

  # Add options as required
  # Money will take care of managing the `:currency` option
  iex> options = []

  iex> {:ok, positive_options} = Cldr.Number.Format.Options.validate_options(0, backend, options)
  iex> {:ok, negative_options} = Cldr.Number.Format.Options.validate_options(-1, backend, options)

  iex> if Money.cmp(money, Money.zero(:USD)) == :gt do
  ...>   Money.to_string(money, positive_options)
  ...> else
  ...>   Money.to_string(money, negative_options)
  ...> end
```

## Money v3.4.3

This is the changelog for Money v3.4.3 released on June 2nd, 2019.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/money/tags)

### Bug Fixes

* Ensure `Money.to_string!/2` properly raises

* Add specs for `Money.to_string/2` and `Money.to_string!/2`

Thanks to @rodrigues for the report and PR.

## Money v3.4.2

This is the changelog for Money v3.4.2 released on April 16th, 2019.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/money/tags)

### Bug Fixes

* `Money.put_fraction/2` now correctly allows setting the fraction to 0.

### Enhancements

* `Money.round/2` allows setting `:currency_digits` to an integer number of digits in addition to the options `:iso`, `:cash` and `:accounting`.  The default remains `:iso`.

* Improves the documentation for `Money.to_string/2`.

## Money v3.4.1

This is the changelog for Money v3.4.1 released on April 5th, 2019.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/money/tags)

### Bug Fixes

* Fix `README.md` markdown formatting error.  Thanks to @fireproofsocks for the report and @lostkobrakai for the fix.  Closes #99.

## Money v3.4.0

This is the changelog for Money v3.4.0 released on March 28th, 2019.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/money/tags)

### Enhancements

* Updates to [CLDR version 35.0.0](http://cldr.unicode.org/index/downloads/cldr-35) released on March 27th 2019 through `ex_cldr` version 2.6.0.

## Money v3.3.1

This is the changelog for Money v3.3.1 released on March 8th, 2019.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/money/tags)

### Bug Fixes

* Fix or silence dialyzer warnings

## Money v3.3.0

This is the changelog for Money v3.3.0 released on February 24th, 2019.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/money/tags)

### Enhancements

* Adds `Money.put_fraction/2`. This will set the fractional part of a money to the specified integer amount.  Examples:
```
  iex> Money.put_fraction Money.new(:USD, "2.49"), 99
  #Money<:USD, 2.99>

  iex> Money.put_fraction Money.new(:USD, "2.49"), 999
  {:error,
   {Money.InvalidAmountError, "Rounding up to 999 is invalid for currency :USD"}}
```

### Bug Fixes

* Parsing money strings now uses a more complete set of character definitions for decimal and grouping separators based upon the `characters.json` file of the "en" locale.

## Money v3.2.4

This is the changelog for Money v3.2.4 released on February 13th, 2019.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/money/tags)

### Bug Fixes

* Updates to [ex_cldr_currencies version 2.1.2](https://hex.pm/packages/ex_cldr_currencies/2.1.2) which correctly removes duplicate currency strings when the same string referred to different currency codes. See the [changelog](https://github.com/kipcole9/cldr_currencies/blob/v2.1.2/CHANGELOG.md) for further detail.

### Enhancements

* Adds a `:fuzzy` option to `Money.parse/2` that uses `String.jaro_distance/2` to help determine if the provided currency text can be resolved as a currency code.  For example:
```
  iex> Money.parse("100 eurosports", fuzzy: 0.8)
  #Money<:EUR, 100>

  iex> Money.parse("100 eurosports", fuzzy: 0.9)
  {:error,
   {Money.Invalid, "Unable to create money from \\"eurosports\\" and \\"100\\""}}
```

## Money v3.2.3

This is the changelog for Money v3.2.3 released on February 12th, 2019.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/money/tags)

### Bug Fixes

* Correctly parse money strings with unicode currency symbols like "€". Closes #95.  Thanks to @crbelaus.

## Money v3.2.2

This is the changelog for Money v3.2.2 released on February 10th, 2019.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/money/tags)

### Enhancements

* Improves parsing of money strings. Parsing now uses various strings that [CLDR](https://cldr.unicode.org) knows about.  Some examples:

```elixir
 iex> Money.parse "$au 12 346", locale: "fr"
 #Money<:AUD, 12346>
 iex> Money.parse "12 346 dollar australien", locale: "fr"
 #Money<:AUD, 12346>
 iex> Money.parse "A$ 12346", locale: "en"
 #Money<:AUD, 12346>
 iex> Money.parse "australian dollar 12346.45", locale: "en"
 #Money<:AUD, 12346.45>
 iex> Money.parse "AU$ 12346,45", locale: "de"
 #Money<:AUD, 12346.45>

 # Can also return the strings available for a given currency
 # and locale
 iex> Cldr.Currency.strings_for_currency :AUD, "de"
 ["aud", "au$", "australischer dollar", "australische dollar"]

 # Round trip formatting also seems to be ok
 iex> {:ok, string} = Cldr.Number.to_string 1234, Money.Cldr, currency: :AUD
 iex> Money.parse string
 #Money<:AUD, 1234.00>
```
## Money v3.2.1

This is the changelog for Money v3.2.1 released on February 2nd, 2019.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/money/tags)

### Bug Fixes

* Added `Money.Ecto.Composite.Type.cast/1` and `Money.Ecto.Map.Type.cast/1` for a `String.t` parameter. When a `String.t` is provided, `cast/1` will call `Money.parse/2` to create the `Money.t`.

* `Money.new/3` now uses the current locale on the default backend if no locale or backend is specified. This means that `Money.Ecto.Composite.Type.cast/1` and `Money.Ecto.Map.Type.cast/1` will be parsed using the locale that has been set for the current process in the default backend. As a result, a simple `type=text` form field can be used to input a money type (currency code and amount in a single string) that can then be cast to a `Money.t`.

## Money v3.2.0

This is the changelog for Money v3.2.0 released on February 1st, 2019.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/money/tags)

### Bug Fixes

* Correctly generate `migrations_path/1` function based upon whether `Ecto` is configured and which version

### Enhancements

* Adds `Money.parse/2` which will parse a string comprising a currency code and an amount. It will return a `Money.t` or an error.  This function may be helpful in supporting money input in HTML forms.

## Money v3.1.0

This is the changelog for Money v3.1.0 released on December 30th, 2018.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/money/tags)

### Bug Fixes

* Fix typo in `exchange_rates_retriever.ex`.  Thanks to @lostkobrakai.  Closes #91.

* Remove obsolete `cldr` compiler

* Changes the `sum` aggregate function for `money_with_currency` to be `STRICT` which means it handles `NULL` columns in the same way as the standard `SUM` function.  Thanks to @lostkobrakai.  Closes #88.

* Fixes documentation link errors

* Fix unhandled terminate typo error in exchange rates server. Thanks to @xavier. Closes #90.

## Money v3.0.0

This is the changelog for Money v3.0.0 released on November 23rd, 2018.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/money/tags)

The primary purpose of this release is to support ex_cldr version 2.0

### Breaking changes

* `Money.from_tuple/1` has been removed
* Uses [ex_cldr](https://hex.pm/packages/ex_cldr/2.0.0) version 2.  Please see [the changelog](https://github.com/kipcole9/cldr/blob/v2.0.1/CHANGELOG.md#migrating-from-cldr-1x-to-cldr-version-2x) for configuration changes that are required.
* Requires a default_cldr_backend to be configured in `config.exs`.  For example:
```
  config :ex_money,
    ...
    default_cldr_backend: MyApp.Cldr
  end
```
