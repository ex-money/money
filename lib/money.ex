defmodule Money do
  @moduledoc """
  Money implements a set of functions to store, retrieve, convert and perform
  arithmetic on a `t:Money.t/0` type that is composed of a currency code and
  a decimal currency amount.

  Money is very opinionated in the interests of serving as a dependable library
  that can underpin accounting and financial applications.

  This opinion expressed by ensuring that:

  1. Money must always have both a amount and a currency code.

  2. The currency code must always be valid.

  3. Money arithmetic can only be performed when both operands are of the
     same currency.

  4. Money amounts are represented as a `Decimal`.

  5. Money is serialised to the database as a custom Postgres composite type
     that includes both the amount and the currency. Therefore for Ecto
     serialization Postgres is assumed as the data store. Serialization is
     entirely optional and Ecto is not a package dependency.

  6. All arithmetic functions work in fixed point decimal.  No rounding
     occurs automatically (unless expressly called out for a function).

  7. Explicit rounding obeys the rounding rules for a given currency.  The
     rounding rules are defined by the Unicode consortium in its CLDR
     repository as implemented by the hex package `localize`.  These rules
     define the number of fractional digits for a currency and the rounding
     increment where appropriate.

  """

  import Kernel, except: [round: 1, abs: 1]

  # `:digital_token` is an optional dependency. Runtime call sites are all
  # guarded with `Code.ensure_loaded?(DigitalToken)`, but the compiler still
  # warns about unknown remote calls. Suppress those warnings.
  @compile {:no_warn_undefined, DigitalToken}

  @typedoc """
  A value that can reference a currency. This is either:

  * An atom — an ISO 4217 currency code (e.g. `:USD`) or a custom/private-use
    currency code registered via `Money.Currency.new/2` (e.g. `:XBT`).

  * A binary — either a string form of an ISO code (e.g. `"USD"`), a digital
    token short name (e.g. `"BTC"`), or a 9-character ISO 24165 digital
    token identifier (DTI).

  """
  @type currency_reference :: atom() | String.t()

  @typedoc """
  Money is composed of an atom representation of an ISO4217 currency code or a custom
  currency code and a `Decimal` representation of an amount.
  """
  @type t :: %Money{
          currency: currency_reference(),
          amount: Decimal.t(),
          format_options: Keyword.t()
        }

  @typedoc """
  An amount can be expressed as a float, an integer,
  a Decimal or a string (which is converted to a Decimal)

  """
  @type amount :: float() | integer() | Decimal.t() | String.t()

  @enforce_keys [:currency, :amount]
  defstruct currency: nil, amount: nil, format_options: []

  # Default mode for rounding is :half_even, also known
  # as bankers rounding
  @default_rounding_mode :half_even

  alias Money.ExchangeRates

  def known_currencies do
    Localize.Currency.known_currency_codes() ++ Money.Currency.Store.codes()
  end

  defdelegate known_current_currencies, to: Money.Currency
  defdelegate known_historic_currencies, to: Money.Currency
  defdelegate known_tender_currencies, to: Money.Currency

  @doc false
  defguard is_currency_code(currency_code)
           when is_atom(currency_code) or is_binary(currency_code)

  @doc false
  defguard is_digital_token(token_id)
           when is_binary(token_id) and byte_size(token_id) == 9

  @doc """
  Returns a `t:Money.t/0` from a currency code and a currency amount or
  an error tuple of the form `{:error, {exception, message}}`.

  ### Arguments

  * `currency_code` is an [ISO4217](https://en.wikipedia.org/wiki/ISO_4217)
    binary or atom currency code or an
    [ISO 24165](https://www.iso.org/standard/80601.html) token identifier or shortname.

  * `amount` is an integer, string or Decimal money amount.

  * `options` is a keyword list of options.

  ### Options

  * `:locale` is any known locale.  The locale is used to normalize any
    binary (String) amounts to a form that can be consumed by `Decimal.new/1`.
    This consists of removing any localised grouping characters and replacing
    the localised decimal separator with a ".".
    The default is `Localize.get_locale/0`.

  * `:separators` selects which of the available symbol
    sets should be used when attempting to parse a string into a number.
    The default is `:standard`. Some limited locales have an alternative `:us`
    variant that can be used. See `Localize.Number.Symbol.number_symbols_for/2`
    for the symbols supported for a given locale and number system.

  * `:dti_type` specifies the digital token type when the currency code
    is a digital token short name or long name that maps to more than one
    token identifier. One of `:native`, `:auxiliary`, `:distributed`, or
    `:fungible`. When not specified, the lookup tries each type in priority
    order: `:native`, `:auxiliary`, `:distributed`, `:fungible`. The first
    match wins. This option is only relevant for digital tokens and is
    ignored for ISO 4217 currencies.

  * Any other options are considered as formatting options to
    be applied by default when calling `Money.to_string/2`.

  Note that the `currency_code` and `amount` arguments can be supplied in
  either order,

  ### Examples

      iex> Money.new(:USD, 100)
      Money.new(:USD, "100")

      iex> Money.new(100, :USD)
      Money.new(:USD, "100")

      iex> Money.new("USD", 100)
      Money.new(:USD, "100")

      iex> Money.new("thb", 500)
      Money.new(:THB, "500")

      iex> Money.new("EUR", Decimal.new(100))
      Money.new(:EUR, "100")

      iex> Money.new(:EUR, "100.30")
      Money.new(:EUR, "100.30")

      iex> Money.new(:EUR, "100.30", fractional_digits: 4)
      Money.new(:EUR, "100.30", fractional_digits: 4)

      iex> Money.new(:XYZZ, 100)
      {:error, {Money.UnknownCurrencyError, "The currency :XYZZ is not known."}}

      iex> Money.new("1.000,99", :EUR, locale: "de")
      Money.new(:EUR, "1000.99")

      iex> Money.new 123.445, :USD
      {:error,
       {Money.InvalidAmountError,
        "Float amounts are not supported in new/2 due to potential " <>
        "rounding and precision issues.  If absolutely required, " <>
        "use Money.from_float/2"}}

  """
  @spec new(
          amount | currency_reference(),
          amount | currency_reference(),
          Keyword.t()
        ) ::
          Money.t() | {:error, {module(), String.t()}}

  def new(currency_code, amount, options \\ [])

  # For integer amounts

  def new(currency_code, amount, options)
      when is_currency_code(currency_code) and is_integer(amount) do
    with {:ok, code} <- validate_currency(currency_code, options) do
      format_options = extract_format_options(options)
      %Money{amount: Decimal.new(amount), currency: code, format_options: format_options}
    else
      {:error, {Money.UnknownCurrencyError, message}} ->
        {:error, {Money.UnknownCurrencyError, message}}
    end
  end

  def new(amount, currency_code, options)
      when is_currency_code(currency_code) and is_integer(amount) do
    new(currency_code, amount, options)
  end

  # For Decimal amouonts

  def new(currency_code, %Decimal{} = amount, options) when is_currency_code(currency_code) do
    with {:ok, amount} <- validate_not_nan_or_inf(amount),
         {:ok, code} <- validate_currency(currency_code, options) do
      format_options = extract_format_options(options)
      %Money{amount: amount, currency: code, format_options: format_options}
    else
      {:error, {Money.UnknownCurrencyError, message}} ->
        {:error, {Money.UnknownCurrencyError, message}}

      {:error, {Money.InvalidAmountError, message}} ->
        {:error, {Money.InvalidAmountError, message}}
    end
  end

  def new(%Decimal{} = amount, currency_code, options) when is_currency_code(currency_code) do
    new(currency_code, amount, options)
  end

  # For Float amounts

  def new(_currency_code, amount, _options) when is_float(amount) do
    {:error,
     {Money.InvalidAmountError,
      "Float amounts are not supported in new/2 due to potential rounding " <>
        "and precision issues.  If absolutely required, use Money.from_float/2"}}
  end

  def new(amount, _currency_code, _options) when is_float(amount) do
    {:error,
     {Money.InvalidAmountError,
      "Float amounts are not supported in new/2 due to potential rounding " <>
        "and precision issues.  If absolutely required, use Money.from_float/2"}}
  end

  # These clauses deal with invalid currency codes or amounts

  def new(currency_code, amount, _options) when is_integer(amount) do
    {:error, unknown_currency_error(currency_code)}
  end

  def new(amount, currency_code, _options) when is_integer(amount) do
    {:error, unknown_currency_error(currency_code)}
  end

  def new(currency_code, %Decimal{} = _amount, _options) do
    {:error, unknown_currency_error(currency_code)}
  end

  def new(%Decimal{} = _amount, currency_code, _options) do
    {:error, unknown_currency_error(currency_code)}
  end

  # Last chance saloon, see if we can parse either parameter
  # as a Decimal

  def new(param_a, param_b, options) do
    cond do
      decimal = maybe_decimal(param_a, options) ->
        new(param_b, decimal, options)

      decimal = maybe_decimal(param_b, options) ->
        new(param_a, decimal, options)

      true ->
        {:error, invalid_money_error(param_a, param_b)}
    end
  end

  defp validate_not_nan_or_inf(%Decimal{} = amount) do
    if Decimal.nan?(amount) or Decimal.inf?(amount) do
      {:error, {Money.InvalidAmountError, "Invalid money amount. Found #{inspect(amount)}."}}
    else
      {:ok, amount}
    end
  end

  defp extract_format_options(options) do
    options
    |> Keyword.delete(:locale)
    |> Keyword.delete(:backend)
    |> Keyword.delete(:default_currency)
    |> Keyword.delete(:separators)
    |> Keyword.delete(:dti_type)
  end

  @doc """
  Returns a `t:Money.t/0` from a currency code and a currency amount. Raises an
  exception if the current code is invalid.

  ### Arguments

  * `currency_code` is an [ISO4217](https://en.wikipedia.org/wiki/ISO_4217)
    binary or atom currency code or an
    [ISO 24165](https://www.iso.org/standard/80601.html) token identifier or shortname.

  * `amount` is an integer, float or Decimal

  * `options` is a keyword list of options. See `Money.new/3`.

  ### Examples

      Money.new!(:XYZZ, 100)
      ** (Money.UnknownCurrencyError) Currency :XYZZ is not known
        (ex_money) lib/money.ex:177: Money.new!/2

  """
  @spec new!(
          amount | currency_reference(),
          amount | currency_reference(),
          Keyword.t()
        ) ::
          Money.t() | no_return()

  def new!(currency_code, amount, options \\ [])

  def new!(currency_code, amount, options)
      when is_binary(currency_code) or is_atom(currency_code) do
    case money = new(currency_code, amount, options) do
      {:error, {exception, message}} -> raise exception, message
      _ -> money
    end
  end

  def new!(amount, currency_code, options)
      when (is_binary(currency_code) or is_atom(currency_code)) and is_number(amount) do
    new!(currency_code, amount, options)
  end

  def new!(%Decimal{} = amount, currency_code, options)
      when is_binary(currency_code) or is_atom(currency_code) do
    new!(currency_code, amount, options)
  end

  def new!(currency_code, %Decimal{} = amount, options)
      when is_binary(currency_code) or is_atom(currency_code) do
    new!(currency_code, amount, options)
  end

  @doc """
  Returns a `t:Money.t/0` from a currency code and a float amount, or
  an error tuple of the form `{:error, {exception, message}}`.

  Floats are fraught with danger in computer arithmetic due to the
  unexpected loss of precision during rounding. The IEEE754 standard
  indicates that a number with a precision of 16 digits should
  round-trip convert without loss of fidelity. This function supports
  numbers with a precision up to 15 digits and will error if the
  provided amount is outside that range.

  **Note** that `Money` cannot detect lack of precision or rounding errors
  introduced upstream. This function therefore should be used with
  great care and its use should be considered potentially harmful.

  ### Arguments

  * `currency_code` is an [ISO4217](https://en.wikipedia.org/wiki/ISO_4217)
    binary or atom currency code or an
    [ISO 24165](https://www.iso.org/standard/80601.html) token identifier or shortname.

  * `amount` is a float

  * `options` is a keyword list of options passed
    to `Money.new/3`. The default is `[]`.

  ### Examples

      iex> Money.from_float 1.23456, :USD
      Money.new(:USD, "1.23456")

      iex> Money.from_float 1.234567890987656, :USD
      {:error,
        {Money.InvalidAmountError,
          "The precision of the float 1.234567890987656 is " <>
          "greater than 15 which could lead to unexpected results. " <>
          "Reduce the precision or call Money.new/2 with a Decimal or String amount"}}

  """
  @doc since: "2.0.0"
  @max_precision_allowed 15
  @spec from_float(
          float | currency_reference(),
          float | currency_reference(),
          Keyword.t()
        ) ::
          Money.t() | {:error, {module(), String.t()}}

  def from_float(currency_code, amount, options \\ [])

  def from_float(currency_code, amount, options)
      when (is_binary(currency_code) or is_atom(currency_code)) and is_float(amount) do
    if Localize.Utils.Digits.number_of_digits(amount) <= @max_precision_allowed do
      new(currency_code, Decimal.from_float(amount), options)
    else
      {:error,
       {Money.InvalidAmountError,
        "The precision of the float #{inspect(amount)} " <>
          "is greater than #{inspect(@max_precision_allowed)} " <>
          "which could lead to unexpected results. Reduce the " <>
          "precision or call Money.new/2 with a Decimal or String amount"}}
    end
  end

  def from_float(amount, currency_code, options)
      when (is_binary(currency_code) or is_atom(currency_code)) and is_float(amount) do
    from_float(currency_code, amount, options)
  end

  @doc """
  Returns a `t:Money.t/0` from a currency code and a float amount, or
  raises an exception if the currency code is invalid.

  See `Money.from_float/2` for further information.

  **Note** that `Money` cannot detect lack of precision or rounding errors
  introduced upstream. This function therefore should be used with
  great care and its use should be considered potentially harmful.

  ### Arguments

  * `currency_code` is an [ISO4217](https://en.wikipedia.org/wiki/ISO_4217)
    binary or atom currency code or an
    [ISO 24165](https://www.iso.org/standard/80601.html) token identifier or shortname.

  * `amount` is a float.

  * `options` is a keyword list of options passed
    to `Money.new/3`. The default is `[]`.

  ### Examples

      iex> Money.from_float!(:USD, 1.234)
      Money.new(:USD, "1.234")

      Money.from_float!(:USD, 1.234567890987654)
      #=> ** (Money.InvalidAmountError) The precision of the float 1.234567890987654 is greater than 15 which could lead to unexpected results. Reduce the precision or call Money.new/2 with a Decimal or String amount
          (ex_money) lib/money.ex:293: Money.from_float!/2

  """
  @doc since: "2.0.0"
  @spec from_float!(currency_reference(), float, Keyword.t()) :: Money.t() | no_return()

  def from_float!(currency_code, amount, options \\ []) do
    case from_float(currency_code, amount, options) do
      {:error, {exception, reason}} -> raise exception, reason
      money -> money
    end
  end

  @doc """
  Add format options to a `t:Money.t/0`.

  ### Arguments

  * `money` is any valid `t:Money.t/0` type returned
    by `Money.new/2`.

  * `options` is a keyword list of options. These
    options are used when calling `Money.to_string/2`.
    The default is `[]`.

  """

  @doc since: "5.5.0"
  @spec put_format_options(Money.t(), Keyword.t()) :: Money.t()
  def put_format_options(%Money{} = money, options) when is_list(options) do
    %{money | format_options: options}
  end

  @doc """
  Parse a string and return a `t:Money.t/0` or an error.

  The string to be parsed is required to have a currency
  code and an amount.  The currency code may be placed
  before the amount or after, but not both.

  Parsing is strict.  Additional text surrounding the
  currency code and amount will cause the parse to
  fail.

  ### Arguments

  * `string` is a string to be parsed

  * `options` is a keyword list of options that is
    passed to `Money.new/3` with the exception of
    the options listed below

  ### Options

  * `:locale` is any valid locale returned by `Localize.supported_locales/0`
    or a `Localize.LanguageTag` struct.
    The default is `Localize.get_locale/0`.

  * `:only` is an `atom` or list of `atoms` representing the
    currencies or currency types to be considered for a match.
    The equates to a list of acceptable currencies for parsing.
    See the notes below for currency types.

  * `:except` is an `atom` or list of `atoms` representing the
    currencies or currency types to be not considered for a match.
    This equates to a list of unacceptable currencies for parsing.
    See the notes below for currency types.

  * `:fuzzy` is a float greater than `0.0` and less than or
    equal to `1.0` which is used as input to the
    `String.jaro_distance/2` to determine is the provided
    currency string is *close enough* to a known currency
    string for it to identify definitively a currency code.
    It is recommended to use numbers greater than `0.8` in
    order to reduce false positives.

  * `:default_currency` is any valid currency code or `false`
    that will used if no currency code, symbol or description is
    indentified in the parsed string. The default is `nil`
    which means that the default currency associated with
    the `:locale` option will be used. If `false` then the
    currency assocated with the `:locale` option will not be
    used and an error will be returned if there is no currency
    in the string being parsed.

  ### Returns

  * a `t:Money.t/0` if parsing is successful or

  * `{:error, {exception, reason}}` if an error is
    detected.

  ### Notes

  The `:only` and `:except` options accept a list of
  currency codes and/or currency types.  The following
  types are recognised.

  If both `:only` and `:except` are specified,
  the `:except` entries take priority - that means
  any entries in `:except` are removed from the `:only`
  entries.

    * `:all`, the default, considers all currencies.

    * `:current` considers those currencies that have a `:to`
      date of nil and which also is a known ISO4217 currency.

    * `:historic` is the opposite of `:current`.

    * `:tender` considers currencies that are legal tender.

    * `:unannotated` considers currencies that don't have
      "(some string)" in their names.  These are usually
      financial instruments.

  ### Examples

      iex> Money.parse("USD 100")
      Money.new(:USD, "100")

      iex> Money.parse "USD 100,00", locale: "de"
      Money.new(:USD, "100.00")

      iex> Money.parse("100 USD")
      Money.new(:USD, "100")

      iex> Money.parse("100 eurosports", fuzzy: 0.8)
      Money.new(:EUR, "100")

      iex> Money.parse("100", default_currency: :EUR)
      Money.new(:EUR, "100")

      iex> Money.parse("100 eurosports", fuzzy: 0.9)
      {:error, {Money.UnknownCurrencyError, "The currency \\"eurosports\\" is unknown or not supported"}}

      iex> Money.parse("100 afghan afghanis")
      Money.new(:AFN, "100")

      iex> Money.parse("100", default_currency: false)
      {:error, {Money.Invalid,
        "A currency code, symbol or description must be specified but was not found in \\"100\\""}}

      iex> Money.parse("USD 100 with trailing text")
      {:error, {Money.ParseError, "Could not parse \\"USD 100 with trailing text\\"."}}

  """
  @doc since: "3.2.0"
  @spec parse(String.t(), Keyword.t()) :: Money.t() | {:error, {module(), String.t()}}

  def parse(string, options \\ []) do
    with {:ok, result, "", _, _, _} <- Money.Parser.money_parser(String.trim(string)) do
      result
      |> Enum.map(fn {k, v} -> {k, String.trim_trailing(v)} end)
      |> Keyword.put_new(:currency, Keyword.get(options, :default_currency))
      |> Map.new()
      |> maybe_create_money(string, options)
    else
      _ ->
        {:error, {Money.ParseError, "Could not parse #{inspect(string)}."}}
    end
  end

  # No currency was in the string and options[:default_currency] == false
  # meaning don't derive it from the locale
  defp maybe_create_money(%{currency: false}, string, _options) do
    {:error,
     {Money.Invalid,
      "A currency code, symbol or description must be specified but " <>
        "was not found in #{inspect(string)}"}}
  end

  # No currency was in the string so we'll derive it from
  # the locale
  defp maybe_create_money(%{currency: nil} = money_map, string, options) do
    locale = Keyword.get(options, :locale, Localize.get_locale())

    with {:ok, locale} <- Localize.validate_locale(locale),
         {:ok, currency} <- Localize.Currency.currency_from_locale(locale) do
      money_map
      |> Map.put(:currency, currency)
      |> maybe_create_money(string, options)
    end
  end

  defp maybe_create_money(%{currency: currency, amount: amount}, _string, options) do
    locale = Keyword.get(options, :locale, Localize.get_locale())
    currency = Kernel.to_string(currency)

    {only_filter, options} =
      Keyword.pop(options, :only, Keyword.get(options, :currency_filter, [:all]))

    {except_filter, options} = Keyword.pop(options, :except, [])
    {fuzzy, options} = Keyword.pop(options, :fuzzy, nil)

    only_filter = normalize_filter(only_filter)
    except_filter = normalize_filter(except_filter)

    with {:ok, locale} <- Localize.validate_locale(locale),
         {:ok, currency_strings} <-
           Localize.Currency.currency_strings(locale, only_filter, except_filter),
         {:ok, currency} <-
           find_currency(currency_strings, currency, fuzzy) do
      Money.new(currency, amount, options)
    end
  end

  defp find_currency(currency_strings, currency, nil) do
    canonical_currency =
      currency
      |> String.downcase()
      |> String.trim_trailing(".")

    cond do
      currency = Map.get(currency_strings, canonical_currency) ->
        {:ok, currency}

      digital_token = maybe_token(currency) ->
        {:ok, digital_token}

      true ->
        {:error, unknown_currency_error(currency)}
    end
  end

  defp find_currency(currency_strings, currency, fuzzy)
       when is_float(fuzzy) and fuzzy > 0.0 and fuzzy <= 1.0 do
    canonical_currency = String.downcase(currency)

    {distance, currency_code} =
      currency_strings
      |> Enum.map(fn {k, v} -> {String.jaro_distance(k, canonical_currency), v} end)
      |> Enum.sort(fn {k1, _v1}, {k2, _v2} -> k1 > k2 end)
      |> hd

    if distance >= fuzzy do
      {:ok, currency_code}
    else
      {:error, unknown_currency_error(currency)}
    end
  end

  defp find_currency(_currency_strings, _currency, fuzzy) do
    {:error,
     {
       ArgumentError,
       "option :fuzzy must be a number > 0.0 and <= 1.0. Found #{inspect(fuzzy)}"
     }}
  end

  defp maybe_token(token_id) do
    if Code.ensure_loaded?(DigitalToken) do
      case apply(DigitalToken, :validate_token, [token_id]) do
        {:ok, token_id} -> token_id
        _other -> nil
      end
    else
      nil
    end
  end

  @doc """
  Returns a formatted string representation of a `t:Money.t/0`.

  Formatting is performed according to the rules defined by CLDR. See
  `Localize.Number.to_string/2` for formatting options.  The default is to format
  as a currency which applies the appropriate rounding and fractional digits
  for the currency.

  ### Arguments

  * `money` is any valid `t:Money.t/0` type returned
    by `Money.new/2`.

  * `options` is a keyword list, or a validated options struct accepted by
    `Localize.Number.to_string/2`.

  ### Returns

  * `{:ok, string}` or

  * `{:error, reason}`.

  ### Options

  * `currency_symbol`: Allows overriding a currency symbol. The alternatives
    are:
    * `:iso` the ISO currency code will be used instead of the default
      currency symbol.
    * `:narrow` uses the narrow symbol defined for the locale. The same
      narrow symbol can be defined for more than one currency and therefore this
      should be used with care. If no narrow symbol is defined, the standard
      symbol is used.
    * `:symbol` uses the standard symbol defined in CLDR. A symbol is unique
      for each currency and can be safely used.
    * "string" uses `string` as the currency symbol
    * `:standard` (the default and recommended) uses the CLDR-defined symbol
      based upon the currency format for the locale.
    * `:none` means format the amount without any currency symbol.

  * `:no_fraction_if_integer` is a boolean which, if `true`, will set `:fractional_digits`
    to `0` if the money value is an integer value.

  * Any other options are passed to `Localize.Number.to_string/2`.

  ### Examples

      iex> Money.to_string Money.new(:USD, 1234)
      {:ok, "$1,234.00"}

      iex> Money.to_string Money.new(:USD, 1234), no_fraction_if_integer: true
      {:ok, "$1,234"}

      iex> Money.to_string Money.new(:JPY, 1234)
      {:ok, "¥1,234"}

      iex> Money.to_string Money.new(:THB, 1234)
      {:ok, "THB 1,234.00"}

      iex> Money.to_string Money.new(:THB, 1234, fractional_digits: 4)
      {:ok, "THB 1,234.0000"}

      iex> Money.to_string Money.new(:USD, 1234), format: :long
      {:ok, "1,234 US dollars"}

      iex> Money.to_string(Money.new(:EUR, "100"), locale: "bn")
      {:ok, "১০০.০০€"}

  """
  @spec to_string(Money.t(), Keyword.t() | map()) ::
          {:ok, String.t()} | {:error, {module, String.t()}} | {:error, Exception.t()}

  def to_string(money, options \\ [])

  def to_string(%Money{currency: {:token, _token_id}}, options) when is_list(options) do
    {:error, {Money.FormatError, "Formatting of digital tokens is not current supported"}}
  end

  def to_string(%Money{currency: token_id} = money, options)
      when is_digital_token(token_id) and is_list(options) do
    symbol = digital_token_symbol(token_id)
    formatted = Decimal.to_string(money.amount, :normal)
    {:ok, "#{symbol}#{formatted}"}
  end

  def to_string(%Money{} = money, options) when is_list(options) do
    default_options = [currency: currency_for_format(money.currency)]
    format_options = Map.get(money, :format_options, [])

    options =
      default_options
      |> Keyword.merge(format_options)
      |> Keyword.merge(options)
      |> maybe_no_fractional_digits(money)
      |> translate_format_option()

    Localize.Number.to_string(money.amount, options)
  end

  def to_string(%Money{} = money, %Localize.Number.Format.Options{} = options) do
    format_options = Map.get(money, :format_options, [])

    options =
      format_options
      |> Map.new()
      |> Map.merge(options)
      |> Map.put(:currency, currency_for_format(money.currency))
      |> maybe_no_fractional_digits(money)

    Localize.Number.to_string(money.amount, options)
  end

  # Custom and private currencies are registered at runtime in
  # `Money.Currency.Store` and are unknown to `Localize.Currency`. When
  # formatting one, pass the `Localize.Currency` struct directly so the
  # number formatter uses it as-is rather than trying (and failing) to
  # resolve the code through `Localize.Currency`. ISO 4217 codes are left
  # as atoms so the formatter performs its normal locale-aware resolution.
  defp currency_for_format(currency) when is_atom(currency) and not is_nil(currency) do
    case Money.Currency.Store.get(currency) do
      %Localize.Currency{} = custom_currency -> custom_currency
      nil -> currency
    end
  end

  defp currency_for_format(currency) do
    currency
  end

  defp maybe_no_fractional_digits(options, money) do
    if integer?(money) && options[:no_fraction_if_integer] do
      put_option(options, :fractional_digits, 0)
    else
      options
    end
  end

  defp put_option(%{} = options, option, value), do: Map.put(options, option, value)
  defp put_option(options, option, value), do: Keyword.put(options, option, value)

  defp translate_format_option(options) when is_list(options) do
    case Keyword.get(options, :format) do
      :long -> Keyword.put(options, :format, :currency_long)
      _ -> options
    end
  end

  defp digital_token_symbol(token_id) when is_binary(token_id) do
    if Code.ensure_loaded?(DigitalToken) do
      symbols = apply(DigitalToken, :symbols, [])

      case Map.get(symbols, token_id) do
        nil ->
          case apply(DigitalToken, :short_name, [token_id]) do
            {:ok, name} -> name
            _ -> token_id
          end

        symbol ->
          symbol
      end
    else
      token_id
    end
  end

  defp normalize_currency_code(code) when is_atom(code) do
    code |> Atom.to_string() |> String.upcase() |> String.to_atom()
  end

  defp normalize_currency_code(code) when is_binary(code), do: String.upcase(code)
  defp normalize_currency_code(code), do: code

  defp normalize_filter([:all]), do: :all
  defp normalize_filter([filter]) when is_atom(filter), do: filter
  defp normalize_filter([]), do: nil
  defp normalize_filter(filter), do: filter

  @doc """
  Returns a formatted string representation of a `t:Money.t/0` or raises if
  there is an error.

  Formatting is performed according to the rules defined by CLDR. See
  `Localize.Number.to_string/2` for formatting options.  The default is to format
  as a currency which applies the appropriate rounding and fractional digits
  for the currency.

  ### Arguments

  * `money` is any valid `t:Money.t/0` type returned
    by `Money.new/2`.

  * `options` is a keyword list, or a validated options struct accepted by
    `Localize.Number.to_string/2`.

  ### Options

  * Any other options are passed to `Localize.Number.to_string/2`.

  ### Examples

      iex> Money.to_string! Money.new(:USD, 1234)
      "$1,234.00"

      iex> Money.to_string! Money.new(:JPY, 1234)
      "¥1,234"

      iex> Money.to_string! Money.new(:THB, 1234)
      "THB 1,234.00"

      iex> Money.to_string! Money.new(:USD, 1234), format: :long
      "1,234 US dollars"

  """
  @spec to_string!(Money.t(), Keyword.t() | map()) ::
          String.t() | no_return()

  def to_string!(%Money{} = money, options \\ []) do
    case to_string(money, options) do
      {:ok, string} -> string
      {:error, %{__exception__: true} = exception} -> raise exception
      {:error, {exception, reason}} -> raise exception, reason
    end
  end

  @doc """
  Returns the amount part of a `Money` type as a `Decimal`.

  ### Arguments

  * `money` is any valid `t:Money.t/0` type returned
    by `Money.new/2`.

  ### Returns

  * a `Decimal.t`.

  ## Example

      iex> m = Money.new("USD", 100)
      iex> Money.to_decimal(m)
      Decimal.new(100)

  """
  @spec to_decimal(money :: Money.t()) :: Decimal.t()
  def to_decimal(%Money{amount: amount}) do
    amount
  end

  @doc """
  Returns the currecny code of a `Money` type
  as an `atom`.

  ### Arguments

  * `money` is any valid `t:Money.t/0` type returned
    by `Money.new/2`.

  ### Returns

  * the currency code as an `t:atom`.

  ## Example

      iex> m = Money.new("USD", 100)
      iex> Money.to_currency_code(m)
      :USD

  """
  @doc since: "5.6.0"
  @spec to_currency_code(money :: Money.t()) :: atom()
  def to_currency_code(%Money{currency: currency_code}) do
    currency_code
  end

  @doc """
  The absolute value of a `t:Money.t/0` amount.
  Returns a `t:Money.t/0` type with a positive sign for the amount.

  ### Arguments

  * `money` is any valid `t:Money.t/0` type returned
    by `Money.new/2`.

  ### Returns

  * a `t:Money.t/0`.

  ## Example

      iex> m = Money.new("USD", -100)
      iex> Money.abs(m)
      Money.new(:USD, "100")

  """
  @spec abs(money :: Money.t()) :: Money.t()
  def abs(%Money{amount: amount} = money) do
    %{money | amount: Decimal.abs(amount)}
  end

  @doc """
  Add two `Money` values.

  ### Arguments

  * `money_1` and `money_2` are any valid `t:Money.t/0` types returned
    by `Money.new/2`.

  ### Returns

  * `{:ok, money}` or

  * `{:error, reason}`.

  ## Example

      iex> Money.add Money.new(:USD, 200), Money.new(:USD, 100)
      {:ok, Money.new(:USD, 300)}

      iex> Money.add Money.new(:USD, 200), Money.new(:AUD, 100)
      {:error, {ArgumentError, "Cannot add monies with different currencies. " <>
        "Received :USD and :AUD."}}

  """
  @spec add(money_1 :: Money.t(), money_2 :: Money.t()) ::
          {:ok, Money.t()} | {:error, {module(), String.t()}}

  def add(
        %Money{currency: same_currency, amount: amount_a},
        %Money{currency: same_currency, amount: amount_b} = money_b
      ) do
    {:ok, %{money_b | amount: Decimal.add(amount_a, amount_b)}}
  end

  def add(%Money{currency: code_a}, %Money{currency: code_b}) do
    {
      :error,
      {
        ArgumentError,
        "Cannot add monies with different currencies. " <>
          "Received #{inspect(code_a)} and #{inspect(code_b)}."
      }
    }
  end

  @doc """
  Add two `t:Money.t/0` values or raise on error.

  ### Arguments

  * `money_1` and `money_2` are any valid `t:Money.t/0` types returned
    by `Money.new/2`.

  ### Returns

  * a `t:Money.t/0` struct or

  * raises an exception

  ### Examples

      iex> Money.add! Money.new(:USD, 200), Money.new(:USD, 100)
      Money.new(:USD, "300")

      Money.add! Money.new(:USD, 200), Money.new(:CAD, 500)
      ** (ArgumentError) Cannot add two %Money{} with different currencies. Received :USD and :CAD.

  """
  @spec add!(money_1 :: Money.t(), money_2 :: Money.t()) :: t() | no_return()

  def add!(%Money{} = money_1, %Money{} = money_2) do
    case add(money_1, money_2) do
      {:ok, result} -> result
      {:error, {exception, message}} -> raise exception, message
    end
  end

  @doc """
  Subtract one `t:Money.t/0` value struct from another.

  ### Options

  * `money_1` and `money_2` are any valid `t:Money.t/0` types returned
    by `Money.new/2`.

  ### Returns

  * `{:ok, money}` or

  * `{:error, reason}`.

  ## Example

      iex> Money.sub Money.new(:USD, 200), Money.new(:USD, 100)
      {:ok, Money.new(:USD, 100)}

  """
  @spec sub(money_1 :: Money.t(), money_2 :: Money.t()) ::
          {:ok, Money.t()} | {:error, {module(), String.t()}}

  def sub(
        %Money{currency: same_currency, amount: amount_a},
        %Money{currency: same_currency, amount: amount_b} = money_b
      ) do
    {:ok, %{money_b | amount: Decimal.sub(amount_a, amount_b)}}
  end

  def sub(%Money{currency: code_a}, %Money{currency: code_b}) do
    {:error,
     {ArgumentError,
      "Cannot subtract two monies with different currencies. " <>
        "Received #{inspect(code_a)} and #{inspect(code_b)}."}}
  end

  @doc """
  Subtract one `Money` value struct from another and raise on error.

  Returns either `{:ok, money}` or `{:error, reason}`.

  ### Arguments

  * `money_1` and `money_2` are any valid `t:Money.t/0` types returned
    by `Money.new/2`.

  ### Returns

  * a `t:Money.t/0` struct or

  * raises an exception.

  ### Examples

      iex> Money.sub! Money.new(:USD, 200), Money.new(:USD, 100)
      Money.new(:USD, "100")

      Money.sub! Money.new(:USD, 200), Money.new(:CAD, 500)
      ** (ArgumentError) Cannot subtract monies with different currencies. Received :USD and :CAD.

  """
  @spec sub!(money_1 :: Money.t(), money_2 :: Money.t()) :: Money.t() | none()

  def sub!(%Money{} = a, %Money{} = b) do
    case sub(a, b) do
      {:ok, result} -> result
      {:error, {exception, message}} -> raise exception, message
    end
  end

  @doc """
  Multiply a `Money` value by a number.

  ### Arguments

  * `money` is any valid `t:Money.t/0` type returned
    by `Money.new/2`.

  * `number` is an integer, float or `t:Decimal.t/0`.

  > Note that multipling one `t:Money.t/0` by another is not supported.

  ### Returns

  * `{:ok, money}` or

  * `{:error, reason}`

  ## Example

      iex> Money.mult(Money.new(:USD, 200), 2)
      {:ok, Money.new(:USD, 400)}

      iex> Money.mult(Money.new(:USD, 200), "xx")
      {:error, {ArgumentError, "Cannot multiply money by \\"xx\\""}}

  """
  @spec mult(Money.t(), Localize.Utils.Math.number_or_decimal()) ::
          {:ok, Money.t()} | {:error, {module(), String.t()}}

  def mult(%Money{amount: amount} = money, number) when is_integer(number) do
    {:ok, %{money | amount: Decimal.mult(amount, Decimal.new(number))}}
  end

  def mult(%Money{amount: amount} = money, number) when is_float(number) do
    {:ok, %{money | amount: Decimal.mult(amount, Decimal.from_float(number))}}
  end

  def mult(%Money{amount: amount} = money, %Decimal{} = number) do
    {:ok, %{money | amount: Decimal.mult(amount, number)}}
  end

  def mult(%Money{}, other) do
    {:error, {ArgumentError, "Cannot multiply money by #{inspect(other)}"}}
  end

  @doc """
  Multiply a `Money` value by a number and raise on error.

  ### Arguments

  * `money` is any valid `t:Money.t/0` type returned
    by `Money.new/2`.

  * `number` is an integer, float or `t:Decimal.t/0`.

  ### Returns

  * a `t:Money.t/0` or

  * raises an exception

  ### Examples

      iex> Money.mult!(Money.new(:USD, 200), 2)
      Money.new(:USD, "400")

      Money.mult!(Money.new(:USD, 200), :invalid)
      ** (ArgumentError) Cannot multiply money by :invalid

  """
  @spec mult!(Money.t(), Localize.Utils.Math.number_or_decimal()) :: Money.t() | none()

  def mult!(%Money{} = money, number) do
    case mult(money, number) do
      {:ok, result} -> result
      {:error, {exception, message}} -> raise exception, message
    end
  end

  @doc """
  Divide a `Money` value by a number.

  ### Arguments

  * `money` is any valid `t:Money.t/0` types returned
    by `Money.new/2`

  * `number` is an integer, float or `Decimal.t`

  > Note that dividing one %Money{} by another is not supported.

  ### Returns

  * `{:ok, money}` or

  * `{:error, reason}`

  ## Example

      iex> Money.div Money.new(:USD, 200), 2
      {:ok, Money.new(:USD, 100)}

      iex> Money.div(Money.new(:USD, 200), "xx")
      {:error, {ArgumentError, "Cannot divide money by \\"xx\\""}}

  """
  @spec div(Money.t(), Localize.Utils.Math.number_or_decimal()) ::
          {:ok, Money.t()} | {:error, {module(), String.t()}}

  def div(%Money{amount: amount} = money, number) when is_integer(number) do
    {:ok, %{money | amount: Decimal.div(amount, Decimal.new(number))}}
  end

  def div(%Money{amount: amount} = money, number) when is_float(number) do
    {:ok, %{money | amount: Decimal.div(amount, Decimal.from_float(number))}}
  end

  def div(%Money{amount: amount} = money, %Decimal{} = number) do
    {:ok, %{money | amount: Decimal.div(amount, number)}}
  end

  def div(%Money{}, other) do
    {:error, {ArgumentError, "Cannot divide money by #{inspect(other)}"}}
  end

  @doc """
  Divide a `Money` value by a number and raise on error.

  ### Arguments

  * `money` is any valid `t:Money.t/0` types returned
    by `Money.new/2`

  * `number` is an integer, float or `Decimal.t`

  ### Returns

  * a `t:Money.t/0` struct or

  * raises an exception

  ### Examples

      iex> Money.div!(Money.new(:USD, 200), 2)
      Money.new(:USD, "100")

      iex> Money.div!(Money.new(:USD, 200), "xx")
      ** (ArgumentError) Cannot divide money by "xx"

  """
  @spec div!(Money.t(), Localize.Utils.Math.number_or_decimal()) :: Money.t() | none()

  def div!(%Money{} = money, number) do
    case Money.div(money, number) do
      {:ok, result} -> result
      {:error, {exception, message}} -> raise exception, message
    end
  end

  @doc """
  Return the minimum of two `t:Money.t/0` amounts.

  ### Arguments

  * `money_1` and `money_2` are any valid `t:Money.t/0` types returned
    by `Money.new/2`. `money_1` and `money_2` should be of the same
    currency.

  ### Returns

  * `{:ok, minimum_money}` or

  * `{:error, reason}`

  ## Example

      iex> Money.min(Money.new(:USD, 200), Money.new(:USD, 300))
      {:ok, Money.new(:USD, 200)}

      iex> Money.min(Money.new(:USD, 200), Money.new(:AUD, 200))
      {:error,
        {ArgumentError, "Cannot compare monies with different currencies. Received :USD and :AUD."}}

  """
  @doc since: "5.18.0"

  @spec min(money_1 :: Money.t(), money_2 :: Money.t()) ::
          {:ok, Money.t()} | {:error, {module(), String.t()}}

  def min(%Money{currency: same_currency} = money_1, %Money{currency: same_currency} = money_2) do
    case compare(money_1, money_2) do
      :gt -> {:ok, money_2}
      :eq -> {:ok, money_2}
      :lt -> {:ok, money_1}
      {:error, reason} -> {:error, reason}
    end
  end

  def min(%Money{currency: code_a}, %Money{currency: code_b}) do
    {:error, compare_error(code_a, code_b)}
  end

  @doc """
  Return the maximum of two `t:Money.t/0` amounts.

  ### Arguments

  * `money_1` and `money_2` are any valid `t:Money.t/0` types returned
    by `Money.new/2`. `money_1` and `money_2` should be of the same
    currency.

  ### Returns

  * `{:ok, maximum_money}` or

  * `{:error, reason}`.

  ## Example

      iex> Money.max(Money.new(:USD, 200), Money.new(:USD, 300))
      {:ok, Money.new(:USD, 300)}

      iex> Money.max(Money.new(:USD, 200), Money.new(:AUD, 200))
      {:error,
        {ArgumentError, "Cannot compare monies with different currencies. Received :USD and :AUD."}}

  """
  @doc since: "5.18.0"

  @spec max(money_1 :: Money.t(), money_2 :: Money.t()) ::
          {:ok, Money.t()} | {:error, {module(), String.t()}}

  def max(%Money{currency: same_currency} = money_1, %Money{currency: same_currency} = money_2) do
    case compare(money_1, money_2) do
      :lt -> {:ok, money_2}
      :eq -> {:ok, money_2}
      :gt -> {:ok, money_1}
      {:error, reason} -> {:error, reason}
    end
  end

  def max(%Money{currency: code_a}, %Money{currency: code_b}) do
    {:error, compare_error(code_a, code_b)}
  end

  @doc """
  Return the minimum of two `t:Money.t/0` amounts or
  raises an exception.

  ### Arguments

  * `money_1` and `money_2` are any valid `t:Money.t/0` types returned
    by `Money.new/2`. `money_1` and `money_2` should be of the same
    currency.

  ### Returns

  * `minimum_money` or

  * raises an exception.

  ## Example

      iex> Money.min!(Money.new(:USD, 200), Money.new(:USD, 300))
      Money.new(:USD, 200)

      iex> Money.min!(Money.new(:USD, 200), Money.new(:AUD, 200))
      ** (ArgumentError) Cannot compare monies with different currencies. Received :USD and :AUD.

  """
  @doc since: "5.18.0"

  @spec min!(money_1 :: Money.t(), money_2 :: Money.t()) ::
          Money.t() | no_return()

  def min!(%Money{currency: same_currency} = money_1, %Money{currency: same_currency} = money_2) do
    case compare(money_1, money_2) do
      :gt -> money_2
      :eq -> money_2
      :lt -> money_1
      {:error, {exception, reason}} -> raise exception, reason
    end
  end

  def min!(%Money{currency: code_a}, %Money{currency: code_b}) do
    {exception, reason} = compare_error(code_a, code_b)
    raise exception, reason
  end

  @doc """
  Return the maximum of two `t:Money.t/0` amounts or
  raises an exception.

  ### Arguments

  * `money_1` and `money_2` are any valid `t:Money.t/0` types returned
    by `Money.new/2`. `money_1` and `money_2` should be of the same
    currency.

  ### Returns

  * `maximum_money` or

  * raises an exception.

  ## Example

      iex> Money.max!(Money.new(:USD, 200), Money.new(:USD, 300))
      Money.new(:USD, 300)

      iex> Money.max!(Money.new(:USD, 200), Money.new(:AUD, 200))
      ** (ArgumentError) Cannot compare monies with different currencies. Received :USD and :AUD.

  """
  @doc since: "5.18.0"

  @spec max!(money_1 :: Money.t(), money_2 :: Money.t()) ::
          Money.t() | no_return()

  def max!(%Money{currency: same_currency} = money_1, %Money{currency: same_currency} = money_2) do
    case compare(money_1, money_2) do
      :lt -> money_2
      :eq -> money_2
      :gt -> money_1
      {:error, {exception, reason}} -> raise exception, reason
    end
  end

  def max!(%Money{currency: code_a}, %Money{currency: code_b}) do
    {exception, reason} = compare_error(code_a, code_b)
    raise exception, reason
  end

  @doc """
  Clamps a `t:Money.t/0` to be in the range of `minimum`
  to `maximum`.

  #### Arguments

  * `money`, `minimum` and `maximum` are any valid `t:Money.t/0` types returned
    by `Money.new/2`. They should be of the same currency.

  #### Returns

  * `{:ok, money]` where `money` is clamped to the `minimum` or `maximum` if required.
      * If `money` is within the range `minimum..maximum` then `money` is returned unchanged.
      * If `money` is less than `minimum` then `minimum` is returned.
      * If `money` is greater than `maximum` then `maximum` is returned.

  * or `{:error, reason}`.

  #### Examples

      iex> Money.clamp(Money.new(:USD, 100), Money.new(:USD, 50), Money.new(:USD, 200))
      {:ok, Money.new(:USD, 100)}

      iex> Money.clamp(Money.new(:USD, 300), Money.new(:USD, 50), Money.new(:USD, 200))
      {:ok, Money.new(:USD, 200)}

      iex> Money.clamp(Money.new(:USD, 10), Money.new(:USD, 50), Money.new(:USD, 200))
      {:ok, Money.new(:USD, 50)}

      iex> Money.clamp(Money.new(:USD, 10), Money.new(:USD, 300), Money.new(:USD, 200))
      {:error,
        {ArgumentError,
          "Minimum must be less than maximum. Found Money.new(:USD, \\"300\\") and Money.new(:USD, \\"200\\")"}}

      iex> Money.clamp(Money.new(:USD, 10), Money.new(:AUD, 300), Money.new(:EUR, 200))
      {:error, {ArgumentError, "Cannot compare monies with different currencies. Received :USD, :AUD and :EUR"}}

  """
  @doc since: "5.18.0"

  @spec clamp(money :: Money.t(), minimum :: Money.t(), maximum :: Money.t()) ::
          {:ok, Money.t()} | {:error, {module(), String.t()}}

  def clamp(
        %__MODULE__{currency: same_currency} = money,
        %__MODULE__{currency: same_currency} = minimum,
        %__MODULE__{currency: same_currency} = maximum
      ) do
    if compare(minimum, maximum) == :lt do
      Money.max(minimum, Money.min!(maximum, money))
    else
      {:error,
       {ArgumentError,
        "Minimum must be less than maximum. Found #{inspect(minimum)} and #{inspect(maximum)}"}}
    end
  end

  def clamp(%Money{currency: code_a}, %Money{currency: code_b}, %Money{currency: code_c}) do
    {:error, compare_error(code_a, code_b, code_c)}
  end

  @doc """
  Clamps a `t:Money.t/0` to be in the range of `minimum`
  to `maximum` or raises an exception.

  #### Arguments

  * `money`, `minimum` and `maximum` are any valid `t:Money.t/0` types returned
    by `Money.new/2`. They should be of the same currency.

  #### Returns

  * `money` where `money` is clamped to the `minimum` or `maximum` if required.
      * If `money` is within the range `minimum..maximum` then `money` is returned unchanged.
      * If `money` is less than `minimum` then `minimum` is returned.
      * If `money` is greater than `maximum` then `maximum` is returned.

  * or `{:error, reason}`.

  #### Examples

      iex> Money.clamp!(Money.new(:USD, 100), Money.new(:USD, 50), Money.new(:USD, 200))
      Money.new(:USD, 100)

      iex> Money.clamp!(Money.new(:USD, 300), Money.new(:USD, 50), Money.new(:USD, 200))
      Money.new(:USD, 200)

      iex> Money.clamp!(Money.new(:USD, 10), Money.new(:USD, 50), Money.new(:USD, 200))
      Money.new(:USD, 50)

      iex> Money.clamp!(Money.new(:USD, 10), Money.new(:USD, 300), Money.new(:USD, 200))
      ** (ArgumentError) Minimum must be less than maximum. Found Money.new(:USD, "300") and Money.new(:USD, "200")

      iex> Money.clamp!(Money.new(:USD, 10), Money.new(:AUD, 300), Money.new(:EUR, 200))
      ** (ArgumentError) Cannot compare monies with different currencies. Received :USD, :AUD and :EUR

  """
  @doc since: "5.18.0"

  @spec clamp!(money :: Money.t(), minimum :: Money.t(), maximum :: Money.t()) ::
          Money.t() | no_return()

  def clamp!(
        %__MODULE__{currency: same_currency} = money,
        %__MODULE__{currency: same_currency} = minimum,
        %__MODULE__{currency: same_currency} = maximum
      ) do
    if compare(minimum, maximum) == :lt do
      Money.max!(minimum, Money.min!(maximum, money))
    else
      raise ArgumentError,
            "Minimum must be less than maximum. Found #{inspect(minimum)} and #{inspect(maximum)}"
    end
  end

  def clamp!(%Money{currency: code_a}, %Money{currency: code_b}, %Money{currency: code_c}) do
    {exception, reason} = compare_error(code_a, code_b, code_c)
    raise exception, reason
  end

  @doc """
  Returns a boolean indicating if the `t:Money.t/0` is in the
  range `minimum..maximum`.

  #### Arguments

  * `money`, `minimum` and `maximum` are any valid `t:Money.t/0` types returned
    by `Money.new/2`. They should be of the same currency.

  #### Returns

  * `true` or `false`.

  #### Examples

      iex> Money.within?(Money.new(:USD, 100), Money.new(:USD, 50), Money.new(:USD, 200))
      true

      iex> Money.within?(Money.new(:USD, 10), Money.new(:USD, 50), Money.new(:USD, 200))
      false

      iex> Money.within?(Money.new(:USD, 10), Money.new(:USD, 50), Money.new(:USD, 50))
      false

      iex> Money.within?(Money.new(:USD, 50), Money.new(:USD, 50), Money.new(:USD, 50))
      true

      iex> Money.within?(Money.new(:USD, 100), Money.new(:USD, 300), Money.new(:USD, 200))
      ** (ArgumentError) Minimum must be less than maximum. Found Money.new(:USD, "300") and Money.new(:USD, "200")

      iex> Money.within?(Money.new(:USD, 10), Money.new(:AUD, 300), Money.new(:EUR, 200))
      ** (ArgumentError) Cannot compare monies with different currencies. Received :USD, :AUD and :EUR

  """
  @doc since: "5.18.0"

  @spec within?(money :: Money.t(), minimum :: Money.t(), maximum :: Money.t()) :: boolean()

  def within?(
        %__MODULE__{currency: same_currency} = money,
        %__MODULE__{currency: same_currency} = minimum,
        %__MODULE__{currency: same_currency} = maximum
      ) do
    if compare(minimum, maximum) in [:lt, :eq] do
      compare(money, minimum) in [:gt, :eq] && compare(money, maximum) in [:lt, :eq]
    else
      raise ArgumentError,
            "Minimum must be less than maximum. Found #{inspect(minimum)} and #{inspect(maximum)}"
    end
  end

  def within?(%Money{currency: code_a}, %Money{currency: code_b}, %Money{currency: code_c}) do
    {exception, reason} = compare_error(code_a, code_b, code_c)
    raise exception, reason
  end

  @doc """
  Negate a `t:Money.t/0` value.

  ### Argument

  * `money_1` is any valid `t:Money.t/0` type.

  #### Returns

  * `{:ok, negated_money}` with the amount negated.

  ### Example

      iex> Money.negate(Money.new(:USD, 200))
      {:ok, Money.new(:USD, -200)}

      iex> Money.negate(Money.new(:USD, -200))
      {:ok, Money.new(:USD, 200)}

  """
  @doc since: "5.18.0"

  @spec negate(money :: Money.t()) :: {:ok, Money.t()}

  def negate(%__MODULE__{amount: amount} = money) do
    {:ok, Map.put(money, :amount, Decimal.negate(amount))}
  end

  @doc """
  Negate a `t:Money.t/0` value or raises an
  exception.

  ### Argument

  * `money_1` is any valid `t:Money.t/0` type.

  #### Returns

  * `negated_money` with the amount negated or

  * raises an exception.

  ### Example

      iex> Money.negate!(Money.new(:USD, 200))
      Money.new(:USD, -200)

      iex> Money.negate!(Money.new(:USD, -200))
      Money.new(:USD, 200)

  """
  @doc since: "5.18.0"

  @spec negate!(money :: Money.t()) :: Money.t() | no_return()

  def negate!(%__MODULE__{amount: amount} = money) do
    Map.put(money, :amount, Decimal.negate(amount))
  end

  @doc """
  Returns a boolean indicating if two `Money` values are equal

  ### Arguments

  * `money_1` and `money_2` are any valid `t:Money.t/0` types returned
    by `Money.new/2`

  ### Returns

  * `true` or `false`

  ## Example

      iex> Money.equal?(Money.new(:USD, 200), Money.new(:USD, 200))
      true

      iex> Money.equal?(Money.new(:USD, 200), Money.new(:USD, 100))
      false

  """
  @spec equal?(money_1 :: Money.t(), money_2 :: Money.t()) :: boolean

  def equal?(%Money{currency: same_currency, amount: amount_a}, %Money{
        currency: same_currency,
        amount: amount_b
      }) do
    Decimal.equal?(amount_a, amount_b)
  end

  def equal?(_, _) do
    false
  end

  @doc """
  Sum a list of monies that may be in different
  currencies.

  ### Arguments

  * `money_list` is a list of any valid `t:Money.t/0` types returned
    by `Money.new/2`.

  * `rates` is a map of exchange rates. The default is the rates
    returned by `Money.ExchangeRates.latest_rates/0`. If the
    exchange rates retriever is not running, then the default is
    `%{}`.

  ### Returns

  * `{:ok, money}` where `money` is a `t:Money.t/0` representing the
    sum of the maybe converted money amounts. The currency of the sum is
    the currency of the first `Money` in the `money_list`.

  * `{:error, {exception, reason}}` describing an error.

  ### Examples

      iex> Money.sum([Money.new(:USD, 100), Money.new(:USD, 200), Money.new(:USD, 50)])
      {:ok, Money.new(:USD, 350)}

      iex> Money.sum([Money.new(:USD, 100), Money.new(:USD, 200), Money.new(:AUD, 50)], %{})
      {:error,
       {Money.ExchangeRateError, "No exchange rate is available for currency :AUD"}}

      iex> rates = %{AUD: Decimal.new(2), USD: Decimal.new(1)}
      iex> Money.sum [Money.new(:USD, 100), Money.new(:USD, 200), Money.new(:AUD, 50)], rates
      {:ok, Money.new(:USD, "325.0")}

  """
  @doc since: "5.3.0"
  @spec sum(
          [t(), ...],
          ExchangeRates.t() | {:ok, ExchangeRates.t()} | {:error, {module(), String.t()}}
        ) ::
          {:ok, t()} | {:error, {module(), String.t()}}

  def sum(money_list, rates \\ latest_rates_or_empty_map())

  def sum(money_list, {:ok, rates}) when is_map(rates) do
    sum(money_list, rates)
  end

  def sum(_money_list, {:error, reason}) do
    {:error, reason}
  end

  def sum([%Money{} = first | rest] = money_list, %{} = rates) when is_list(money_list) do
    %Money{currency: target_currency} = first

    Enum.reduce_while(rest, {:ok, first}, fn money, {:ok, acc} ->
      case to_currency(money, target_currency, rates) do
        {:ok, increment} -> {:cont, Money.add(acc, increment)}
        error -> {:halt, error}
      end
    end)
  end

  @doc """
  Sum a list of monies that may be in different
  currencies or raise an exception on error.

  ### Arguments

  * `money_list` is a list of any valid `t:Money.t/0` types returned
    by `Money.new/2`.

  * `rates` is a map of exchange rates. The default is the rates
    returned by `Money.ExchangeRates.latest_rates/0`. If the
    exchange rates retriever is not running, then the default is
    `%{}`.

  ### Returns

  * A `t:Money.t/0`  representing the sum of the maybe
    converted money amounts. The currency of the sum is
    the currency of the first `Money` in the `money_list`.

  * raises an exception.

  ### Examples

      iex> Money.sum!([Money.new(:USD, 100), Money.new(:USD, 200), Money.new(:USD, 50)])
      Money.new(:USD, 350)

      iex> Money.sum!([Money.new(:USD, 100), Money.new(:USD, 200), Money.new(:AUD, 50)], %{})
      ** (Money.ExchangeRateError) No exchange rate is available for currency :AUD

      iex> rates = %{AUD: Decimal.new(2), USD: Decimal.new(1)}
      iex> Money.sum! [Money.new(:USD, 100), Money.new(:USD, 200), Money.new(:AUD, 50)], rates
      Money.new(:USD, "325.0")

  """
  @spec sum!(
          [t(), ...],
          ExchangeRates.t() | {:ok, ExchangeRates.t()} | {:error, {module(), String.t()}}
        ) ::
          t() | no_return()

  def sum!(money_list, rates \\ latest_rates_or_empty_map()) do
    case sum(money_list, rates) do
      {:ok, result} -> result
      {:error, {exception, message}} -> raise exception, message
    end
  end

  defp latest_rates_or_empty_map do
    case Money.ExchangeRates.latest_rates() do
      {:error, _} -> %{}
      {:ok, map} when is_map(map) -> map
    end
  end

  @doc """
  Compares two `Money` values numerically. If the first number is greater
  than the second :gt is returned, if less than :lt is returned, if both
  numbers are equal :eq is returned.

  ### Arguments

  * `money_1` and `money_2` are any valid `t:Money.t/0` types returned
    by `Money.new/2`

  ### Returns

  *  `:gt` | `:eq` | `:lt` or

  * `{:error, {module(), String.t}}`

  ### Examples

      iex> Money.compare(Money.new(:USD, 200), Money.new(:USD, 100))
      :gt

      iex> Money.compare(Money.new(:USD, 200), Money.new(:USD, 200))
      :eq

      iex> Money.compare(Money.new(:USD, 200), Money.new(:USD, 500))
      :lt

      iex> Money.compare(Money.new(:USD, 200), Money.new(:CAD, 500))
      {:error,
       {ArgumentError,
        "Cannot compare monies with different currencies. Received :USD and :CAD."}}

  """
  @spec compare(money_1 :: Money.t(), money_2 :: Money.t()) ::
          :gt | :eq | :lt | {:error, {module(), String.t()}}

  def compare(%Money{currency: same_currency, amount: amount_a}, %Money{
        currency: same_currency,
        amount: amount_b
      }) do
    Decimal.compare(amount_a, amount_b)
  end

  def compare(%Money{currency: code_a}, %Money{currency: code_b}) do
    {:error, compare_error(code_a, code_b)}
  end

  defp compare_error(code_a, code_b) do
    {ArgumentError,
     "Cannot compare monies with different currencies. " <>
       "Received #{inspect(code_a)} and #{inspect(code_b)}."}
  end

  defp compare_error(code_a, code_b, code_c) do
    {ArgumentError,
     "Cannot compare monies with different currencies. " <>
       "Received #{inspect(code_a)}, #{inspect(code_b)} and #{inspect(code_c)}"}
  end

  @doc """
  Compares two `Money` values numerically and raises on error.

  ### Arguments

  * `money_1` and `money_2` are any valid `t:Money.t/0` types returned
    by `Money.new/2`.

  ### Returns

  *  `:gt` | `:eq` | `:lt` or

  * raises an exception

  ### Examples

      Money.compare! Money.new(:USD, 200), Money.new(:CAD, 500)
      ** (ArgumentError) Cannot compare monies with different currencies. Received :USD and :CAD.

  """
  def compare!(%Money{} = money_1, %Money{} = money_2) do
    case compare(money_1, money_2) do
      {:error, {exception, reason}} -> raise exception, reason
      result -> result
    end
  end

  @doc """
  Compares two `Money` values numerically. If the first number is greater
  than the second #Integer<1> is returned, if less than Integer<-1> is
  returned. Otherwise, if both numbers are equal Integer<0> is returned.

  ### Arguments

  * `money_1` and `money_2` are any valid `t:Money.t/0` types returned
    by `Money.new/2`.

  ### Returns

  *  `-1` | `0` | `1` or

  * `{:error, {module(), String.t}}`

  ### Examples

      iex> Money.cmp Money.new(:USD, 200), Money.new(:USD, 100)
      1

      iex> Money.cmp Money.new(:USD, 200), Money.new(:USD, 200)
      0

      iex> Money.cmp Money.new(:USD, 200), Money.new(:USD, 500)
      -1

      iex> Money.cmp Money.new(:USD, 200), Money.new(:CAD, 500)
      {:error,
       {ArgumentError,
        "Cannot compare monies with different currencies. Received :USD and :CAD."}}

  """
  @spec cmp(money_1 :: Money.t(), money_2 :: Money.t()) ::
          -1 | 0 | 1 | {:error, {module(), String.t()}}
  def cmp(%Money{currency: same_currency} = money_1, %Money{currency: same_currency} = money_2) do
    case compare(money_1, money_2) do
      :lt -> -1
      :eq -> 0
      :gt -> 1
    end
  end

  def cmp(%Money{currency: code_a}, %Money{currency: code_b}) do
    {:error,
     {ArgumentError,
      "Cannot compare monies with different currencies. " <>
        "Received #{inspect(code_a)} and #{inspect(code_b)}."}}
  end

  @doc """
  Compares two `Money` values numerically and raises on error.

  ### Arguments

  * `money_1` and `money_2` are any valid `t:Money.t/0` types returned
    by `Money.new/2`

  ### Returns

  *  `-1` | `0` | `1` or

  * raises an exception

  ### Examples

      Money.cmp! Money.new(:USD, 200), Money.new(:CAD, 500)
      ** (ArgumentError) Cannot compare monies with different currencies. Received :USD and :CAD.

  """
  def cmp!(%Money{} = money_1, %Money{} = money_2) do
    case cmp(money_1, money_2) do
      {:error, {exception, reason}} -> raise exception, reason
      result -> result
    end
  end

  @doc """
  Split a `Money` value into a number of parts maintaining the currency's
  precision and rounding and ensuring that the parts sum to the original
  amount.

  ### Arguments

  * `money` is any `t:Money.t/0`.

  * `parts` is an integer number of parts into which the
    `money` is split.

  * `options` is a keyword list of options.

  ### Options

  * See `Money.round/2`; any options are passed to
    this function.

  ### Returns

  * `{split_amount, remainder}` where `split_amount` is the amount
    money allocated by the split and `remainder` is the amount
    left over that could not be allocated evenly.

  ### Notes

  Returns a tuple `{dividend, remainder}` as the function result
  derived as follows:

  1. Divide the money by the integer divisor.

  2. Round the result of the division to the precision of the currency
    using `Money.round/2`. If the rounding mode results in a
    negative remainder, the rounding is done again using rounding mode
    `:down`.

  3. Return two numbers: the result of the division and any remainder
    that could not be applied given the precision of the currency.

  ### Examples

      iex> Money.split(Money.new("123.5", :JPY), 3)
      {Money.new(:JPY, "41"), Money.new(:JPY, "0.5")}

      iex> Money.split(Money.new("123.4", :JPY), 3)
      {Money.new(:JPY, "41"), Money.new(:JPY, "0.4")}

      iex> Money.split(Money.new("123.7", :USD), 9)
      {Money.new(:USD, "13.74"), Money.new(:USD, "0.04")}

      iex> Money.split(Money.new(:USD, 200), 3)
      {Money.new(:USD, "66.66"), Money.new(:USD, "0.02")}

  """
  @spec split(money :: Money.t(), parts :: non_neg_integer, options :: Keyword.t()) ::
          {Money.t(), Money.t()}

  def split(%Money{} = money, parts, options \\ []) when is_integer(parts) do
    {split, remainder} = split_with_rounding(money, parts, options)

    if compare(remainder, zero(money)) == :lt do
      options = Keyword.put(options, :rounding_mode, :down)
      split_with_rounding(money, parts, options)
    else
      {split, remainder}
    end
  end

  defp split_with_rounding(money, parts, options) do
    div =
      money
      |> Money.div!(parts)
      |> round(options)

    remainder = sub!(money, mult!(div, parts))

    {div, remainder}
  end

  @doc """
  Proportionally spreads a given amount across the given portions with no remainder.

  ## Arguments

    * `amount` is any `t:Money.t/0`.

    * `portions` may be a list of `t:Money.t/0`, a list of numbers, or an integer
      into which the `money` is spread.

    * `options` is a keyword list of options, which will be applied to
      `Money.round/2`.

  Returns a list of `t:Money.t/0` that is the same length (or value of the integer),
  with the amount spread as evenly as the currency's smallest unit allows.
  The result is derived as follows:

  1. Round the amount to the currency's default precision.

  2. Calculate partial sums of the given portions.

  3. Starting with the last portion, calculate the expected remaining amount then
     subtract and round that portion's value from the current remaining amount.

  For example, with `[2, 1]` as portions and `$1` to spread, we calculate that 2/3 of the amount
  should remain after `1` receives its portion, so we subtract the unrounded Money amount of
  `0.666666`, and we round the share to `$0.33`.  Then `$1.00 - 0.33` is the new remaining amount.
  This approach avoids numerical instability by using the expected remaining amount,
  rather than summing up values as they are doled out.

  ## Examples

      iex> Money.spread(Money.new(:usd, 10), [Money.new(:usd, 10), Money.new(:usd, 1)])
      [Money.new(:USD, "9.09"), Money.new(:USD, "0.91")]

      iex> Money.spread(Money.new(:usd, "2.50"), [2.5, 1, 1])
      [Money.new(:USD, "1.39"), Money.new(:USD, "0.55"), Money.new(:USD, "0.56")]

      iex> Money.spread(Money.new(:usd, 2), 3)
      [Money.new(:USD, "0.67"), Money.new(:USD, "0.66"), Money.new(:USD, "0.67")]

  """
  @spec spread(Money.t(), list(Money.t()) | list(number()) | integer()) :: list(Money.t())
  def spread(amount, portions, options \\ [])
  def spread([], _, _), do: []

  def spread(amount, portions, options) when is_integer(portions) do
    spread(amount, List.duplicate(1, portions), options)
  end

  def spread(%Money{} = amount, [h | _] = portions, options) do
    {shares, _, _} = recurse_spread(portions, spread_zero(h), round(amount), options)
    shares
  end

  def spread(_, _, _), do: raise("Amount to spread must be Money.t()")

  defp recurse_spread([], total, amount, _opts), do: {[], amount, total}

  defp recurse_spread([head | tail], curr_sum, amount, options) do
    partial_sum = spread_sum(head, curr_sum)
    {shares, remaining, total} = recurse_spread(tail, partial_sum, amount, options)

    proportion_remaining = prop_remaining(curr_sum, total)
    unrounded_now_remaining = mult!(amount, proportion_remaining)

    share = sub!(remaining, unrounded_now_remaining) |> round(options)
    now_remaining = sub!(remaining, share)

    {[share | shares], now_remaining, total}
  end

  defp prop_remaining(%Money{} = partial_sum, total),
    do: Decimal.div(to_decimal(partial_sum), to_decimal(total))

  defp prop_remaining(partial_sum, total), do: partial_sum / total

  defp spread_sum(%Money{} = head, sum), do: add!(head, sum)
  defp spread_sum(head, sum), do: head + sum

  defp spread_zero(%Money{} = head), do: zero(head)
  defp spread_zero(_head), do: 0

  @doc """
  Round a `Money` value into the acceptable range for the requested currency.

  ### Arguments

  * `money` is any `t:Money.t/0`.

  * `options` is a keyword list of options.

  ### Options

    * `:rounding_mode` that defines how the number will be rounded.  See
      `Decimal.Context`.  The default is `:half_even` which is also known
      as "banker's rounding".

    * `:currency_digits` which determines the rounding increment.
      The valid options are `:cash`, `:accounting` and `:iso` or
      an integer value representing the rounding factor.  The
      default is `:iso`.

  ### Notes

  There are two kinds of rounding applied:

  1. Round to the appropriate number of currency digits.

  3. Apply an appropriate rounding increment.  Most currencies
     round to the same precision as the number of decimal digits, but some
     such as `:CHF` round to a minimum such as `0.05` when its a cash
     amount. The rounding increment is applied when the option
     `:fractional_digits` is set to `:cash`.

  3. Digital Tokens (crypto currencies) do not have formal definitions
     of decimal digits or rounding strategies. Therefore the `money` is
     returned unmodified.

  ### Examples

      iex> Money.round Money.new("123.73", :CHF), currency_digits: :cash
      Money.new(:CHF, "123.75")

      iex> Money.round Money.new("123.73", :CHF), currency_digits: 0
      Money.new(:CHF, "124")

      iex> Money.round Money.new("123.7456", :CHF)
      Money.new(:CHF, "123.75")

      iex> Money.round Money.new("123.7456", :JPY)
      Money.new(:JPY, "124")

  """
  @spec round(Money.t(), Keyword.t()) :: Money.t() | {:error, {module(), binary()}}
  def round(money, opts \\ [])

  # Digital tokens don't have rounding
  def round(%Money{currency: token_id} = money, _opts) when is_digital_token(token_id) do
    money
  end

  def round(%Money{} = money, options) do
    money
    |> round_to_decimal_digits(options)
    |> round_to_nearest(options)
  end

  defp round_to_decimal_digits(%Money{currency: code, amount: amount}, options) do
    with {:ok, currency} <- Money.Currency.currency_for_code(code),
         {:ok, rounding, _options} = digits_from_options(currency, options) do
      rounding_mode = Keyword.get(options, :rounding_mode, @default_rounding_mode)
      rounded_amount = Decimal.round(amount, rounding, rounding_mode)
      %Money{currency: code, amount: rounded_amount}
    end
  end

  defp round_to_nearest(%Money{currency: code} = money, options) do
    with {:ok, currency} <- Money.Currency.currency_for_code(code),
         {:ok, digits, _options} = digits_from_options(currency, options) do
      increment = increment_from_options(currency, options)
      do_round_to_nearest(money, digits, increment, options)
    end
  end

  defp round_to_nearest({:error, _} = error, _opts) do
    error
  end

  defp do_round_to_nearest(money, _digits, 0, _opts) do
    money
  end

  defp do_round_to_nearest(money, digits, increment, options) do
    rounding_mode = Keyword.get(options, :rounding_mode, @default_rounding_mode)

    rounding =
      -digits
      |> Localize.Utils.Math.power_of_10()
      |> Kernel.*(increment)
      |> Decimal.from_float()

    rounded_amount =
      money.amount
      |> Decimal.div(rounding)
      |> Decimal.round(0, rounding_mode)
      |> Decimal.mult(rounding)

    %Money{currency: money.currency, amount: rounded_amount}
  end

  defp increment_from_options(currency, options) do
    case Keyword.get(options, :currency_digits) do
      :cash -> currency.cash_rounding
      _other -> currency.rounding
    end
  end

  @doc """
  Set the fractional part of a `Money`.

  ### Arguments

  * `money` is any `t:Money.t/0`.

  * `fraction` is an integer amount that will be set
    as the fraction of the `money`.

  ### Notes

  The fraction can only be set if it matches the number of
  decimal digits for the currency associated with the `money`.
  Therefore, for a currency with 2 decimal digits, the
  maximum for `fraction` is `99`.

  ### Examples

      iex> Money.put_fraction Money.new(:USD, "2.49"), 99
      Money.new(:USD, "2.99")

      iex> Money.put_fraction Money.new(:USD, "2.49"), 0
      Money.new(:USD, "2.0")

      iex> Money.put_fraction Money.new(:USD, "2.49"), 999
      {:error,
       {Money.InvalidAmountError, "Rounding up to 999 is invalid for currency :USD"}}

  """
  def put_fraction(money, fraction \\ 0)

  @one Decimal.new(1)
  @zero Decimal.new(0)

  def put_fraction(%Money{amount: amount} = money, upto) when is_integer(upto) do
    with {:ok, currency} <- Money.Currency.currency_for_code(money.currency) do
      digits = currency.digits
      diff = Decimal.from_float((100 - upto) * :math.pow(10, -digits))

      if Decimal.compare(diff, @one) in [:lt, :eq] &&
           Decimal.compare(@zero, diff) in [:lt, :eq] do
        new_amount =
          Decimal.round(amount, 0)
          |> Decimal.add(@one)
          |> Decimal.sub(diff)

        %{money | amount: new_amount}
      else
        {:error,
         {Money.InvalidAmountError,
          "Rounding up to #{inspect(upto)} is invalid for currency #{inspect(money.currency)}"}}
      end
    end
  end

  @doc """
  Localizes a `Money` by converting it to the currency
  of the specified locale.

  ### Arguments

  * `money` is any `t:Money.t/0` struct returned by `Money.Currency.new/2`.

  * `options` is a keyword list of options.

  ### Options

  * `:locale` is any valid locale returned by `Localize.supported_locales/0`
    or a `Localize.LanguageTag` struct.
    The default is `Localize.get_locale/0`.

  ### Returns

  * `{:ok, localized_money}` or

  * `{:error, {exception, reason}}`

  """
  @doc since: "5.12.0"

  @spec localize(t(), Keyword.t()) :: {:ok, t()} | {:error, {module(), String.t()}}
  def localize(%Money{} = money, options \\ []) do
    locale = Keyword.get(options, :locale, Localize.get_locale())

    with {:ok, locale} <- Localize.validate_locale(locale),
         {:ok, currency} <- Localize.Currency.currency_from_locale(locale) do
      to_currency(money, currency)
    end
  end

  @doc """
  Convert `money` from one currency to another.

  ### Arguments

  * `money` is any `t:Money.t/0` struct returned by `Money.Currency.new/2`.

  * `to_currency` is a valid currency code into which the `money` is converted.

  * `rates` is a `Map` of currency rates where the map key is an upcased
    atom or string and the value is a Decimal conversion factor.  The default is the
    latest available exchange rates returned from `Money.ExchangeRates.latest_rates/0`.

  ### Converting to a currency defined in a locale

  To convert a `Money` to a currency defined by a locale,
  `Localize.Currency.currency_from_locale/1` can be called with
  a `t:Localize.LanguageTag.t/0` parameter. It will return
  the currency configured for that locale.

  ### Examples

      iex> Money.to_currency(Money.new(:USD, 100), :AUD,
      ...>   %{USD: Decimal.new(1), AUD: Decimal.from_float(0.7345)})
      {:ok, Money.new(:AUD, "73.4500")}

      iex> Money.to_currency(Money.new("USD", 100), "AUD",
      ...>   %{"USD" => Decimal.new(1), "AUD" => Decimal.from_float(0.7345)})
      {:ok, Money.new(:AUD, "73.4500")}

      iex> Money.to_currency(Money.new(:USD, 100), :AUDD,
      ...>   %{USD: Decimal.new(1), AUD: Decimal.from_float(0.7345)})
      {:error, {Money.UnknownCurrencyError, "The currency :AUDD is not known."}}

      iex> Money.to_currency(Money.new(:USD, 100), :CHF,
      ...>   %{USD: Decimal.new(1), AUD: Decimal.from_float(0.7345)})
      {:error, {Money.ExchangeRateError,
        "No exchange rate is available for currency :CHF"}}

  """
  @spec to_currency(
          Money.t(),
          currency_reference(),
          ExchangeRates.t() | {:ok, ExchangeRates.t()} | {:error, {module(), String.t()}}
        ) :: {:ok, Money.t()} | {:error, {module(), String.t()}}

  def to_currency(money, to_currency, rates \\ Money.ExchangeRates.latest_rates())

  def to_currency(%Money{} = money, currency, {:ok, %{} = rates}) do
    to_currency(money, currency, rates)
  end

  def to_currency(_money, _to_currency, {:error, reason}) do
    {:error, reason}
  end

  def to_currency(%Money{currency: currency} = money, currency, _rates) do
    {:ok, money}
  end

  def to_currency(%Money{currency: from_currency, amount: amount} = money, to_currency, rates)
      when is_atom(to_currency) or (is_digital_token(to_currency) and is_map(rates)) do
    with {:ok, to_currency_code} <- validate_currency(to_currency),
         {:ok, cross_rate} <- cross_rate(from_currency, to_currency_code, rates) do
      converted_amount = Decimal.mult(amount, cross_rate)
      {:ok, %{money | currency: to_currency, amount: converted_amount}}
    end
  end

  def to_currency(%Money{} = money, to_currency, %{} = rates)
      when is_binary(to_currency) do
    with {:ok, currency_code} <- validate_currency(to_currency) do
      to_currency(money, currency_code, rates)
    end
  end

  @doc """
  Convert `money` from one currency to another or raises on error.

  ### Arguments

  * `money` is any `t:Money.t/0` struct returned by `Money.Currency.new/2`.

  * `to_currency` is a valid currency code into which the `money` is converted.

  * `rates` is a `Map` of currency rates where the map key is an upcased
    atom or string and the value is a Decimal conversion factor.  The default is the
    latest available exchange rates returned from `Money.ExchangeRates.latest_rates/0`.

  ### Examples

      iex> Money.to_currency! Money.new(:USD, 100), :AUD,
      ...>   %{USD: Decimal.new(1), AUD: Decimal.from_float(0.7345)}
      Money.new(:AUD, "73.4500")

      iex> Money.to_currency! Money.new("USD", 100), "AUD",
      ...>   %{"USD" => Decimal.new(1), "AUD" => Decimal.from_float(0.7345)}
      Money.new(:AUD, "73.4500")

      => Money.to_currency! Money.new(:USD, 100), :ZZZ,
           %{USD: Decimal.new(1), AUD: Decimal.from_float(0.7345)}
      ** (Money.UnknownCurrencyError) The currency :ZZZ is not known.

  """
  @spec to_currency!(
          Money.t(),
          currency_reference(),
          ExchangeRates.t() | {:ok, ExchangeRates.t()} | {:error, {module(), String.t()}}
        ) :: Money.t() | no_return

  def to_currency!(money, to_currency, rates \\ Money.ExchangeRates.latest_rates())

  def to_currency!(%Money{} = money, currency, rates) do
    case to_currency(money, currency, rates) do
      {:ok, money} -> money
      {:error, {exception, reason}} -> raise exception, reason
    end
  end

  @doc """
  Returns the effective cross-rate to convert from one currency
  to another.

  ### Arguments

  * `from` is any `t:Money.t/0` struct returned by `Money.Currency.new/2` or a valid
     currency code.

  * `to_currency` is a valid currency code into which the `money` is converted.

  * `rates` is a `Map` of currency rates where the map key is an upcased
    atom or string and the value is a Decimal conversion factor.  The default is the
    latest available exchange rates returned from `Money.ExchangeRates.latest_rates/0`.

  ### Examples

      Money.cross_rate(Money.new(:USD, 100), :AUD, %{USD: Decimal.new(1), AUD: Decimal.new("0.7345")})
      {:ok, Decimal.new("0.7345")}

      Money.cross_rate Money.new(:USD, 100), :ZZZ, %{USD: Decimal.new(1), AUD: Decimal.new(0.7345)}
      ** (Money.UnknownCurrencyError) The currency :ZZZ is not known.

  """
  @spec cross_rate(
          Money.t() | currency_reference(),
          currency_reference(),
          ExchangeRates.t() | {:ok, ExchangeRates.t()}
        ) :: {:ok, Decimal.t()} | {:error, {module(), String.t()}}

  def cross_rate(from, to, rates \\ Money.ExchangeRates.latest_rates())

  def cross_rate(from, to, {:ok, rates}) do
    cross_rate(from, to, rates)
  end

  def cross_rate(%Money{currency: from_currency}, to_currency, %{} = rates) do
    cross_rate(from_currency, to_currency, rates)
  end

  def cross_rate(from_currency, to_currency, %{} = rates) do
    with {:ok, from_code} <- validate_currency(from_currency),
         {:ok, to_code} <- validate_currency(to_currency),
         {:ok, from_rate} <- get_rate(from_code, rates),
         {:ok, to_rate} <- get_rate(to_code, rates) do
      {:ok, Decimal.div(to_rate, from_rate)}
    end
  end

  @doc """
  Returns the effective cross-rate to convert from one currency
  to another.

  ### Arguments

  * `from` is any `t:Money.t/0` struct returned by `Money.Currency.new/2` or a valid
     currency code.

  * `to_currency` is a valid currency code into which the `money` is converted.

  * `rates` is a `Map` of currency rates where the map key is an upcased
    atom or string and the value is a Decimal conversion factor.  The default is the
    latest available exchange rates returned from `Money.ExchangeRates.latest_rates/0`.

  ### Examples

      iex> Money.cross_rate!(Money.new(:USD, 100), :AUD, %{USD: Decimal.new(1), AUD: Decimal.new("0.7345")})
      Decimal.new("0.7345")

      iex> Money.cross_rate!(:USD, :AUD, %{USD: Decimal.new(1), AUD: Decimal.new("0.7345")})
      Decimal.new("0.7345")

      Money.cross_rate Money.new(:USD, 100), :ZZZ, %{USD: Decimal.new(1), AUD: Decimal.new("0.7345")}
      ** (Money.UnknownCurrencyError) The currency :ZZZ is not known.

  """
  @spec cross_rate!(
          Money.t() | currency_reference(),
          currency_reference(),
          ExchangeRates.t() | {:ok, ExchangeRates.t()}
        ) :: Decimal.t() | no_return

  def cross_rate!(from, to_currency, rates \\ Money.ExchangeRates.latest_rates())

  def cross_rate!(from, to_currency, rates) do
    cross_rate(from, to_currency, rates)
    |> do_cross_rate!
  end

  defp do_cross_rate!({:ok, rate}) do
    rate
  end

  defp do_cross_rate!({:error, {exception, reason}}) do
    raise exception, reason
  end

  @doc """
  Normalizes the underlying decimal amount in a
  given `t:Money.t/0`.

  This will normalize the coefficient and exponent of the
  decimal amount in a standard way that may aid in
  native comparison of `t:Money.t/0` items.

  ## Example

      iex> x = %Money{currency: :USD, amount: %Decimal{sign: 1, coef: 42, exp: 0}}
      Money.new(:USD, "42")
      iex> y = %Money{currency: :USD, amount: %Decimal{sign: 1, coef: 4200000000, exp: -8}}
      Money.new(:USD, "42.00000000")
      iex> x == y
      false
      iex> y = Money.normalize(x)
      Money.new(:USD, "42")
      iex> x == y
      true

  """
  @spec normalize(Money.t()) :: Money.t()
  @doc since: "5.0.0"

  if Code.ensure_loaded?(Decimal) and function_exported?(Decimal, :normalize, 1) do
    def normalize(%Money{amount: amount} = money) do
      %{money | amount: Decimal.normalize(amount)}
    end
  else
    def normalize(%Money{amount: amount} = money) do
      %{money | amount: Decimal.reduce(amount)}
    end
  end

  @deprecated "Use Money.normalize/1 instead."
  def reduce(money) do
    normalize(money)
  end

  @doc """
  Returns a tuple comprising the currency code, integer amount,
  exponent and remainder.

  Some services require submission of money items as an integer
  with an implied exponent that is appropriate to the currency.

  Rather than return only the integer, `Money.to_integer_exp`
  returns the currency code, integer, exponent and remainder.
  The remainder is included because to return an integer
  money with an implied exponent the `Money` has to be rounded
  potentially leaving a remainder.

  ### Options

  * `money` is any `t:Money.t/0` struct returned by `Money.Currency.new/2`.

  ### Notes

  * Since the returned integer is expected to have the implied fractional
    digits the `Money` needs to be rounded which is what this function does.

  ### Example

      iex> m = Money.new(:USD, "200.012356")
      Money.new(:USD, "200.012356")
      iex> Money.to_integer_exp(m)
      {:USD, 20001, -2, Money.new(:USD, "0.002356")}

      iex> m = Money.new(:USD, "200.00")
      Money.new(:USD, "200.00")
      iex> Money.to_integer_exp(m)
      {:USD, 20000, -2, Money.new(:USD, "0.00")}

  """
  def to_integer_exp(%Money{} = money, options \\ []) do
    new_money =
      money
      |> Money.round(options)
      |> Money.normalize()

    with {:ok, remainder} <- Money.sub(money, new_money),
         {:ok, currency} <- Money.Currency.currency_for_code(money.currency),
         {:ok, exponent, _options} <- digits_from_options(currency, options) do
      exponent_adjustment = Kernel.abs(-exponent - new_money.amount.exp)

      integer =
        Localize.Utils.Math.power_of_10(exponent_adjustment) * new_money.amount.coef *
          new_money.amount.sign

      {money.currency, integer, -exponent, remainder}
    end
  end

  @doc """
  Convert an integer representation of money into a `Money` struct.

  ### Arguments

  * `integer` is an integer representation of a money amount including
    any decimal digits.  ie. `20000` would be interpreted to mean `$200.00`
    if the `currency` is `:USD` and no `:currency_digits` option
    was provided.

  * `currency` is the currency code for the `integer`.  The assumed
    decimal precision is derived from the currency code if no `fractional_digits`
    option is specified.

  * `options` is a keyword list of options.

  ### Options

  * `:currency_digits` which determines the currency precision implied
    by the `integer`. The valid options are `:cash`, `:accounting`,
    `:iso` or a non-negative integer. The default is `:iso` which uses the
    [ISO 4217](https://en.wikipedia.org/wiki/ISO_4217) definition of
    currency digits.

  All other options are passed to `Money.new/3`.

  ### Returns

  * A `t:Money.t/0` struct or

  * `{:error, {exception, message}}`

  ### Notes

  * Some currencies, like the [Iraqi Dinar](https://en.wikipedia.org/wiki/Iraqi_dinar)
    have a difference in the decimal digits defined by CLDR versus
    those defined by [ISO 4217](https://en.wikipedia.org/wiki/ISO_4217). CLDR
    defines the decimal digits for `IQD` as `0` whereas ISO 4217 defines
    `3` decimal digits.

  * Since converting an integer to a money amount is very
    sensitive to the number of fractional digits specified it is
    important to be very clear about the precision of the data used
    with this function and care taken in specifying the `:fractional_digits`
    parameter.

  ### Examples

      iex> Money.from_integer(20000, :USD)
      Money.new(:USD, "200.00")

      iex> Money.from_integer(200, :JPY)
      Money.new(:JPY, "200")

      iex> Money.from_integer(20012, :USD)
      Money.new(:USD, "200.12")

      iex> Money.from_integer(20012, :USD, currency_digits: 3)
      Money.new(:USD, "20.012")

      iex> Money.from_integer(20012, :IQD)
      Money.new(:IQD, "20.012")

  """
  @spec from_integer(integer, currency_reference(), Keyword.t()) ::
          Money.t() | {:error, {module(), String.t()}}

  def from_integer(amount, currency, options \\ [])
      when is_integer(amount) and is_list(options) do
    options = replace_fractional_digits_with_currency_digits(options)

    with {:ok, currency} <- validate_currency(currency),
         {:ok, currency_data} <- Money.Currency.currency_for_code(currency),
         {:ok, digits, options} <- digits_from_options(currency_data, options) do
      sign = if amount < 0, do: -1, else: 1

      sign
      |> Decimal.new(Kernel.abs(amount), -digits)
      |> Money.new(currency, options)
    end
  end

  defp digits_from_options(currency_data, options) when is_list(options) do
    {fractional_digits, options} = Keyword.pop(options, :currency_digits)

    with {:ok, digits} <- do_digits_from_options(currency_data, fractional_digits) do
      {:ok, digits, options}
    else
      :error -> {:error, invalid_digits_error(fractional_digits)}
      other -> other
    end
  end

  defp do_digits_from_options(currency_data, :iso), do: Map.fetch(currency_data, :iso_digits)
  defp do_digits_from_options(currency_data, nil), do: Map.fetch(currency_data, :iso_digits)
  defp do_digits_from_options(currency_data, :cash), do: Map.fetch(currency_data, :cash_digits)
  defp do_digits_from_options(currency_data, :accounting), do: Map.fetch(currency_data, :digits)

  defp do_digits_from_options(_currency_data, integer) when is_integer(integer) and integer >= 0,
    do: {:ok, integer}

  defp do_digits_from_options(_currency_data, other),
    do: {:error, invalid_digits_error(other)}

  defp invalid_digits_error(other),
    do:
      {Money.InvalidDigitsError,
       "Unknown or invalid :currency_digits option, found: #{inspect(other)}"}

  # :fractional_digits option renamed to :currency_digits for
  # consistency with Money.round/2 and `ex_cldr_numbers`

  defp replace_fractional_digits_with_currency_digits(options) do
    case Keyword.pop(options, :fractional_digits) do
      {nil, options} -> options
      {digits, options} -> Keyword.put(options, :currency_digits, digits)
    end
  end

  @doc """
  Return a zero amount `t:Money.t/0` in the given currency.

  ### Arguments

  * `money_or_currency` is either a `t:Money.t/0` or
    a currency code.

  * `options` is a keyword list of options passed
    to `Money.new/3`. The default is `[]`.

  ### Example

      iex> Money.zero(:USD)
      Money.new(:USD, "0")

      iex> money = Money.new(:USD, 200)
      iex> Money.zero(money)
      Money.new(:USD, "0")

      iex> Money.zero :ZZZ
      {:error, {Money.UnknownCurrencyError, "The currency :ZZZ is not known."}}

  """
  @spec zero(currency_reference() | Money.t()) ::
          Money.t() | {:error, {module(), binary()}}
  @spec zero(currency_reference() | Money.t(), Keyword.t()) ::
          Money.t() | {:error, {module(), binary()}}

  def zero(money_or_currency_code, options \\ [])

  def zero(%Money{currency: currency_code}, options) do
    zero(currency_code, options)
  end

  def zero(currency_code, options) do
    with {:ok, currency_code} <- validate_currency(currency_code) do
      Money.new(currency_code, 0, options)
    end
  end

  @doc """
  Returns a boolean indicating if `t:Money.t/0`
  has a zero value.

  ### Arguments

  * `money` is any valid `t:Money.t/0` type returned
    by `Money.new/2`

  ### Example

      iex> Money.zero?(Money.new(:USD, 0))
      true

      iex> Money.zero?(Money.new(:USD, 1))
      false

      iex> Money.zero?(Money.new(:USD, -1))
      false

  """
  @doc since: "5.10.0"
  @spec zero?(Money.t()) :: boolean

  def zero?(%{currency: currency} = value) do
    case compare(zero(currency), value) do
      :eq -> true
      _ -> false
    end
  end

  @doc """
  Returns a boolean indicating if `t:Money.t/0`
  is an integer value (has no significant fractional
  digits).

  ### Arguments

  * `money` is any valid `t:Money.t/0` type returned
    by `Money.new/2`

  ### Example

      iex> Money.integer?(Money.new(:USD, 0))
      true

      iex> Money.integer?(Money.new(:USD, "1.10"))
      false

  """
  @doc since: "5.10.0"
  @spec integer?(Money.t()) :: boolean

  if function_exported?(Decimal, :integer?, 1) do
    def integer?(%{amount: amount}) do
      Decimal.integer?(amount)
    end
  else
    def integer?(%{amount: %Decimal{coef: :NaN}}), do: false
    def integer?(%{amount: %Decimal{coef: :inf}}), do: false

    def integer?(%{amount: %Decimal{coef: coef, exp: exp}}),
      do: exp >= 0 or zero_after_dot?(coef, exp)

    defp zero_after_dot?(coef, exp) when coef >= 10 and exp < 0,
      do: Kernel.rem(coef, 10) == 0 and zero_after_dot?(Kernel.div(coef, 10), exp + 1)

    defp zero_after_dot?(coef, exp),
      do: coef == 0 or exp == 0
  end

  @doc """
  Returns a boolean indicating if `t:Money.t/0`
  has a positive value.

  ### Arguments

  * `money` is any valid `t:Money.t/0` type returned
    by `Money.new/2`

  ### Example

      iex> Money.positive?(Money.new(:USD, 1))
      true

      iex> Money.positive?(Money.new(:USD, 0))
      false

      iex> Money.positive?(Money.new(:USD, -1))
      false

  """
  @doc since: "5.10.0"
  @spec positive?(Money.t()) :: boolean

  def positive?(%{currency: currency} = value) do
    case compare(zero(currency), value) do
      :lt -> true
      _ -> false
    end
  end

  @doc """
  Returns a boolean indicating if `t:Money.t/0`
  has a negative value.

  ### Arguments

  * `money` is any valid `t:Money.t/0` type returned
    by `Money.new/2`

  ### Example

      iex> Money.negative?(Money.new(:USD, -1))
      true

      iex> Money.negative?(Money.new(:USD, 0))
      false

      iex> Money.negative?(Money.new(:USD, 1))
      false

  """
  @doc since: "5.10.0"
  @spec negative?(Money.t()) :: boolean

  def negative?(%{currency: currency} = value) do
    case compare(zero(currency), value) do
      :gt -> true
      _ -> false
    end
  end

  @doc false
  def from_integer({currency, integer, _exponent, _remainder}) do
    from_integer(integer, currency)
  end

  @doc false
  def validate_currency(currency_code, options \\ []) do
    normalized = normalize_currency_code(currency_code)

    case Localize.Currency.validate_currency(normalized) do
      {:ok, code} ->
        {:ok, code}

      {:error, _} ->
        store_key = if is_binary(normalized), do: String.to_atom(normalized), else: normalized

        case Money.Currency.Store.get(store_key) do
          %Localize.Currency{code: code} ->
            {:ok, code}

          nil ->
            error = {Money.UnknownCurrencyError, "The currency #{inspect(store_key)} is not known."}
            validate_digital_token(currency_code, options, error)
        end
    end
  end

  defp validate_digital_token(currency_code, options, original_error) do
    if Code.ensure_loaded?(DigitalToken) do
      case apply(DigitalToken, :validate_token, [currency_code, options]) do
        {:ok, token_id} -> {:ok, token_id}
        {:error, _} -> {:error, original_error}
      end
    else
      {:error, original_error}
    end
  end

  @doc false
  def unknown_currency_error(currency) do
    {Money.UnknownCurrencyError, "The currency #{inspect(currency)} is unknown or not supported"}
  end

  @doc false
  def invalid_amount_error(amount) do
    {Money.InvalidAmountError, "Amount cannot be converted to a number: #{inspect(amount)}"}
  end

  defp invalid_money_error(param_a, param_b) do
    {Money.Invalid, "Unable to create money from #{inspect(param_a)} and #{inspect(param_b)}"}
  end

  ## Helpers

  @doc false
  def get_env(key, default \\ nil) do
    case env = Application.get_env(:ex_money, key, default) do
      {:system, env_key} ->
        System.get_env(env_key) || default

      _ ->
        env
    end
  end

  def get_env(key, default, :integer) do
    key
    |> get_env(default)
    |> to_integer
  end

  def get_env(key, default, :maybe_integer) do
    key
    |> get_env(default)
    |> to_maybe_integer
  end

  def get_env(key, default, :module) do
    key
    |> get_env(default)
    |> to_module()
  end

  def get_env(key, default, :boolean) do
    case get_env(key, default) do
      true ->
        true

      false ->
        false

      other ->
        raise RuntimeError,
              "[ex_money] The configuration key " <>
                "#{inspect(key)} must be either true or false. #{inspect(other)} was provided."
    end
  end

  defp to_integer(nil), do: nil
  defp to_integer(n) when is_integer(n), do: n
  defp to_integer(n) when is_binary(n), do: String.to_integer(n)

  defp to_maybe_integer(nil), do: nil
  defp to_maybe_integer(n) when is_integer(n), do: n
  defp to_maybe_integer(n) when is_atom(n), do: n
  defp to_maybe_integer(n) when is_binary(n), do: String.to_integer(n)

  defp to_module(nil), do: nil
  defp to_module(module_name) when is_atom(module_name), do: module_name

  defp to_module(module_name) when is_binary(module_name) do
    Module.concat([module_name])
  end

  defp get_rate(currency, rates) do
    keys = (is_atom(currency) && [currency, Atom.to_string(currency)]) || [currency]

    rates
    |> Map.take(keys)
    |> Map.values()
    |> case do
      [rate] ->
        {:ok, rate}

      _ ->
        {:error,
         {Money.ExchangeRateError,
          "No exchange rate is available for currency #{inspect(currency)}"}}
    end
  end

  defp parse_decimal(string, nil, options) do
    parse_decimal(string, Localize.get_locale(), options)
  end

  defp parse_decimal(string, locale, options) do
    with {:ok, locale} <- Localize.validate_locale(locale),
         {:ok, symbols} <- Localize.Number.Symbol.number_symbols_for(locale),
         {:ok, script_symbols} <- number_symbols_for_number_system(symbols, locale),
         {:ok, group, decimal} <- symbol_preference(script_symbols, options) do
      decimal =
        string
        |> String.replace(group, "")
        |> String.replace(decimal, ".")
        |> Decimal.new()

      {:ok, decimal}
    end
  rescue
    Decimal.Error ->
      {:error, invalid_amount_error(string)}
  end

  defp symbol_preference(symbols, options) do
    preference = Keyword.get(options, :separators, :standard)

    group =
      Map.get(symbols.group, preference) || Map.fetch!(symbols.group, :standard)

    decimal =
      Map.get(symbols.decimal, preference) || Map.fetch!(symbols.decimal, :standard)

    {:ok, group, decimal}
  end

  # Return either a Decimal or nil

  defp maybe_decimal(amount, options) when is_binary(amount) do
    case parse_decimal(amount, options[:locale], options) do
      {:ok, decimal} -> decimal
      _other -> nil
    end
  end

  defp maybe_decimal(_amount, _options) do
    nil
  end

  defp number_symbols_for_number_system(symbols, locale) do
    number_system = Localize.Number.System.number_system_from_locale(locale)
    symbols = Map.get(symbols, number_system) || Map.get(symbols, :latn)
    {:ok, symbols}
  end

  @doc false
  @app_name Money.Mixfile.project() |> Keyword.get(:app)
  def app_name do
    @app_name
  end

  @doc """
  Returns the default rounding mode.

  """
  @doc since: "5.18.1"
  def default_rounding_mode do
    @default_rounding_mode
  end

  @doc false
  def exclude_protocol_implementation(module) when is_atom(module) do
    exclusions =
      Application.get_env(:ex_money, :exclude_protocol_implementations, []) |> List.wrap()

    module in exclusions
  end
end
