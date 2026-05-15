defmodule Money.Currency do
  @moduledoc """
  Functions to manage currencies including ISO 4217 currencies
  and custom (private-use) currencies.

  Custom currencies can be created at runtime using `new/2` and
  are stored in `Money.Currency.Store` for fast concurrent access.

  """

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
    with {:ok, currency_code} <- validate_new_currency(currency_code),
         {:ok, options} <- validate_options(currency_code, options) do
      currency = struct(Localize.Currency, [{:code, currency_code} | options])
      Money.Currency.Store.put(currency)
    end
  end

  # ── Known currency lists ──────────────────────────────────────

  @doc """
  Returns the list of currently active ISO 4217 currency codes.

  ## Example:

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
  def known_current_currencies do
    @current_currencies
  end

  @doc """
  Returns the list of historic ISO 4217 currency codes.

  ## Example:

      iex> Money.Currency.known_historic_currencies()
      [:ADP, :AFA, :ALK, :ANG, :AOK, :AON, :AOR, :ARA, :ARL, :ARM, :ARP, :ATS, :AZM,
       :BAD, :BAN, :BEC, :BEF, :BEL, :BGL, :BGM, :BGN, :BGO, :BOL, :BOP, :BRB, :BRC,
       :BRE, :BRN, :BRR, :BRZ, :BUK, :BYB, :BYR, :CLE, :CNH, :CNX, :CSD, :CSK, :CUC,
       :CYP, :DDM, :DEM, :ECS, :ECV, :EEK, :ESA, :ESB, :ESP, :FIM, :FRF, :GEK, :GHC,
       :GNS, :GQE, :GRD, :GWE, :GWP, :HRD, :HRK, :IEP, :ILP, :ILR, :ISJ, :ITL, :KRH,
       :KRO, :LTL, :LTT, :LUC, :LUF, :LUL, :LVL, :LVR, :MAF, :MCF, :MDC, :MGF, :MKN,
       :MLF, :MRO, :MTL, :MTP, :MVP, :MXP, :MZE, :MZM, :NIC, :NLG, :PEI, :PES, :PLZ,
       :PTE, :RHD, :ROL, :RUR, :SDD, :SDP, :SIT, :SKK, :SLL, :SRG, :STD, :SUR, :TJR,
       :TMM, :TPE, :TRL, :UAK, :UGS, :USS, :UYP, :VEB, :VEF, :VNN, :XEU, :XFO, :XFU,
       :XRE, :YDD, :YUD, :YUM, :YUN, :YUR, :ZAL, :ZMK, :ZRN, :ZRZ, :ZWD, :ZWL, :ZWR]

  """
  def known_historic_currencies do
    @historic_currencies
  end

  @doc """
  Returns the list of legal tender ISO 4217 currency codes.

  ## Example:

      iex> Money.Currency.known_tender_currencies()
      [:ADP, :AED, :AFA, :AFN, :ALK, :ALL, :AMD, :ANG, :AOA, :AOK, :AON, :AOR, :ARA,
       :ARL, :ARM, :ARP, :ARS, :ATS, :AUD, :AWG, :AZM, :AZN, :BAD, :BAM, :BAN, :BBD,
       :BDT, :BEC, :BEF, :BEL, :BGL, :BGM, :BGN, :BGO, :BHD, :BIF, :BMD, :BND, :BOB,
       :BOL, :BOP, :BOV, :BRB, :BRC, :BRE, :BRL, :BRN, :BRR, :BRZ, :BSD, :BTN, :BUK,
       :BWP, :BYB, :BYN, :BYR, :BZD, :CAD, :CDF, :CHE, :CHF, :CHW, :CLE, :CLF, :CLP,
       :CNH, :CNX, :CNY, :COP, :COU, :CRC, :CSD, :CSK, :CUC, :CUP, :CVE, :CYP, :CZK,
       :DDM, :DEM, :DJF, :DKK, :DOP, :DZD, :ECS, :ECV, :EEK, :EGP, :ERN, :ESA, :ESB,
       :ESP, :ETB, :EUR, :FIM, :FJD, :FKP, :FRF, :GBP, :GEK, :GEL, :GHC, :GHS, :GIP,
       :GMD, :GNF, :GNS, :GQE, :GRD, :GTQ, :GWE, :GWP, :GYD, :HKD, :HNL, :HRD, :HRK,
       :HTG, :HUF, :IDR, :IEP, :ILP, :ILR, :ILS, :INR, :IQD, :IRR, :ISJ, :ISK, :ITL,
       :JMD, :JOD, :JPY, :KES, :KGS, :KHR, :KMF, :KPW, :KRH, :KRO, :KRW, :KWD, :KYD,
       :KZT, :LAK, :LBP, :LKR, :LRD, :LSL, :LTL, :LTT, :LUC, :LUF, :LUL, :LVL, :LVR,
       :LYD, :MAD, :MAF, :MCF, :MDC, :MDL, :MGA, :MGF, :MKD, :MKN, :MLF, :MMK, :MNT,
       :MOP, :MRO, :MRU, :MTL, :MTP, :MUR, :MVP, :MVR, :MWK, :MXN, :MXP, :MXV, :MYR,
       :MZE, :MZM, :MZN, :NAD, :NGN, :NIC, :NIO, :NLG, :NOK, :NPR, :NZD, :OMR, :PAB,
       :PEI, :PEN, :PES, :PGK, :PHP, :PKR, :PLN, :PLZ, :PTE, :PYG, :QAR, :RHD, :ROL,
       :RON, :RSD, :RUB, :RUR, :RWF, :SAR, :SBD, :SCR, :SDD, :SDG, :SDP, :SEK, :SGD,
       :SHP, :SIT, :SKK, :SLE, :SLL, :SOS, :SRD, :SRG, :SSP, :STD, :STN, :SUR, :SVC,
       :SYP, :SZL, :THB, :TJR, :TJS, :TMM, :TMT, :TND, :TOP, :TPE, :TRL, :TRY, :TTD,
       :TWD, :TZS, :UAH, :UAK, :UGS, :UGX, :USD, :USN, :USS, :UYI, :UYP, :UYU, :UYW,
       :UZS, :VEB, :VED, :VEF, :VES, :VND, :VNN, :VUV, :WST, :XAF, :XAG, :XAU, :XBA,
       :XBB, :XBC, :XBD, :XCD, :XCG, :XDR, :XEU, :XFO, :XFU, :XOF, :XPD, :XPF, :XPT,
       :XRE, :XSU, :XTS, :XUA, :XXX, :YDD, :YER, :YUD, :YUM, :YUN, :YUR, :ZAL, :ZAR,
       :ZMK, :ZMW, :ZRN, :ZRZ, :ZWD, :ZWG, :ZWL, :ZWR]

  """
  def known_tender_currencies do
    @tender_currencies
  end

  # ── Custom currency accessors ─────────────────────────────────

  @doc """
  Returns a map of all custom currencies.

  ### Returns

  * A map of `%{currency_code => Localize.Currency.t()}`.

  """
  @spec private_currencies() :: %{atom() => Localize.Currency.t()}
  def private_currencies do
    Money.Currency.Store.all()
  end

  @doc """
  Returns a list of all custom currency codes.

  ### Returns

  * A list of atom currency codes.

  """
  @spec private_currency_codes() :: [atom()]
  def private_currency_codes do
    Money.Currency.Store.codes()
  end

  # ── Currency lookup ───────────────────────────────────────────

  @doc """
  Returns the currency data for the given code.

  Checks locale-specific data first, then falls back to the
  custom currency store.

  """
  def currency_for_code(code) do
    case Localize.Currency.currency_for_code(code) do
      {:ok, _currency} = success ->
        success

      {:error, _} ->
        case Money.Currency.Store.get(normalize_code(code)) do
          nil ->
            {:error, {Money.UnknownCurrencyError, "The currency #{inspect(code)} is not known."}}

          currency ->
            {:ok, currency}
        end
    end
  end

  # ── Private helpers ───────────────────────────────────────────

  defp validate_new_currency(currency_code) do
    canonical_code = normalize_code(currency_code)

    if canonical_code in Localize.Currency.known_currency_codes() do
      {:error, Money.CurrencyAlreadyDefinedError.exception(currency: canonical_code)}
    else
      case validate_custom_currency_code(currency_code) do
        {:ok, code} ->
          if code in Money.Currency.Store.codes() do
            {:error, Money.CurrencyAlreadyDefinedError.exception(currency: code)}
          else
            {:ok, code}
          end

        {:error, _} = error ->
          error
      end
    end
  end

  defp validate_custom_currency_code(currency_code) when is_binary(currency_code) do
    upcase_code = String.upcase(currency_code)

    if Regex.match?(@valid_custom_currency_code, upcase_code) ||
         Regex.match?(@valid_private_currency_code, upcase_code) do
      {:ok, String.to_atom(upcase_code)}
    else
      {:error,
       Money.UnknownCurrencyError.exception(
         "The currency #{inspect(currency_code)} is not a valid custom currency code."
       )}
    end
  end

  defp validate_custom_currency_code(currency_code) when is_atom(currency_code) do
    validate_custom_currency_code(to_string(currency_code))
  end

  defp validate_options(code, options) do
    name = options[:name]

    if name do
      digits = options[:digits] || 2

      validated = [
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

      {:ok, validated}
    else
      {:error, Money.InvalidCurrencyError.exception("Options must include at least a :name key.")}
    end
  end

  defp normalize_code(code) when is_atom(code), do: code

  defp normalize_code(code) when is_binary(code) do
    code |> String.upcase() |> String.to_atom()
  end
end
