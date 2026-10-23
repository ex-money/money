defmodule Money.Currency do
  @moduledoc """
  Functions to manage currencies including ISO 4217 currencies
  and custom (private-use) currencies.

  Custom currencies can be created at runtime using `new/2` and
  are stored in `Money.Currency.Store` for fast concurrent access.

  """

  alias Money.Currency.Store

  @data_dir :code.priv_dir(:localize) |> :erlang.iolist_to_binary()
  @locale_file Path.join([@data_dir, "localize", "locales", "en.etf"])

  @currencies @locale_file
              |> File.read!()
              |> :erlang.binary_to_term()
              |> Map.get(:currencies)

  @current_currencies @currencies
                      |> Enum.filter(fn {_code, currency} -> !is_nil(currency.iso_digits) end)
                      |> Enum.map(fn {code, _currency} -> code end)
                      |> Enum.sort()

  @historic_currencies @currencies
                       |> Enum.filter(fn {_code, currency} -> is_nil(currency.iso_digits) end)
                       |> Enum.map(fn {code, _currency} -> code end)
                       |> Enum.sort()

  @tender_currencies @currencies
                     |> Enum.filter(fn {_code, currency} -> currency.tender end)
                     |> Enum.map(fn {code, _currency} -> code end)
                     |> Enum.sort()

  # Custom currency codes: 4–10 uppercase alphanumeric characters,
  # starting with a letter. The minimum of 4 characters avoids
  # collision with the ISO 4217 3-letter code space.
  @valid_custom_currency_code ~r/^[A-Z][A-Z0-9]{3,9}$/

  # Private-use currency codes conform to the ISO 4217 standard:
  # 3 characters starting with X followed by exactly 2 uppercase
  # letters. These are reserved for application-specific use and
  # will never conflict with an ISO-assigned code.
  @valid_private_currency_code ~r/^X[A-Z]{2}$/

  # ── Custom currency creation ──────────────────────────────────

  @doc """
  Creates a new private-use or custom currency and stores it in the currency store.

  Currencies use the `Localize.Currency` struct as the data shape
  to maintain compatibility with locale-aware formatting.

  ### Arguments

  * `currency_code` is an atom or string currency code. Must be either:

    * A **private-use** code conforming to ISO 4217: 3 characters starting
      with `X` followed by 2 uppercase letters (e.g. `:XBT`, `:XAU`).

    * A **custom** code: 4–10 uppercase alphanumeric characters starting
      with a letter (e.g. `:QFFP`, `:BTC1`).

  * `options` is a keyword list of options.

  ### Options

  * `:name` is the display name of the currency. Required.

  * `:digits` is the decimal precision. The default is `2`.

  * `:symbol` is the currency symbol (e.g. `"₿"`, `"Ξ"`).
    Defaults to the uppercase currency code string.

  * `:narrow_symbol` is an alternative narrow symbol. Optional.

  * `:round_nearest` is the rounding precision such as `0.05`. Optional.

  * `:alt_code` is an alternative currency code for application use. Optional.

  * `:cash_digits` is the precision when used as cash. Defaults to `:digits`.

  * `:cash_round_nearest` is the cash rounding precision. Optional.

  * `:tender` is a boolean indicating whether the currency is
    legal tender. The default is `false`.

  * `:count` is a map of pluralized name forms (e.g.
    `%{one: "Bitcoin", other: "Bitcoins"}`). Defaults to
    `%{other: name}`.

  ### Returns

  * `{:ok, Localize.Currency.t()}` on success.

  * `{:error, exception}` if the code is invalid or already defined.

  ### Examples

      iex> Money.Currency.new(:XAC, name: "XAC currency", digits: 0)
      {:ok,
       %Localize.Currency{
        code: :XAC,
        alt_code: :XAC,
        name: "XAC currency",
        symbol: "XAC",
        narrow_symbol: nil,
        digits: 0,
        rounding: 0,
        cash_digits: 0,
        cash_rounding: nil,
        iso_digits: 0,
        decimal_separator: nil,
        grouping_separator: nil,
        tender: false,
        count: %{other: "XAC currency"},
        from: nil,
        to: nil
      }}

  """
  @spec new(atom() | String.t(), Keyword.t()) ::
          {:ok, Localize.Currency.t()} | {:error, Exception.t()}
  def new(currency_code, options \\ []) do
    with {:ok, code} <- validate_currency_code(currency_code),
         :ok <- refute_already_defined(code),
         {:ok, validated_options} <- validate_options(code, options) do
      Store.put(struct(Localize.Currency, [{:code, code} | validated_options]))
    end
  end

  @doc false
  # Validates a custom currency code and its options and returns the
  # `Localize.Currency` struct without writing it to the store or checking
  # whether it is already registered. Used by `Money.Currency.Store` to
  # materialise currencies declared in the `:custom_currencies` configuration.
  # Performs no `GenServer` call, so it is safe to invoke from within the store
  # process during startup.
  @spec build(atom() | String.t(), Keyword.t()) ::
          {:ok, Localize.Currency.t()} | {:error, Exception.t()}
  def build(currency_code, options \\ []) do
    with {:ok, code} <- validate_currency_code(currency_code),
         {:ok, validated_options} <- validate_options(code, options) do
      {:ok, struct(Localize.Currency, [{:code, code} | validated_options])}
    end
  end

  @doc false
  # Returns true if `code` is declared in the `:custom_currencies` configuration
  # and would build successfully. Validity is decided by `build/2` — the exact
  # function the store uses to register configured currencies at startup — so a
  # code is accepted here if and only if it would register in the store. This is
  # how `Money.validate_currency/2` accepts configured currencies at compile
  # time (where the store is not running) without any behaviour differing from
  # runtime. Declare configured currencies with atom codes so their atoms exist
  # at compile time.
  @spec configured?(atom()) :: boolean()
  def configured?(code) when is_atom(code) and not is_nil(code) do
    Enum.any?(configured_currency_specs(), fn
      {config_code, options} -> match?({:ok, %{code: ^code}}, build(config_code, options))
      _ -> false
    end)
  end

  def configured?(_code) do
    false
  end

  # ── Known currency lists ──────────────────────────────────────

  @doc """
  Returns the list of currently active ISO 4217 currency codes.

  ### Returns

  * a list of the ISO 4217 currency codes that are currently active.

  ### Examples

      iex> Money.Currency.known_current_currencies()
      [:AED, :AFN, :ALL, :AMD, :AOA, :ARS, :AUD, :AWG, :AZN, :BAM, :BBD, :BDT, :BHD,
       :BIF, :BMD, :BND, :BOB, :BOV, :BRL, :BSD, :BTN, :BWP, :BYN, :BZD, :CAD, :CDF,
       :CHE, :CHF, :CHW, :CLF, :CLP, :CNY, :COP, :COU, :CRC, :CUP, :CVE, :CZK, :DJF,
       :DKK, :DOP, :DZD, :EGP, :ERN, :ETB, :EUR, :FJD, :FKP, :GBP, :GEL, :GHS, :GIP,
       :GMD, :GNF, :GTQ, :GYD, :HKD, :HNL, :HTG, :HUF, :IDR, :ILS, :INR, :IQD, :IRR,
       :ISK, :JMD, :JOD, :JPY, :KES, :KGS, :KHR, :KMF, :KPW, :KRW, :KWD, :KYD, :KZT,
       :LAK, :LBP, :LKR, :LRD, :LSL, :LYD, :MAD, :MDL, :MGA, :MKD, :MMK, :MNT, :MOP,
       :MRU, :MUR, :MVR, :MWK, :MXN, :MXV, :MYR, :MZN, :NAD, :NGN, :NIO, :NOK, :NPR,
       :NZD, :OMR, :PAB, :PEN, :PGK, :PHP, :PKR, :PLN, :PYG, :QAR, :RON, :RSD, :RUB,
       :RWF, :SAR, :SBD, :SCR, :SDG, :SEK, :SGD, :SHP, :SLE, :SOS, :SRD, :SSP, :STN,
       :SVC, :SYP, :SZL, :THB, :TJS, :TMT, :TND, :TOP, :TRY, :TTD, :TWD, :TZS, :UAH,
       :UGX, :USD, :USN, :UYI, :UYU, :UYW, :UZS, :VED, :VES, :VND, :VUV, :WST, :XAF,
       :XAG, :XAU, :XBA, :XBB, :XBC, :XBD, :XCD, :XCG, :XDR, :XOF, :XPD, :XPF, :XPT,
       :XSU, :XTS, :XUA, :XXX, :YER, :ZAR, :ZMW, :ZWG]

  """
  @spec known_current_currencies() :: [atom(), ...]
  def known_current_currencies do
    @current_currencies
  end

  @doc """
  Returns the list of historic ISO 4217 currency codes.

  ### Returns

  * a list of historic (no longer active) ISO 4217 currency codes.

  ### Examples

      iex> :DEM in Money.Currency.known_historic_currencies()
      true

      iex> :EUR in Money.Currency.known_historic_currencies()
      false

  """
  @spec known_historic_currencies() :: [atom(), ...]
  def known_historic_currencies do
    @historic_currencies
  end

  @doc """
  Returns the list of legal tender ISO 4217 currency codes.

  ### Returns

  * a list of the ISO 4217 currency codes that are legal tender.

  ### Examples

      iex> :EUR in Money.Currency.known_tender_currencies()
      true

      iex> :ABC in Money.Currency.known_tender_currencies()
      false

  """
  @spec known_tender_currencies() :: [atom(), ...]
  def known_tender_currencies do
    @tender_currencies
  end

  # ── Custom currency accessors ─────────────────────────────────

  @doc false
  # The raw list of `{code, options}` specifications declared in the
  # `:custom_currencies` configuration. This is the single point at which the
  # configuration is read, so the store (which registers them at startup) and
  # `Money.validate_currency/2` (which validates them at compile time) always
  # see the same declarations.
  @spec configured_currency_specs() :: [{atom() | String.t(), Keyword.t()}]
  def configured_currency_specs do
    :ex_money
    |> Application.get_env(:custom_currencies, [])
    |> List.wrap()
  end

  @doc """
  Returns a map of all custom currencies.

  ### Returns

  * A map of `%{currency_code => Localize.Currency.t()}`.

  """
  @spec private_currencies() :: %{atom() => Localize.Currency.t()}
  def private_currencies do
    Store.all()
  end

  @doc """
  Returns a list of all custom currency codes.

  ### Returns

  * A list of atom currency codes.

  """
  @spec private_currency_codes() :: [atom()]
  def private_currency_codes do
    Store.codes()
  end

  # ── Currency lookup ───────────────────────────────────────────

  @doc """
  Returns the currency definition for a currency code.

  The lookup checks the locale-aware currency data first and then falls back
  to the custom currency store. Unknown codes never create new atoms.

  ### Arguments

  * `code` is an ISO 4217 currency code, or a custom or private currency code,
    as an atom or a string.

  ### Returns

  * `{:ok, currency}` where `currency` is a `t:Localize.Currency.t/0` struct.

  * `{:error, {Money.UnknownCurrencyError, message}}` if `code` is not a known
    or registered currency.

  ### Examples

      iex> {:ok, currency} = Money.Currency.currency_for_code(:USD)
      iex> currency.code
      :USD

      iex> Money.Currency.currency_for_code(:NotACurrency)
      {:error, {Money.UnknownCurrencyError, "The currency :NotACurrency is not known."}}

  """
  @spec currency_for_code(atom() | String.t()) ::
          {:ok, Localize.Currency.t()} | {:error, {module(), String.t()}}
  def currency_for_code(code) do
    case normalize_code(code) do
      nil ->
        {:error, {Money.UnknownCurrencyError, "The currency #{inspect(code)} is not known."}}

      normalized ->
        case Localize.Currency.currency_for_code(normalized) do
          {:ok, _currency} = success -> success
          {:error, _} -> custom_currency_for_code(code, normalized)
        end
    end
  end

  # Falls back to the custom currency store for a code that is not a known ISO
  # 4217 currency. `code` is the original (for the error message); `normalized`
  # is the store lookup key.
  defp custom_currency_for_code(code, normalized) do
    case Store.get(normalized) do
      %Localize.Currency{} = currency ->
        {:ok, currency}

      nil ->
        {:error, {Money.UnknownCurrencyError, "The currency #{inspect(code)} is not known."}}
    end
  end

  @doc false
  # Returns true if `code` has the shape of a custom or private currency code
  # (as opposed to a malformed or ISO 4217 code). This is the single definition
  # of the custom/private code format: `validate_custom_currency_code/1` (the
  # registration path) and the `~M` sigil's error message both delegate here, so
  # the format cannot be applied inconsistently.
  @spec private_or_custom_code?(atom() | String.t() | any()) :: boolean()
  def private_or_custom_code?(code) when is_atom(code) and not is_nil(code) do
    private_or_custom_code?(Atom.to_string(code))
  end

  def private_or_custom_code?(code) when is_binary(code) do
    upcased = String.upcase(code)

    Regex.match?(@valid_custom_currency_code, upcased) or
      Regex.match?(@valid_private_currency_code, upcased)
  end

  def private_or_custom_code?(_code) do
    false
  end

  # ── Private helpers ───────────────────────────────────────────

  # Validates the shape of a candidate custom currency code, rejecting codes
  # that collide with an ISO 4217 code. Does not consult the store, so it is
  # side-effect free; the already-registered check is `refute_already_defined/1`.
  defp validate_currency_code(currency_code) do
    canonical_code = normalize_code(currency_code)

    if canonical_code in Localize.Currency.known_currency_codes() do
      {:error, Money.CurrencyAlreadyDefinedError.exception(currency: canonical_code)}
    else
      validate_custom_currency_code(currency_code)
    end
  end

  defp refute_already_defined(code) do
    if code in Store.codes() do
      {:error, Money.CurrencyAlreadyDefinedError.exception(currency: code)}
    else
      :ok
    end
  end

  # Delegates the format check to `private_or_custom_code?/1` (the single source
  # of the format rule) and, when valid, returns the canonical upcased atom.
  defp validate_custom_currency_code(currency_code) do
    if private_or_custom_code?(currency_code) do
      # Creating the atom is safe here: the code has already passed the
      # custom/private format regex (3 to 10 characters) and currency
      # registration is a developer-driven action, not untrusted input.
      # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
      {:ok, currency_code |> to_string() |> String.upcase() |> String.to_atom()}
    else
      {:error,
       Money.UnknownCurrencyError.exception(
         "The currency #{inspect(currency_code)} is not a valid custom currency code."
       )}
    end
  end

  defp validate_options(code, options) do
    case options[:name] do
      nil ->
        {:error, Money.InvalidCurrencyError.exception("Options must include at least a :name key.")}

      name ->
        {:ok, currency_options(code, name, options)}
    end
  end

  # Applies the default for each optional currency field. The defaults are
  # interdependent (`:narrow_symbol` falls back to `:symbol`, `:cash_digits` to
  # `:digits`, and so on), so they are expressed as a flat list of `||`
  # fallbacks rather than a map merge. The cyclomatic complexity is inherent to
  # this defaulting and does not reflect branching logic.
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defp currency_options(code, name, options) do
    digits = options[:digits] || 2

    [
      code: code,
      alt_code: options[:alt_code] || code,
      name: name,
      symbol: options[:symbol] || to_string(code),
      narrow_symbol: options[:narrow_symbol] || options[:symbol],
      digits: digits,
      rounding: options[:round_nearest] || 0,
      cash_digits: options[:cash_digits] || digits,
      cash_rounding: options[:cash_round_nearest] || options[:round_nearest],
      iso_digits: digits,
      tender: options[:tender] || false,
      count: options[:count] || %{other: name}
    ]
  end

  defp normalize_code(code) when is_atom(code), do: code

  # Resolves a binary code to an existing atom without creating new atoms.
  # Returns `nil` when no matching atom exists — such a code cannot name a
  # known or registered currency. Prevents atom-table exhaustion from
  # untrusted input (see String.to_existing_atom/1).
  defp normalize_code(code) when is_binary(code) do
    String.to_existing_atom(String.upcase(code))
  rescue
    ArgumentError -> nil
  end

  defp normalize_code(_code), do: nil
end
