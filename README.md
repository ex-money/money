# Introduction to Money

![Build status](https://github.com/ex-money/money/actions/workflows/ci.yml/badge.svg)
[![Hex.pm](https://img.shields.io/hexpm/v/ex_money.svg)](https://hex.pm/packages/ex_money)
[![Hex.pm](https://img.shields.io/hexpm/dw/ex_money.svg?)](https://hex.pm/packages/ex_money)
[![Hex.pm](https://img.shields.io/hexpm/dt/ex_money.svg?)](https://hex.pm/packages/ex_money)
[![Hex.pm](https://img.shields.io/hexpm/l/ex_money.svg)](https://hex.pm/packages/ex_money)

Money implements a set of functions to store, retrieve, convert and perform arithmetic
on a `t:Money.t/0` type that is composed of an [ISO 4217](https://www.iso.org/iso-4217-currency-codes.html) currency code, an [ISO 24165](https://www.iso.org/standard/80601.html) Digital Token Identifier (crypto currency) or a custom currency code with a currency amount.

Money is opinionated in the interests of serving as a dependable library that can underpin accounting and financial applications.

How is this opinion expressed?

1. Money must always have both a amount and a currency code or digital token identifier.

2. The currency code must always be a valid [ISO 4217](https://www.iso.org/iso-4217-currency-codes.html) code or a valid [ISO 24165](https://www.iso.org/standard/80601.html) digital token identifier. [Current](https://www.currency-iso.org/en/home/tables/table-a1.html) and [historical](https://www.currency-iso.org/en/home/tables/table-a3.html) currency codes can be used.  See the [ISO Currency](https://www.currency-iso.org/en/home/tables.html) for more information. You can also identify the relevant codes by:

   * `Money.known_currencies/0` returns all the ISO 4217 currency codes known to `Money`
   * `Money.known_current_currencies/0` returns the ISO 4217 currency codes currently in use
   * `Money.known_historic_currencies/0` returns the list of historic ISO 4217 currency codes
   * `Money.known_tender_currencies/0` returns the list of ISO 4217 currencies known to be legal tender
   * `DigitalToken.tokens/0` returns a map of the known ISO 24165 digital tokens.

3. Money arithmetic can only be performed when both operands are of the same currency.

4. Money amounts are represented as a `Decimal`.

5. Money can be serialised to the database as a composite Postgres type that includes both the amount and the currency. For MySQL, money is serialized into a json column with the amount converted to a string to preserve precision since json does not have a decimal type. Serialization is entirely optional.

6. All arithmetic functions work on a `Decimal`. No rounding occurs automatically (unless expressly called out for a function, as is the case for `Money.split/2`).

7. Explicit rounding obeys the rounding rules for a given currency. The rounding rules are defined by the Unicode consortium in its CLDR repository as implemented by the hex package [localize](https://hex.pm/packages/localize). These rules define the number of fractional digits for a currency and the rounding increment where appropriate.

8. Money output string formatting output using the hex package [localize](https://hex.pm/packages/localize) that correctly rounds to the appropriate number of fractional digits and to the correct rounding increment for currencies that have minimum cash increments (like the Swiss Franc and Australian Dollar)

## Prerequisities

* `Money` is supported on Elixir 1.12 and later only.

## Migration from 5.x to 6.0

Money 6.0 replaces the `ex_cldr` family of dependencies (`ex_cldr`, `ex_cldr_numbers`, `ex_cldr_units`) with the unified `localize` package. This is a breaking change that removes the compile-time backend system.

### Update dependencies

In `mix.exs`, replace the CLDR dependencies with `localize`:

```elixir
# Remove these:
{:ex_cldr, "~> 2.46"},
{:ex_cldr_numbers, "~> 2.38"},
{:ex_cldr_units, "~> 3.19", optional: true},

# Add this:
{:localize, "~> 0.1"},
```

### Remove backend modules

Delete your CLDR backend module (e.g. `MyApp.Cldr`). Localize has no compile-time backend system. The backend module typically looked like:

```elixir
# DELETE THIS MODULE
defmodule MyApp.Cldr do
  use Cldr,
    locales: ["en", "fr", "de"],
    default_locale: "en",
    providers: [Cldr.Number, Money]
end
```

### Update configuration

Remove all backend-related configuration:

```elixir
# Remove these from config.exs:
config :ex_money, default_cldr_backend: MyApp.Cldr
config :ex_cldr, default_backend: MyApp.Cldr

# Optionally configure localize locales:
config :localize,
  default_locale: :en,
  preload_locales: [:en, :fr, :de]
```

### Remove `:backend` option from function calls

The `:backend` option has been removed from all Money functions. Remove it from any calls to `Money.new/3`, `Money.to_string/2`, `Money.parse/2`, `Money.localize/2`, and others:

```elixir
# Before (5.x):
Money.to_string(money, backend: MyApp.Cldr, locale: "de")
Money.parse("100 USD", backend: MyApp.Cldr)

# After (6.0):
Money.to_string(money, locale: "de")
Money.parse("100 USD")
```

### Update locale management

Replace CLDR locale functions with Localize equivalents:

```elixir
# Before (5.x):
Cldr.put_locale(MyApp.Cldr, "de")
Cldr.get_locale()

# After (6.0):
Localize.put_locale(:de)
Localize.get_locale()
```

### Update custom currency creation

```elixir
# Before (5.x):
Cldr.Currency.new(:XBTC, name: "Bitcoin", symbol: "₿", digits: 8)

# After (6.0):
Money.Currency.new(:XBTC, name: "Bitcoin", symbol: "₿", digits: 8)
```

### Update error handling

Error types have changed for currency validation:

```elixir
# Before (5.x):
{:error, {Cldr.UnknownCurrencyError, "The currency :ZZZ is unknown"}}

# After (6.0):
{:error, {Money.UnknownCurrencyError, "The currency :ZZZ is not known."}}
```

### Update number formatting references

If you use number formatting directly, update the module references:

```elixir
# Before (5.x):
Cldr.Number.to_string(1234, MyApp.Cldr, currency: :USD)

# After (6.0):
Localize.Number.to_string(1234, currency: :USD)
```

## Supervisor configuration and operation

`Money` starts a supervisor `Money.Supervisor` by default unless the dependency is configured as `runtime: false` in `mix.exs`. If configured as `runtime: false` then the application can be started later via `Money.Application.start(:normal, supervisor_options)` where `supervisor_options` is a keyword list of options that is given the `Supervisor.start_link/2`. The default options are `[strategy: :one_for_one, name: Money.Supervisor]`.

The application supervisor is used by default to start the exchange rates service when required. The exchange rate service can be configured to run in a user defined supervision tree as explained in the next section.

## Private Use and Custom Currencies

It is possible to define private use currencies. These are currencies that are [ISO 4217](https://www.iso.org/iso-4217-currency-codes.html) compliant but guaranteed never to be allocated by the ISO committee and therefore safe to be used by developers. It is also possible to define custom currencies which are *not* ISO4217 compliant.

### Defining private use and custom currencies

See `Money.Currency.new/2`.

### Custom currency store

The `Money.Currency.Store` GenServer is started automatically by the `ex_money` application and manages the storage of custom currency definitions. Custom currencies can be defined at any time after application startup:

```elixir
Money.Currency.new(:XBTC, name: "Bitcoin", symbol: "₿", digits: 8)
```

## Exchange rates and currency conversion

Money includes a process to retrieve exchange rates on a periodic basis.  These exchange rates can then be used to support currency conversion.  This service is not started by default.  If started it will attempt to retrieve exchange rates every 5 minutes by default.

By default, exchange rates are retrieved from [Open Exchange Rates](http://openexchangerates.org) however any module that conforms to the `Money.ExchangeRates` behaviour can be configured.

An optional callback module can also be defined.  This module defines a `rates_retrieved/2` function that is invoked upon every successful retrieval of exchange rates.  This might be used to serialize exchange rate to a data store or to stream rates to other applications or systems.

## Configuration

`Money` provides a set of configuration keys to customize behaviour. The default configuration is:

    config :ex_money,
      auto_start_exchange_rate_service: true,
      exchange_rates_retrieve_every: 300_000,
      api_module: Money.ExchangeRates.OpenExchangeRates,
      callback_module: Money.ExchangeRates.Callback,
      exchange_rates_cache_module: Money.ExchangeRates.Cache.Ets,
      preload_historic_rates: nil,
      retriever_options: nil,
      log_failure: :warning,
      log_info: :info,
      log_success: nil,
      json_library: Jason,
      exclude_protocol_implementations: []

### Configuration key definitions

* `:auto_start_exchange_rate_service` indicates if the exchange rate service is to be started when `ex_money` starts. The default is `true`. Set this to `false` when configuring the service to run within a different supervision tree.

* `:exchange_rates_retrieve_every` defines how often the exchange rates are retrieved in milliseconds.  The default is `:never`. An `atom` value is interpreted to mean that there should be no periodic retrieval.

* `:api_module` identifies the module that does the retrieval of exchange rates. This is any module that implements the `Money.ExchangeRates` behaviour.  The  default is `Money.ExchangeRates.OpenExchangeRates`.

* `:exchange_rates_cache_module` defines the module that provides an exchange rates cache.  Any module that implements the `Money.ExchangeRates.Cache` behaviour.  Two alternative strategies are provided:

  * `Money.ExchangeRates.Cache.Ets` which is also the default.
  * `Money.ExchangeRates.Cache.Dets`

* `:retriever_options` is available for exchange rate retriever module developers as a place to add retriever-specific configuration information.  This information should be added in the `init/1` callback in the retriever module.  See `Money.ExchangeRates.OpenExchangeRates.init/1` for an example.

* `:preload_historic_rates` defines a date or a date range that will be requested when the exchange rate service starts up. The date or date range should be specified as either a `Date.t` or a `Date.Range.t` or a tuple of `{Date.t, Date.t}` representing the `from` and `to` dates for the rates to be retrieved. The default is `nil` meaning no historic rates are preloaded. See [Preloading historic rates](#preloading-historic-rates) for more information.

* `callback_module` defines a module that follows the `Money.ExchangeRates.Callback` behaviour whereby the function `rates_retrieved/2` is invoked after every successful retrieval of exchange rates.  The default is `Money.ExchangeRates.Callback`.

* `log_failure` defines the log level at which api retrieval errors are logged.  The default is `:warning`.

* `log_success` defines the log level at which successful api retrieval notifications are logged.  The default is `nil` which means no logging.

* `log_info` defines the log level at which service startup messages are logged.  The default is `info`.

* `:json_library` determines which json library to be used for decoding. Two common options are `Jason` and `Poison`. The default is `:json` (built into OTP).

* `:exclude_protocol_implementations` is a protocol module, or list of protocol modules, that will not be defined by `ex_money`. The default is `[]`. The protocol implementations influenced by this option are `Jason.Encoder`, `JSON.Encoder` and `Phoenix.HTML.Safe`.

### JSON library configuration

Note that `ex_money` does not define a json library dependency and therefore it is the users responsibility to configure the required json library as a dependency in the application's `mix.exs`.

The recommended library is [jason](https://hex.pm/packages/jason) on Elixir versions prior to 1.18 which would be configured as:
```
  defp deps do
    [
      {:jason, "~> 1.0"},
      ...
    ]
  end
```
For Elixir version 1.18 or later, no JSON library need be configured since the built-in `JSON` module can be used automatically. For earlier Elixir versions that are running on OTP 27 or later, the built-in OTP module `:json` will be used automatically.

In most cases no JSON library configuration is required since the built-in OTP `:json` module is used by default. For Elixir versions prior to 1.18, configure `Jason` as the json library.

### Configuring locales to support localised formatting

`Money` uses [localize](https://hex.pm/packages/localize) to support configuring locales and providing locale formatting. This package is also the source of currency definitions, names, formats and so on.

No backend module is required. Localize uses runtime locale resolution. Configure locales via the `localize` application configuration:

```elixir
config :localize,
  default_locale: :en,
  preload_locales: [:en, :fr, :zh]
```

The current locale can be set at runtime:

```elixir
Localize.put_locale(:fr)
```

### Preloading historic rates

The current implementation will call the api_module to retrieve the historic rates once for each date in the `:preload_historic_rates` range.  Some exchange rate services, like Open Exchange Rates, provides a bulk retrieval api that can retrieve multiple dates in a single call.  However this endpoint is only available for premium subscribers and it is still charged on a "per date retrieved" basis. So while there is a network/performance/efficiency benefit there is no economic benefit.  Please file an issue on [github](https://github.com/ex-money/money) if implementing a bulk api is important to you.

Some examples of configuring the `:preload_historic_rates` key follow:

  * `preload_historic_rates: ~D[2017-01-01]`
  * `preload_historic_rates: Date.range(~D[2017-01-01], ~D[2017-10-01])`
  * `preload_historic_rates: {~D[2017-01-01], ~D[2017-10-01]}`

### Open Exchange Rates configuration

If you plan to use the provided Open Exchange Rates module to retrieve exchange rates then you should also provide the addition configuration key for `app_id`:

      config :ex_money,
        open_exchange_rates_app_id: "your_app_id"

  or configure it via environment variable, for example:

      config :ex_money,
        open_exchange_rates_app_id: {:system, "OPEN_EXCHANGE_RATES_APP_ID"}

The default exchange rate retrieval module is provided in `Money.ExchangeRates.OpenExchangeRates` which can be used as a example to implement your own retrieval module for  other services.

### Managing the configuration at runtime

During exchange rate service startup, the function `init/1` is called on the configured exchange rate retrieval module.  This module is expected to return an updated configuration allowing a developer to customise how the configuration is to be managed.  See the implementation at `Money.ExchangeRates.OpenExchangeRates.init/1` for an example.

To support runtime (re-)configuration the following functions are provided:

  * `Money.ExchangeRates.Retriever.config/0` returns the current configuration of the exchange rates retrieval service.

  * `Money.ExchangeRates.Retriever.stop/0` and `Money.ExchangeRates.Retriever.start/0` stop and start the exchange rates retrieval service respectively.

  * `Money.ExchangeRates.Retriever.reconfigure/1` reconfigures the exchange rates retrieval service.  It does not restart the service, the service remains active during the recongiguration.

### Using Environment Variables in the configuration

Keys can also be configured to retrieve values from environment variables.  This lookup is done at runtime to facilitate deployment strategies.  If the value of a configuration key is `{:system, "some_string"}` then `"some_string"` is interpreted as an environment variable name which is passed to `System.get_env/2`.  An example configuration might be:

    config :ex_money,
      auto_start_exchange_rate_service: {:system, "RATE_SERVICE"},
      exchange_rates_retrieve_every: {:system, "RETRIEVE_EVERY"},
      open_exchange_rates_app_id: {:system, "OPEN_EXCHANGE_RATES_APP_ID"}

Note that the `{:system, "ENV KEY"}` approach is **not** currently supported for the `:preload_historic_rates` configuration key.

## The Exchange rates service process supervision and startup

If the exchange rate service is configured to automatically start up (because the config key `auto_start_exchange_rate_service` is set to `true`) then a supervisor process named `Money.ExchangeRates.Supervisor` is started which in turns starts a child `GenServer` called `Money.ExchangeRates.Retriever`.  It is `Money.ExchangeRates.Retriever` which will call the configured `api_module` to retrieve the rates.  It is also responsible for calling the configured `callback_module` after a successfull retrieval.

                                         +-----------------+
                                         |                 |
    +-------------+    +-----------+     |   api_module    |-> External Service
    |             |    |           |---> |                 |
    | Supervisor  |--->| Retriever |     +-----------------+
    |             |    |           |---> +-----------------+
    +-------------+    +-----------+     |                 |
                                         | callback_module |
                                         |                 |
                                         +-----------------+

On application start (or manual start if `:auto_start_exchange_rate_service` is set to `false`), `Money.ExchangeRates.Retriever` will schedule the first retrieval to be executed after immediately and then each `:exchange_rates_retrieve_every` milliseconds thereafter.

## Using Ecto or other applications from within the callback module

If you provide your own callback module and that module depends on some other applications, like `Ecto`, already being started then automatically starting `Money.ExchangeRates.Supervisor` may not work since your `Ecto.Repo` is unlikely to have already been started.

In this situation the appropriate way to configure the exchange rates retrieval service is the following:

1. Set the configuration key `auto_start_exchange_rate_service` to `false` to prevent automatic startup of the service.

2. Configure your `api_module`, `callback_module` and any other required configuration as appropriate

3. In your client application code, add the `Money.ExchangeRates.Supervisor` to the `children` configuration of your application.  For example, in an application that uses `Ecto` and where your `callback_module` is designed to save exchange rates to a database, your application may would look something like:

```elixir
defmodule Application do
  use Application

  def start(_type, _args) do
    import Supervisor.Spec

    children = [

      # Start your repo first so that it is running before your
      # exchange rates callback module is called
      supervisor(MoneyTest.Repo, []),

      # Include the Money.ExchangeRates.Supervisor in your application's
      # supervision tree.  This supervisor will start the child process
      # Money.ExchangeRates.Retriever.

      # Note the use of double `[]` around
      # the parameters which are required to ensure that the supervisor
      # is stopped before including in your supervisor tree.
      # The `start_retriever: true` is optional.  The default value is `false`.
      supervisor(Money.ExchangeRates.Supervisor, [[restart: true, start_retriever: true]])
    ]

    opts = [strategy: :one_for_one, name: Application.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

## API Usage Examples

### Creating a %Money{} struct

    iex> Money.new(:USD, 100)
    Money.new(:USD, "100")

    iex> Money.new(100, :USD)
    Money.new(:USD, "100")

    iex> Money.new("CHF", "130.02")
    Money.new(:CHF, "130.02")

    iex> Money.new("thb", 11)
    Money.new(:THB, "11")

    iex> Money.new("1.000,99", :EUR, locale: "de")
    Money.new(:EUR, "1000.99")

    iex> Money.parse("USD 100")
    Money.new(:USD, "100")

    iex> Money.parse("USD 100,00", locale: "de")
    Money.new(:USD, "100.00")

The canonical representation of a currency code is an `atom` that is a valid
[ISO4217](http://www.currency-iso.org/en/home/tables/table-a1.html) currency code or a `t:String.t/0` representation of an [ISO 24165](https://www.iso.org/standard/80601.html) digital token identifier. The amount of a `%Money{}` is represented by a `Decimal`.

Note that the amount and currency code arguments to `Money.new/3` can be supplied in either order.

### Parsing money strings

`Money` provides an ability to parse strings that contain a currency and an amount.  The currency can be represented in different ways depending on the locale. See `Money.parse/2` for further information.  Some examples are:

```
  iex> Money.parse "$au 12346", locale: "fr"
  Money.new(:AUD, "12346")

  iex> Money.parse "dollar australien 12346", locale: "fr"
  Money.new(:AUD, "12346")

  iex> Money.parse "A$ 12346", locale: "en"
  Money.new(:AUD, "12346")

  iex> Money.parse "australian dollar 12346.45", locale: "en"
  Money.new(:AUD, "12346.45")

  # Parse using a default currency
  iex> Money.parse("100", default_currency: :EUR)
  Money.new(:EUR, "100")

  # Parse using the default currency of the locale
	# If no `:locale` option is provided then
	# `Localize.get_locale/0` is used.
  iex> Money.parse("100", locale: "en")
  Money.new(:USD, "100")

  # Note that the decimal separator in the "de" locale
  # is a `.`
  iex> Money.parse "AU$ 12346,45", locale: "de"
  Money.new(:AUD, "12346.45")

  # Round trip formatting is supported
  iex> {:ok, string} = Localize.Number.to_string 1234, currency: :AUD
  {:ok, "A$1,234.00"}
  iex> Money.parse string
  #Money<:AUD, 1234.00>

  # Fuzzy matching is possible
  iex> Money.parse("100 eurosports", fuzzy: 0.8)
  Money.new(:EUR, "100")

  iex> Money.parse("100 eurosports", fuzzy: 0.9)
  {:error,
   {Money.Invalid, "Unable to create money from \"eurosports\" and \"100\""}}

  # Eligible currencies can be filtered
  iex> Money.parse("100 eurosports", fuzzy: 0.8, only: [:current])
  Money.new(:EUR, "100")

  iex> Money.parse("100 euro", only: [:EUR, :USD, :COP])
  Money.new(:EUR, "100")

  iex> Money.parse("100 euro", except: [:EUR, :USD, :COP])
  {:error,
    {Money.UnknownCurrencyError,
      "The currency \"euro\" is unknown or not supported"}}

  iex> Money.parse "100 afghan afghanis"
  Money.new(:AFN, "100")

  iex> Money.parse "100 afa", only: [:current]
  {:error,
   {Money.UnknownCurrencyError,
    "The currency \"afa\" is unknown or not supported"}}
```

### Casting a money type (basic support for HTML forms)

`Money` supports form field inputs that are a single string combining both a currency code and an amount.  When a form field (or other data) is [cast](https://hexdocs.pm/ecto/Ecto.Changeset.html#cast/4) then `Money` will attempt to parse a string field into a `Money.t` using `Money.parse/2`. Therefore simple money form input can be supported with a single input field of `type=text`.

Note that when parsing the input text, the amount is interpreted in the context of the current locale set via `Localize.get_locale/0`. This affects how separator characters are interpreted in exactly the same way as is done for `Money.new/3`.

### Float amounts cannot be provided to `Money.new/2`

Float have well-known issues in computing due to issues of rounding and potential precision loss.  Internally `Money` uses `Decimal` to store the amount which allows arbitrary precision arithmetic.  `Money` also uses the `numeric` type in Postgres to preserve precision and even goes to far as to store the amount as a `string` in `MySQL` for the same reason.

Therefore an error is returned if an attempt is made to use `Money.new/2` with a float amount:

    {:error,
     {Money.InvalidAmountError,
      "Float amounts are not supported in new/2 due to potential rounding " <>
        "and precision issues.  If absolutely required, use Money.from_float/2"}}

If the use of `float`s is require then the function `Money.from_float/2` is provided with the same arguments as those for `Money.new/2`.  `Money.from_float/2` provides an addition check and will return an error if the precision (number of digits) of the provided float is more than 15 (the number of digits guaranteed to round-trip between a 64-bit float and a string).

### Comparison functions

`Money` values can be compared as long as they have the same currency. The recommended function is `Money.compare/2` which, given two compatible money amounts, will return `:lt`, `:eq` or `:gt` depending on the relationship. For example:
```
iex> Money.compare Money.new(:USD, 100), Money.new(:USD, 200)
:lt

iex> Money.compare Money.new(:USD, 100), Money.new(:AUD, 200)
{:error,
 {ArgumentError,
  "Cannot compare monies with different currencies. Received :USD and :AUD."}}
```

From Elixir verison `1.10.0` onwards, several functions in the `Enum` module can use the `Money.compare/2` function to simplify sorting. For example:
```
iex> list = [Money.new(:USD, 100), Money.new(:USD, 200)]
[Money.new(:USD, "100"), Money.new(:USD, "200")]
iex> Enum.sort list, Money
[Money.new(:USD, "100"), Money.new(:USD, "200")]
iex> Enum.sort list, {:asc, Money}
[Money.new(:USD, "100"), Money.new(:USD, "200")]
iex> Enum.sort list, {:desc, Money}
[Money.new(:USD, "200"), Money.new(:USD, "100")]
```

**Note that `Enum.sort/2` will sort money amounts even when the currencies are incompatible. In this case the order of the result is not predictable. It is the developers responsibility to filter the list to compatible currencies prior to sorting. This is a limitation of the `Enum.sort/2` implementation.**

### Optional ~M sigil

An optional sigil module is available to aid in creating %Money{} structs.  It needs to be imported before use:

    import Money.Sigil

    ~M[100]USD
    #> Money.new(:USD, "100")

### Localised Money formatting

`Money` provides locale-specific formatted output that is controlled by either the locale that has been set for this process or by the `:locale` parameter supplied to `Money.to_string/2`.

The main API for formatting `Money` is `Money.to_string/2`. Formatting options are passed to `Localize.Number.to_string/2`. See the [localize documentation](https://hexdocs.pm/localize) for more information.

    iex> Money.to_string Money.new("thb", 11)
    {:ok, "THB\u00A011.00"}

    iex> Money.to_string Money.new("USD", "234.467")
    {:ok, "$234.47"}

    # The locale "en" is "American English".  For
    # UK English use the locale "en-GB".  Australian
    # English is "en-AU" and so on.
    iex> Money.to_string Money.new("USD", "234.467"), locale: "en"
    {:ok, "$234.47"}

    iex> Money.to_string Money.new("USD", "234.467"), format: :long
    {:ok, "234 US dollars"}

    iex> Money.to_string Money.new("USD", "234.467"), locale: "fr"
    {:ok, "234,47 $US"}

    iex> Money.to_string Money.new("USD", "234.467"), locale: "de"
    {:ok, "234,47 $"}

    iex> Money.to_string Money.new("EUR", "234.467"), locale: "de"
    {:ok, "234,47 €"}

    iex> Money.to_string Money.new("EUR", "234.467"), locale: "fr"
    {:ok, "234,47 €"}

**Note that the output is influenced by the locale in effect.** By default the locale used is that returned by `Localize.get_locale/0`. Its default value is `:en`. Additional locales can be configured via the `localize` application configuration. The formatting options are defined in `Localize.Number.to_string/2`.

### Arithmetic Functions

Some basic math functions are available to operate on `Money` structs.

    iex> m1 = Money.new(:USD, 100)
    Money.new(:USD, "100")

    iex> m2 = Money.new(:USD, 200)
    Money.new(:USD, "200")

    iex> Money.add(m1, m2)
    {:ok, Money.new(:USD, "300")}

    iex> Money.add!(m1, m2)
    Money.new(:USD, "300")

    iex> m3 = Money.new(:AUD, 300)
    Money.new(:AUD, "300")

    iex> Money.add Money.new(:USD, 200), Money.new(:AUD, 100)
    {:error,
      {ArgumentError,
        "Cannot add monies with different currencies. Received :USD and :AUD."}}

    # Split a %Money{} returning the a dividend and a remainder. All
    # operations respect the number of fractional digits defined for a currency
    iex> m1 = Money.new(:USD, 100)
    Money.new(:USD, "100")

    iex> Money.split(m1, 3)
    {Money.new(:USD, "33.33"), Money.new(:USD, "0.01")}

    # Rounding applies the currency definitions of CLDR as implemented in
    # the hex package [localize](https://hex.pm/packages/localize)
    iex> Money.round Money.new(:USD, "100.678")
    Money.new(:USD, "100.68")

    iex> Money.round Money.new(:JPY, "100.678")
    Money.new(:JPY, "101")

### Currency Conversion

A `%Money{}` struct can be converted to another currency using `Money.to_currency/3` or `Money.to_currency!/3`.  For example:

    iex> Money.to_currency Money.new(:USD, 100), :AUD
    {:ok, Money.new(:AUD, "152.9300")}

    iex> Money.to_currency Money.new(:USD, 100), :AUD, Money.ExchangeRates.historic_rates(~D[2017-01-01])
    {:ok, Money.new(:AUD, "138.6200")}

    iex> Money.to_currency Money.new(:USD, 100) , :AUDD, %{USD: Decimal.new(1), AUD: Decimal.new("0.7345")}
    {:error, {Money.UnknownCurrencyError, "The currency :AUDD is not known."}}

    iex> Money.to_currency! Money.new(:USD, 100), :XXX
    ** (Money.ExchangeRateError) No exchange rate is available for currency :XXX

A user-defined map of exchange rates can also be supplied:

    iex> Money.to_currency Money.new(:USD, 100), :AUD, %{USD: Decimal.new("1.0"), AUD: Decimal.new("1.3")}
    {:ok, Money.new(:AUD, "130.0")}

### Historic Conversion Rates

As noted in the [configuration](#configuration) section, `ex_money` can preload historic exchange rates when the exchange rates service starts up.  It can be anticipated that additional historic rates may be required subsequently.

* `Money.ExchangeRates.Retriever.historic_rates/1` can be called to request retrieval of historic rates at any time.  This call will send a message to the retrieval service to request retrieval.  It does not return the rates.

* `Money.ExchangeRates.historic_rates/1` is the partner function to `Money.ExchangeRates.latest_rates/0`.  It returns the exchange rates for a given date, and will return an error if no rates are available.

### Financial Functions

A set of basic financial functions are available in the module `Money.Financial`.   These functions are:

* Present value: `Money.Financial.present_value/3`
* Future value: `Money.Financial.future_value/3`
* Interest rate: `Money.Financial.interest_rate/3`
* Number of periods: `Money.Financial.periods/3`
* Payment amount: `Money.Financial.payment/3`
* Net Present Value of a set of cash flows: `Money.Financial.net_present_value/2`
* Internal rate of return: `Money.Financial.internal_rate_of_return/1`

For more detail see `Money.Financial`.

## Subscriptions

Subscriptions, especially in the context of a SaaS, can involve changing plans - either from a smaller plan to a larger or a larger plan to smaller.  In either situation a credit amount needs to be calculated based upon the current plan which is then applied to the new plan.  `Money.Subscription` is a module that provides functions to support this subscription pricing, credit calculations and payment dates.

The primary functions supporting subscriptions are:

* Create a new subscription: `Money.Subscription.new/3`
* Create a subscription plan: `Money.Subscription.Plan.new/3`
* Change a from one plan to another: `Money.Subscription.change_plan/3`
* Calculate the start date for the next interval of a plan: `Money.Subscription.next_interval_starts/3`
* Calculate the number of days in a plan interval: `Money.Subscription.plan_days/3`
* Calculate the number of days left in a plan interval: `Money.Subscription.days_remaining/4`

### Examples

    # Create the current plan
    iex> current_plan = Money.Subscription.Plan.new!(Money.new(:USD, 10), :month, 1)
    %Money.Subscription.Plan{
      price: Money.new(:USD, "10"),
      interval: :month,
      interval_count: 1
    }

    # How many days in a billing period?
    iex> Money.Subscription.plan_days current_plan, ~D[2018-03-01]
    31

    iex> Money.Subscription.plan_days current_plan, ~D[2018-02-01]
    28

    # How many days remaining in the current billing period
    iex> Money.Subscription.days_remaining current_plan, ~D[2018-03-01], ~D[2018-03-10]
    22

    # When is the next billing date
    iex> Money.Subscription.next_interval_starts current_plan, ~D[2018-03-01]
    ~D[2018-04-01]

    # Create a new plan
    iex> new_plan = Money.Subscription.Plan.new!(Money.new(:USD, 10), :month, 3)
    %Money.Subscription.Plan{
      price: Money.new(:USD, "10"),
      interval: :month,
      interval_count: 3
    }

    # Change plans at the end of the current billing period
    iex> Money.Subscription.change_plan! current_plan, new_plan, current_interval_started: ~D[2018-03-01]
    %Money.Subscription.Change{
      first_billing_amount: Money.new(:USD, "10"),
      first_interval_starts: ~D[2018-04-01],
      next_interval_starts: ~D[2018-07-01],
      credit_amount_applied: Money.new(:USD, "0"),
      credit_amount: Money.new(:USD, "0"),
      credit_days_applied: 0,
      credit_period_ends: nil,
      carry_forward: Money.new(:USD, "0")
    }

    # Change plans in the middle of the current plan period
    # and credit the balance of the current plan to the new plan
    iex> Money.Subscription.change_plan! current_plan, new_plan, current_interval_started: ~D[2018-03-01], effective: ~D[2018-03-15]
    %Money.Subscription.Change{
      first_billing_amount: Money.new(:USD, "4.51"),
      first_interval_starts: ~D[2018-03-15],
      next_interval_starts: ~D[2018-06-15],
      credit_amount_applied: Money.new(:USD, "5.49"),
      credit_amount: Money.new(:USD, "5.49"),
      credit_days_applied: 0,
      credit_period_ends: nil,
      carry_forward: Money.new(:USD, "0")
    }

    # Change plans in the middle of the current plan period
    # but instead of a monetary credit, apply the credit as
    # extra days on the new plan in the first billing period
    iex> Money.Subscription.change_plan! current_plan, new_plan, current_interval_started: ~D[2018-03-01], effective: ~D[2018-03-15], prorate: :period
    %Money.Subscription.Change{
      first_billing_amount: Money.new(:USD, "10"),
      first_interval_starts: ~D[2018-03-15],
      next_interval_starts: ~D[2018-08-05],
      credit_amount_applied: Money.new(:USD, "0"),
      credit_amount: Money.new(:USD, "5.49"),
      credit_days_applied: 51,
      credit_period_ends: ~D[2018-05-04],
      carry_forward: Money.new(:USD, "0")
    }

    # Create a subscription
    iex> plan = Money.Subscription.Plan.new!(Money.new(:USD, 200), :month, 3)
    iex> subscription = Money.Subscription.new! plan, ~D[2018-01-01]
    %Money.Subscription{
      id: nil,
      plans: [
        {%Money.Subscription.Change{
          first_billing_amount: Money.new(:USD, "200"),
          first_interval_starts: ~D[2018-01-01],
          next_interval_starts: ~D[2018-04-01],
          credit_amount_applied: Money.new(:USD, "0"),
          credit_amount: Money.new(:USD, "0"),
          credit_days_applied: 0,
          credit_period_ends: nil,
          carry_forward: Money.new(:USD, "0")
        },
        %Money.Subscription.Plan{
          price: Money.new(:USD, "200"),
          interval: :month,
          interval_count: 3
        }}
      ],
      created_at: ~U[2025-08-30 04:20:22.018760Z]
    }

    # Change a subscription's plan
    iex> new_plan = Money.Subscription.Plan.new!(Money.new(:USD, 150), :day, 30)
    iex> Money.Subscription.change_plan! subscription, new_plan
    %Money.Subscription{
      id: nil,
      plans: [
        {%Money.Subscription.Change{
          first_billing_amount: Money.new(:USD, "150"),
          first_interval_starts: ~D[2025-10-01],
          next_interval_starts: ~D[2025-10-31],
          credit_amount_applied: Money.new(:USD, "0"),
          credit_amount: Money.new(:USD, "0"),
          credit_days_applied: 0,
          credit_period_ends: nil,
          carry_forward: Money.new(:USD, "0")
        },
        %Money.Subscription.Plan{
          price: Money.new(:USD, "150"),
          interval: :day,
          interval_count: 30
        }},
        {%Money.Subscription.Change{
          first_billing_amount: Money.new(:USD, "200"),
          first_interval_starts: ~D[2018-01-01],
          next_interval_starts: ~D[2018-04-01],
          credit_amount_applied: Money.new(:USD, "0"),
          credit_amount: Money.new(:USD, "0"),
          credit_days_applied: 0,
          credit_period_ends: nil,
          carry_forward: Money.new(:USD, "0")
        },
        %Money.Subscription.Plan{
          price: Money.new(:USD, "200"),
          interval: :month,
          interval_count: 3
        }}
      ],
      created_at: ~U[2025-08-30 04:20:22.018760Z]
    }

## Serializing to a database with Ecto

The companion package [ex_money_sql](https://hex.pm/packages/ex_money_sql) provides functions for the serialization of `Money` data.  See the [README](https://hexdocs.pm/ex_money_sql/readme.html) for further information.

## Installation

`Money` can be installed by adding `ex_money` to your list of dependencies in `mix.exs` and then executing `mix deps.get`

```elixir
def deps do
  [
    {:ex_money, "~> 5.0"},
    ...
  ]
end
```

## Why yet another Money package?

* Fully localized formatting and rounding using [localize](https://hex.pm/packages/localize)

* Provides serialization to Postgres using a composite type and MySQL using a JSON type that keeps both the currency code and the amount together removing a source of potential error

* Uses the `Decimal` type in Elixir and the Postgres `numeric` type to preserve precision.  For MySQL the amount is serialised as a string to preserve precision that might otherwise be lost if stored as a JSON numeric type (which is either an integer or a float)

* Includes a set of financial calculations (arithmetic and cash flow calculations) that follow solid rounding rules

## Falsehoods programmers believe about prices

The [github gist](https://gist.github.com/rgs/6509585) gives a good summary of the challenges of managing money in an application. The following described how `Money` handles each of these assertions.

**1. You can store a price in a floating point variable.**

`Money` operates and serialises in a arbitrary precision Decimal value.

**2. All currencies are subdivided in 1/100th units (like US dollar/cents, euro/eurocents etc.).**

`Money` leverages CLDR which defines the appropriate number of decimal places of a currency. As of CLDR version 32 there are:

  * 52 currencies with zero decimal digits
  * 241 currencies with two decimal digits
  * 6 currencies with three decimal digits
  * and 1 currency with four decimal digits

**3. All currencies are subdivided in decimal units (like dinar/fils)**

**4. All currencies currently in circulation are subdivided in decimal units. (to exclude shillings, pennies) (counter-example: MGA)**

**5. All currencies are subdivided. (counter-examples: KRW, COP, JPY... Or subdivisions can be deprecated.)**

`Money` correctly manages the appropriate number of decimal places for a currency.  It also round correctly when formatting a currency for output (different currencies have different rounding levels for cash or transactions).

**6. Prices can't have more precision than the smaller sub-unit of the currency. (e.g. gas prices)**

All `Money` calculations are done with decimal arithmetic to the maxium precision of 28 decimal digits.

**7. For any currency you can have a price of 1. (ZWL)**

`Money` makes no assumption about the value assigned as long as its a real number.

**8. Every country has its own currency. (EUR is the best example, but also Franc CFA, etc.)**

`Money` makes no assumptions about the linkage of currencies to territories.

**9. No country uses another's country official currency as its official currency. (many countries use USD: Ecuador, Micronesia...)**

**10. Countries have only one currency.**

`Money` doesn't link territories (countries) to a currency - it focuses only on the `Money` domain. The `Localize.Territory` module has knowledge of what currencies are in effect throughout history for a given territory.

**11. Countries have only one currency currently in circulation. (Panama officially uses both PAB and USD)**

`Money` makes no assumptions about currencies in circulation.

**12. I'll only deal with currencies currently in circulation anyway.**

`Money` makes no assumptions about currencies in circulation.

**13. All currencies have an ISO 4217 3-letter code. (The Transnistrian ruble has none, for example)**

`Money` does validate currency codes against the ISO 4217 list. Custom currencies can be created in accordance with ISO 4217 using `Money.Currency.new/2`.

**14. All currencies have a different name. (French franc, "nouveau franc")**

`Money` has localised names for all ISO 4217 currencies in each of the over 500 locales defined by CLDR.

**15. You always put the currency symbol after the price.**

`Money` formats currency strings according to a format mask that is either defined by CLDR or user supplied.

**16. You always put the currency symbol before the price.**

`Money` formats currency strings according to a format mask that is either defined by CLDR or user supplied.

**17. You always put the currency symbol either after, or before the price, never in the middle.**

`Money` formats currency strings according to a format mask that is either defined by CLDR or user supplied.

**18. There's only one currency symbol for any currency. (元, 角, 分 are increasing units of the Chinese renminbi.)**

`Money` uses format masks defined by CLDR which, for the Chinese renminbi uses the "￥" symbol.

**19. For a given currency, you always, but always, put the symbol in the same place.**

`Money` makes no assumpions about symbol placement.  The symbol can be places anywhere in a formatted string but is typically, for CLDR format masks, placed either before or after the formatted number.

**20. OK. But if you only use the ISO 4217 currency codes, you always put it before the price. (Hint: it depends on the language.)**

Same as for the answer to 19 above.

**21. Before the price means on the left. (ILS)**

`Money` formats according to a locale and correctly places symbols for languages written right-to-left.

**22. You can always use a dot (or a comma, etc.) as a decimal separator.**

The decimal separator is defined per locale according to the CLDR definitions.

**23. You can always use a space (or a dot, or a comma, etc.) as a thousands separator.**

The thousands (acutally grouping since not all locales format in thousands) separator is defined per locale according to the CLDR definitions.

**24. You separate big prices by grouping numbers in triplets (thousands). (One writes ¥1 0000)**

Grouping is done according the CLDR definitions.  For many languages the grouping is in thousands.  Some format other ways.  For example in India numbers are formatted with the first group as a triplet and subsequent groups as doublets.

**25. Prices at a single company will never range from five digits before the decimal to five digits after.**

`Money`'s default precision is 28 decimal digits.  All arithmetic is done using arbitrary precision decimal arithemetic.  No round is performed unless either explicitly requested or a money value is formatted for output.  When formatting rounding is applied according the locale-specific rules.

**26. Prices contains only digits and punctuation. (Germans can write 12,- €)**

`Money` format masks can contain very flexible formatting masks.  A set of formats is defined for each locale and a user-defined masks can also be defined.

**27. A price can be at most 10^N for some value of N.**

See the answer to 25.

**28. Given two currencies, there is only one exchange rate between them at any given point in time.**

`Money` supports an exchange rate mechansim, currency conversions and retrieval from external exchange rate services.  It does not impose any constraint on underlying conversion tables.

**29. Given two currencies, there is at least one exchange rate between them at any given point in time. (restriction on export of MAD, ARS, CNY, for example)**

See the answer to 28.

**30. And the final one: a standalone $ character is always pronounced dollar. (It's also the peso sign.)**

This is outside the domain of `Money`.
