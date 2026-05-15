# `money_tax` — tax labels, snapshot rates, and display helpers

**Status:** planning, last updated 2026-05-15

**Owner:** Money maintainers

**Companion:**
* [money_range.md](money_range.md) — Money range formatting (the other "next gap" beyond single-money).
* [~/Development/localize/localize/plans/e_commerce.md](../../localize/localize/plans/e_commerce.md) — the broader e-commerce roadmap that flagged tax labelling as missing infrastructure (items T1, T2).

## Why a separate library

Tax data has a different refresh cadence, different licensing posture, and different test discipline than currency formatting. Bundling it into `Money` would force every Money user to pull in tax data they don't need (and to inherit a "is the EU VAT rate current?" maintenance burden). A separate `money_tax` package depends on `money` and `localize`, ships its own data, and updates on its own release cadence.

Naming: `money_tax` on Hex; `Money.Tax` namespace in the project. Same convention as `money` / `Money` and `localize_address` / `Localize.Address`.

## Critical scope boundary: display, not calculation

`money_tax` ships **tax labels** (the words "VAT" / "TVA" / "GST" / "消費税") and **snapshot rates** (the standard percentage per territory at a known date). It does **not** ship a tax calculator. Calculating "what tax does this customer owe on this order in this jurisdiction" is a legal-liability problem with thousands of edge cases (good-type exemptions, B2B reverse charge, threshold rules, sub-state district rates, holiday exemptions); libraries that wade in get sued or get stale. The supported scope is:

* Render the right label next to a price (`$20 + tax` / `20 € TTC` / `1,200 円 (税込)`).
* Quote a representative standard rate for display purposes (`"VAT (20%) included"`).
* Define the protocol to plug in an authoritative tax-calculation service (TaxJar, Avalara, Stripe Tax, Vertex) for production use.

This boundary will appear in the @moduledoc and in every public function's @doc, in addition to the README.

## Data layers

### Layer 1 — tax labels (always free, always shipped)

A small static dataset keyed by territory. ~200 entries cover the world. Fields per row:

```elixir
%{
  territory: :GB,
  tax_kind: :vat,
  position: :before_total,        # display convention: tax shown after the subtotal line
  inclusive_default: true,        # consumer prices show inclusive by legal/cultural default
  abbreviation: %{
    "en" => "VAT",
    "cy" => "TAW",
    "de" => "MwSt"                 # appears on cross-border invoices in DE
  },
  full_name: %{
    "en" => "Value Added Tax",
    "cy" => "Treth Ar Werth"
  },
  inclusive_phrase: %{
    "en" => "incl. VAT",
    "cy" => "yn cynnwys TAW"
  },
  exclusive_phrase: %{
    "en" => "+ VAT",
    "cy" => "+ TAW"
  }
}
```

`tax_kind` enumerates: `:vat` (most of world), `:gst` (AU/NZ/CA/SG/IN/MY), `:sales_tax` (US — unlike VAT, sub-national), `:consumption_tax` (JP — same shape as VAT but distinct legal name), `:none` (jurisdictions with no national consumption tax: HK, USA-state-by-state, etc.).

`position` records cultural display convention: where in the line-item summary the tax appears (`:before_total`, `:after_total`, `:within_price`).

`inclusive_default` records whether consumer-facing prices are typically shown tax-included (most of EU/UK/AU/JP) or tax-excluded (US/CA). This drives which formatter is the right default per territory.

Source: Wikipedia's [Value-added tax by country](https://en.wikipedia.org/wiki/Value-added_tax) cross-referenced against the European Commission's TEDB and country revenue-authority sites for ground truth. Manual curation; ~one day to build the initial dataset; quarterly review.

License: data is factual (uncopyrightable in most jurisdictions; database-rights in EU need consideration). Cite Wikipedia and TEDB; ship under the package's MIT/Apache licence.

### Layer 2 — snapshot standard rates (free for ~150 countries)

A second dataset keyed by territory + rate type:

```elixir
%{
  territory: :GB,
  standard_rate: Decimal.new("0.20"),
  reduced_rates: [
    %{rate: Decimal.new("0.05"), description: "Reduced rate (children's car seats, home energy, …)"},
    %{rate: Decimal.new("0.00"), description: "Zero rate (most food, books, children's clothing, …)"}
  ],
  as_of: ~D[2025-04-01],
  source: :tedb,                    # :tedb / :revenue_authority / :wikipedia / :user_supplied
  source_url: "https://ec.europa.eu/..."
}
```

`as_of` is **always** included and surfaced in any function that returns a rate. Callers can decide whether the snapshot is fresh enough for their use case.

Coverage:

* **EU 27 + UK + Norway + Switzerland** — TEDB API is authoritative and free; refresh quarterly via a `mix money_tax.refresh` task that pulls and regenerates the ETF.
* **Australia, NZ, Singapore, UAE, Saudi Arabia, India, Japan, Korea, Vietnam, Thailand, Indonesia, Malaysia, Philippines, South Africa, Israel, Mexico** — single nationwide rates; manual curation from revenue-authority sites; refresh annually or when a public rate change is announced.
* **United States, Canada, Brazil, Argentina** — ship federal/state-level standard rates only; **explicit comment** in the data noting that real tax computation in these countries requires sub-state rates that aren't in the dataset. The `Money.Tax.Source` behaviour (Layer 3) is the right path for these.

Sources and refresh cadence:

| Region | Source | Cadence | Notes |
|--------|--------|---------|-------|
| EU/UK/EEA | EC TEDB API | Quarterly via mix task | Authoritative; free; structured. |
| AU/NZ/SG/AE/SA/IN/JP/KR/VN/TH/ID/MY/PH/ZA/IL | Revenue-authority sites | Annually + on rate-change news | Single-rate; stable; manual update |
| US/CA/BR/AR | Federal/state level only | Annually | Disclaimer documented |
| Everything else | Wikipedia + revenue authority | Annually | Curated; "best-effort" disclaimer |

Total dataset size: ~200 territories × ~5 fields = trivial; ships as a single ETF in `priv/money_tax/rates.etf`.

### Layer 3 — `Money.Tax.Source` behaviour for live lookups and calculation

Defines the contract for plug-in tax services. Every callback past the first two is `@optional` because providers vary in scope (TaxJar covers calculation but not commit-for-filing in some plans; the snapshot source covers neither rate-by-address nor calculation):

```elixir
defmodule Money.Tax.Source do
  alias Money.Tax.{Calculation, Quote, Transaction}

  @callback rate_for(territory :: atom(), options :: keyword()) ::
              {:ok, Quote.t()} | {:error, term()}

  @callback rate_for_address(address :: Localize.Address.t(), options :: keyword()) ::
              {:ok, Quote.t()} | {:error, term()}

  @doc """
  Computes line-item tax for a quoted transaction. The `request` carries
  origin/destination addresses, line items (each a `Money.t()` plus an
  optional product tax code), customer type (B2B/B2C), and exemption
  certificate IDs if any. Returns a normalised `Calculation.t()` with
  per-line tax amounts, totals, and the jurisdictions that contributed.
  """
  @callback calculate(request :: Calculation.Request.t(), options :: keyword()) ::
              {:ok, Calculation.t()} | {:error, term()}

  @doc """
  Records a finalised transaction with the provider for filing/audit.
  Callers should `calculate/2` first, present the total to the customer,
  then `commit/2` once payment is confirmed. Returns the provider's
  transaction reference for reconciliation.
  """
  @callback commit(transaction :: Transaction.t(), options :: keyword()) ::
              {:ok, %{provider_id: String.t(), recorded_at: DateTime.t()}}
              | {:error, term()}

  @doc """
  Voids or refunds a previously-committed transaction. For partial
  refunds, the caller passes the refund amounts; the provider voids
  proportionally.
  """
  @callback void(provider_id :: String.t(), options :: keyword()) ::
              {:ok, %{voided_at: DateTime.t()}} | {:error, term()}

  @optional_callbacks rate_for_address: 2,
                      calculate: 2,
                      commit: 2,
                      void: 2
end
```

`rate_for/2` — country-level lookup; trivial; the snapshot-rate dataset (Layer 2) implements this for shipped territories.

`rate_for_address/2` — sub-national rate lookup; needs a real address with city/postal code. Used for "what's the right rate to display next to this price for a customer at this address?" Cheap to call (often free-tier on commercial providers).

`calculate/2` — full line-item tax computation for a transaction in flight (cart/checkout). This is the "real" tax calculation: per-line tax, jurisdictions contributing, exemptions applied. Where the legal correctness lives.

`commit/2` — records the finalised transaction with the provider for filing/audit purposes. Required by Avalara's filing service and TaxJar's SmartCalcs; optional with Stripe Tax (Stripe records automatically when the underlying invoice/payment is created).

`void/2` — voids/refunds for accurate filing. Required to keep provider records aligned with actual fulfilment.

Default implementations shipped in `money_tax`:

* `Money.Tax.Source.Snapshot` — reads from the bundled rate dataset (Layer 2). Covers `rate_for/2` only. Suitable for display purposes where the standard rate is "good enough".
* `Money.Tax.Source.Static` — accepts a fixed `%{territory => rate}` map at compile/configuration time. Covers `rate_for/2` only. Useful for tests and small projects with hard-coded rates.

Production provider implementations (Layer 4) implement the full surface.

### Layer 4 — production provider clients

#### Hex.pm prior-art survey (May 2026)

Before designing Layer 4 in detail, surveyed hex.pm for actively-maintained Elixir clients to each of the three target providers:

| Provider | Existing Hex packages | Latest release | Coverage | Verdict |
|----------|----------------------|----------------|----------|---------|
| **TaxJar** | `tax_jar` (v0.3.0) | May 2024 | Only `POST /taxes` (calculate). No `/transactions/orders` (commit), no `/rates`, no void. Solo-maintained, 0 stars, no activity since release. | Build our own. The existing package is incomplete (missing 3 of the 4 behaviour callbacks) and effectively unmaintained. |
| **TaxJar (alternates)** | `ex_taxjar` (v0.5.0, Apr 2018), `taxjar` (v0.1.1, Nov 2017) | 2017–2018 | Both abandoned. | Skip. |
| **Avalara** | None | — | — | Build our own. No prior art to defer to or build on; this is genuinely missing infrastructure in the Elixir ecosystem. |
| **Stripe (incl. Stripe Tax)** | `stripity_stripe` (v3.3.1) | May 2026 | Full Stripe API surface; actively maintained (5.7M downloads); Stripe Tax endpoints exposed. | Wrap `stripity_stripe`, don't re-implement Stripe HTTP. Saves work and benefits from upstream maintenance. |

Net effect on Layer 4 design:

* **`Money.Tax.Source.TaxJar`** and **`Money.Tax.Source.Avalara`** — build directly on `Req`. We own the HTTP, the auth, the error normalisation, the retry logic. Same shape for both for code-reuse.
* **`Money.Tax.Source.StripeTax`** — depends on `stripity_stripe` (added as an *optional* dep so users who don't use Stripe don't pull it in). Translates the normalised `Money.Tax.*` request structs into `stripity_stripe`'s call shape, calls Stripe via the existing client, and normalises the response back. Avoids duplicating Stripe's API-versioning, idempotency, and retry semantics — those are `stripity_stripe`'s job.

#### Common scaffolding

All three providers share the `Money.Tax.*` request/response structs, error normalisation, and Telemetry events. Users opt in via configuration:

```elixir
# config/runtime.exs
config :money_tax, :source, Money.Tax.Source.TaxJar
config :money_tax, Money.Tax.Source.TaxJar,
  api_key: System.get_env("TAXJAR_API_KEY"),
  environment: :production    # or :sandbox
```

Each provider module:

* Uses `Req` for HTTP (no extra deps; modern Elixir convention).
* Reads credentials from app config / env, never from Application code.
* Supports `:sandbox` / `:production` switch; `:sandbox` points at the provider's test endpoint and uses test API keys.
* Maps from the normalised `Calculation.Request.t()` to the provider's wire format on input, and from the provider's response back to `Calculation.t()` on output.
* Normalises every provider error into one of: `{:error, %Money.Tax.AuthError{}}`, `{:error, %Money.Tax.RateLimitError{retry_after: s}}`, `{:error, %Money.Tax.ProviderError{provider: :taxjar, code: code, message: msg}}`, `{:error, %Money.Tax.ValidationError{field: field, message: msg}}`.
* Logs request/response (with secrets redacted) at `:debug`; errors at `:warning`.
* Supports retry on transient 5xx and 429 with exponential backoff; one retry budget by default (configurable).
* Exposes circuit-breaker hooks via the standard `Telemetry` events (`[:money_tax, :request, :start | :stop | :exception]`) so the host app can wire `:fuse`-style breakers without the library taking that dep.

#### Provider matrix

| Provider | Coverage | `rate_for_address/2` | `calculate/2` | `commit/2` | `void/2` | Filing service | Auth |
|----------|----------|-----------|----------------|---------------|----------------|----------------|------|
| **TaxJar** | US/CA/AU/EU + 10+ countries | ✓ | ✓ | ✓ (records to API) | ✓ | Yes (TaxJar Filing) | Bearer token |
| **Avalara AvaTax** | Global, 14,000+ jurisdictions | ✓ | ✓ | ✓ (commit-on-create flag) | ✓ | Yes (Avalara Returns) | Account ID + license key |
| **Stripe Tax** | 50+ countries | ✓ | ✓ | Implicit (when Invoice/Checkout commits) | Implicit | Limited (Stripe Tax filings, US-only currently) | Stripe secret key |

Coverage notes (subject to provider plan tier; users should verify against their contract):
* TaxJar excels at US sales tax; weaker outside the supported regions.
* Avalara is the most expansive but has the steepest API and strictest data requirements (every line item needs a tax-code classification).
* Stripe Tax is simplest to wire if the project already uses Stripe for payments; coupling to Stripe is the trade-off.

#### Module shape (common to all three)

```elixir
defmodule Money.Tax.Source.TaxJar do
  @behaviour Money.Tax.Source

  @impl true
  def rate_for(territory, options \\ [])

  @impl true
  def rate_for_address(%Localize.Address{} = address, options \\ [])

  @impl true
  def calculate(%Money.Tax.Calculation.Request{} = request, options \\ [])

  @impl true
  def commit(%Money.Tax.Transaction{} = transaction, options \\ [])

  @impl true
  def void(provider_id, options \\ []) when is_binary(provider_id)

  # Public — exposed for users who want to pass through to provider-specific
  # endpoints not covered by the behaviour.
  def request(method, path, body \\ nil, options \\ [])
end
```

`request/4` is a deliberate escape hatch — the behaviour covers ~90% of what users need, but the long tail of provider-specific endpoints (TaxJar's `summary_rates`, Avalara's `companies`, Stripe's `tax_settings`) gets a typed but uninterpreted passthrough so users aren't forced to bypass the library entirely for one-off calls.

#### Per-provider notes

**`Money.Tax.Source.TaxJar`** — base URL `https://api.taxjar.com/v2/`. The endpoints we wrap:

* `GET /rates/{zip}?country={iso}` for `rate_for_address/2` (fast, free-tier eligible).
* `POST /taxes` for `calculate/2`.
* `POST /transactions/orders` for `commit/2` (records the transaction; required for TaxJar Filing).
* `DELETE /transactions/orders/{id}` for `void/2`.

The mapping from `Money.Tax.Calculation.Request.t()` → TaxJar's `from_*` / `to_*` / `line_items[]` shape is direct. Money amounts are sent as strings (TaxJar accepts string-encoded decimals to avoid float precision loss).

**`Money.Tax.Source.Avalara`** — base URL `https://rest.avatax.com/api/v2/` (production) or `https://sandbox-rest.avatax.com/api/v2/` (sandbox). The endpoints:

* `POST /transactions/createoradjust` with `commit: false` for `calculate/2` (Avalara folds calc + commit into one endpoint via the flag).
* `POST /transactions/createoradjust` with `commit: true` (and the same idempotency code) for `commit/2`.
* `POST /companies/{companyCode}/transactions/{transactionCode}/void` for `void/2`.
* `GET /taxratesbyzipcode/download` for sub-national rate lookup (`rate_for_address/2`); Avalara also has `GET /addresses/resolve` for address validation we pass through to `Localize.Address` rather than re-implement.

The Avalara client must support the `companyCode` config — Avalara accounts can have multiple companies, each with its own filing entity. Default to a single-company configuration for simplicity; document multi-company override per-call via options.

Avalara requires every line item to carry a `taxCode` (their product classification — `P0000000` is the generic taxable goods code). The `Calculation.Request.LineItem.t()` struct accepts an optional `:tax_code` field that maps to this; if omitted, falls back to the configured default per the app config.

**`Money.Tax.Source.StripeTax`** — depends on `stripity_stripe` (~> 3.3) as an **optional** dep. Users who configure this provider must add `stripity_stripe` to their own `mix.exs`; users who don't use Stripe Tax pay no compile or runtime cost.

Two distinct Stripe Tax call patterns; we model both:

1. **Standalone tax calculation** for `calculate/2`. Calls `Stripe.Tax.Calculation.create/1,2` (the `stripity_stripe` wrapper around `POST /tax/calculations`). Returns a `Stripe.Tax.Calculation` object with per-line tax amounts; no transaction is created on Stripe's side until promoted to a Transaction.
2. **Implicit calculation** via Stripe Invoices / Checkout Sessions / Payment Links with `automatic_tax: { enabled: true }`. Stripe applies tax automatically when the invoice/session is finalised. Users on this path don't call `calculate/2` directly — they create the Invoice/Session with `automatic_tax` enabled and Stripe handles everything. The module @doc documents this trade-off prominently with a worked example that calls `Stripe.Invoice.create/1` with the auto-tax flag.

`commit/2` for Stripe Tax maps to `Stripe.Tax.Transaction.create_from_calculation/1,2` (`POST /tax/transactions/create_from_calculation`) — promotes a Calculation to a Transaction so it appears in Stripe's tax filing reports.

`void/2` maps to `Stripe.Tax.Transaction.create_reversal/1,2` (`POST /tax/transactions/{id}/create_reversal`).

Idempotency, retry, and `Retry-After` handling all flow through `stripity_stripe`'s native machinery — we don't reimplement them. The `Money.Tax.*` error structs are populated from `stripity_stripe`'s error responses via a small mapping helper.

The wrap-`stripity_stripe` decision is reversible: if `stripity_stripe` ever stops being actively maintained or its abstractions get in the way, swapping to direct `Req`-against-Stripe is mechanical (same wire format, same auth) and contained to this single module. The dependency tradeoff is worth it as long as `stripity_stripe` stays healthy (5.7M downloads and a May 2026 release suggest it will).

#### Normalised request/response structs

```elixir
defmodule Money.Tax.Calculation.Request do
  @type t :: %__MODULE__{
          ship_from: Localize.Address.t(),
          ship_to: Localize.Address.t(),
          line_items: [LineItem.t()],
          shipping: Money.t() | nil,
          customer_type: :b2c | :b2b,
          customer_tax_id: String.t() | nil,         # for B2B reverse-charge
          exemption_certificate_id: String.t() | nil,
          currency: atom(),
          transaction_date: Date.t() | nil           # defaults to today
        }
  defstruct [:ship_from, :ship_to, :line_items, :shipping,
             customer_type: :b2c, currency: nil,
             customer_tax_id: nil, exemption_certificate_id: nil,
             transaction_date: nil]
end

defmodule Money.Tax.Calculation.Request.LineItem do
  @type t :: %__MODULE__{
          id: String.t(),                            # caller-supplied; passed back in the response
          unit_price: Money.t(),
          quantity: pos_integer(),
          tax_code: String.t() | nil,                # provider-specific product classification
          discount: Money.t() | nil
        }
  defstruct [:id, :unit_price, :quantity, :tax_code, :discount]
end

defmodule Money.Tax.Calculation do
  @type t :: %__MODULE__{
          line_items: [LineItemResult.t()],
          subtotal: Money.t(),
          shipping_tax: Money.t() | nil,
          total_tax: Money.t(),
          total: Money.t(),
          jurisdictions: [Jurisdiction.t()],
          provider: atom(),
          provider_id: String.t() | nil,
          calculated_at: DateTime.t()
        }
  defstruct [:line_items, :subtotal, :shipping_tax, :total_tax, :total,
             :jurisdictions, :provider, :provider_id, :calculated_at]
end

defmodule Money.Tax.Calculation.LineItemResult do
  @type t :: %__MODULE__{
          id: String.t(),
          taxable_amount: Money.t(),
          tax_amount: Money.t(),
          rate: Decimal.t(),
          jurisdictions: [Jurisdiction.t()],         # may be empty if provider doesn't break down per-line
          exempt: boolean(),
          exemption_reason: String.t() | nil
        }
  defstruct [:id, :taxable_amount, :tax_amount, :rate, :jurisdictions,
             exempt: false, exemption_reason: nil]
end

defmodule Money.Tax.Jurisdiction do
  @type t :: %__MODULE__{
          name: String.t(),                          # "California", "Los Angeles County", "Special District"
          kind: :country | :state | :county | :city | :special,
          rate: Decimal.t(),
          tax: Money.t()
        }
  defstruct [:name, :kind, :rate, :tax]
end

defmodule Money.Tax.Transaction do
  # Same shape as Calculation, but carries the provider's transaction reference
  # for void/2 and the timestamp the customer paid.
  @type t :: %__MODULE__{
          calculation: Money.Tax.Calculation.t(),
          provider_id: String.t(),
          paid_at: DateTime.t(),
          metadata: map()
        }
  defstruct [:calculation, :provider_id, :paid_at, metadata: %{}]
end
```

These structs are the public Elixir surface; provider modules translate to/from each provider's wire format internally. Adding a new provider in the future means writing a new module that implements the behaviour and maps to its native shape — no changes needed in user code.

#### Telemetry events

Every provider call emits Telemetry events on a consistent name space:

* `[:money_tax, :request, :start]` — measurements `%{system_time: ...}`, metadata `%{provider: :taxjar, operation: :calculate, request_id: ref}`
* `[:money_tax, :request, :stop]` — measurements `%{duration: ns}`, metadata adds `%{status: :ok | :error}`
* `[:money_tax, :request, :exception]` — for unhandled errors; standard exception metadata

This lets the host app instrument tax-API latency and error rates without the library opining on what monitoring stack to use.

#### Sandbox / test discipline

Each provider supports a `:sandbox` environment with its own credentials and base URL. Recommended pattern in `config/test.exs`:

```elixir
config :money_tax, :source, Money.Tax.Source.Static    # for unit tests, no network
config :money_tax, Money.Tax.Source.Static, %{US: Decimal.new("0.0875")}    # rough CA-equivalent
```

For integration tests against real provider sandboxes (gated behind `MONEY_TAX_RUN_LIVE_TESTS=1`), each provider has a `Money.Tax.Source.Provider.SandboxFixtures` helper that seeds the sandbox account with predictable customers/products at test-suite startup so tests are deterministic against the real API.

#### Mock-friendly testing for users

`money_tax` ships a `Money.Tax.Source.Mock` module (using the standard `Mox`-compatible behaviour pattern) so user applications can mock out provider calls in their own tests:

```elixir
# user's test_helper.exs
Mox.defmock(MyApp.MockTaxSource, for: Money.Tax.Source)
Application.put_env(:money_tax, :source, MyApp.MockTaxSource)

# user's test
test "checkout includes tax for California address" do
  expect(MyApp.MockTaxSource, :calculate, fn _request, _opts ->
    {:ok, %Money.Tax.Calculation{total_tax: Money.new(:USD, "8.75"), …}}
  end)

  assert {:ok, response} = MyApp.Checkout.compute(cart_with_ca_shipping())
  assert response.tax == Money.new(:USD, "8.75")
end
```

This is the same pattern Stripe-the-library, Tesla, and other API-client libraries use; users will recognise it immediately.

## Public API

```elixir
defmodule Money.Tax do
  @doc """
  Returns the tax label data for a territory.

  Used by `Money.Tax.to_inclusive_string/3` and `to_exclusive_string/3` to
  render display strings. Pure label lookup — does not query rates.
  """
  @spec label(territory :: atom(), Keyword.t()) ::
          {:ok, %{kind: atom(), abbreviation: String.t(), full_name: String.t(), …}}
          | {:error, :unknown_territory}
  def label(territory, options \\ [])

  @doc """
  Returns the snapshot standard rate for a territory.

  Result includes `:as_of` so callers can decide whether the snapshot is
  fresh enough. For US/CA/BR/AR returns the country-level rate only;
  use a `Money.Tax.Source` implementation that supports
  `rate_for_address/2` for sub-national rates.
  """
  @spec standard_rate(territory :: atom(), Keyword.t()) ::
          {:ok, %{rate: Decimal.t(), as_of: Date.t(), …}}
          | {:error, :unknown_territory | :no_rate}
  def standard_rate(territory, options \\ [])

  @doc """
  Renders a money value with a tax-inclusive label.

  Picks the locale-appropriate phrase ("incl. VAT", "TTC", "税込")
  for the territory derived from the locale. Forwards remaining
  options to `Money.to_string/2`.
  """
  @spec to_inclusive_string(Money.t(), Keyword.t()) ::
          {:ok, String.t()} | {:error, term()}
  def to_inclusive_string(money, options \\ [])

  @doc """
  Renders a money value with a tax-exclusive label ("+ VAT" / "+ tax").

  For territories whose convention is tax-inclusive prices (most of
  EU/UK/AU/JP), this still renders correctly but is rarely the right
  choice for consumer-facing display. Use `to_inclusive_string/2`
  by default in those territories.
  """
  @spec to_exclusive_string(Money.t(), Keyword.t()) ::
          {:ok, String.t()} | {:error, term()}
  def to_exclusive_string(money, options \\ [])

  @doc """
  Renders a money value with the territory's default tax-label
  convention.

  Looks up the territory's `inclusive_default` flag from the label
  dataset and picks `to_inclusive_string/2` or `to_exclusive_string/2`
  accordingly. The right default for "I just want to display this
  price for a customer in this territory."
  """
  @spec to_string(Money.t(), Keyword.t()) ::
          {:ok, String.t()} | {:error, term()}
  def to_string(money, options \\ [])
end
```

### Worked examples

```elixir
iex> Money.Tax.to_inclusive_string(Money.new(:GBP, 20), locale: "en-GB")
{:ok, "£20.00 incl. VAT"}

iex> Money.Tax.to_inclusive_string(Money.new(:EUR, 20), locale: "fr-FR")
{:ok, "20,00 € TTC"}

iex> Money.Tax.to_inclusive_string(Money.new(:JPY, 1200), locale: "ja-JP")
{:ok, "¥1,200 税込"}

iex> Money.Tax.to_exclusive_string(Money.new(:USD, 20), locale: "en-US")
{:ok, "$20.00 + tax"}

iex> Money.Tax.to_string(Money.new(:GBP, 20), locale: "en-GB")
{:ok, "£20.00 incl. VAT"}    # GB defaults to inclusive

iex> Money.Tax.to_string(Money.new(:USD, 20), locale: "en-US")
{:ok, "$20.00 + tax"}        # US defaults to exclusive

iex> Money.Tax.label(:DE)
{:ok, %{kind: :vat, abbreviation: "MwSt", inclusive_phrase_en: "incl. VAT", …}}

iex> Money.Tax.standard_rate(:GB)
{:ok, %{rate: Decimal.new("0.20"), as_of: ~D[2025-04-01], source: :tedb}}

iex> Money.Tax.standard_rate(:US)
{:error, :no_country_level_rate}    # US has no nationwide rate
```

The `:as_of` date is always returned and is the caller's responsibility to act on.

## Refresh tooling

A `mix money_tax.refresh` task pulls the latest TEDB data and regenerates `priv/money_tax/rates.etf`. Output:

```
$ mix money_tax.refresh
Pulling EU TEDB rates (28 territories)... ok
Pulling UK HMRC rate (GB)... ok
Pulling NO Skatteetaten rate (NO)... ok
Pulling CH ESTV rate (CH)... ok
Manually-curated territories (~150) — skipped (refresh by editing priv/money_tax/manual_rates.exs)
Wrote priv/money_tax/rates.etf (as_of: 2026-05-15)
```

Manually-curated rates live in a hand-edited Elixir file (`priv/money_tax/manual_rates.exs`) committed to the repo; the mix task reads it, merges with TEDB output, and emits the ETF. This keeps rare manual changes (a single-rate country bumps from 7% to 7.5%) lightweight and auditable.

The mix task ships in the published package so users can run it themselves if they're between releases. Standard cadence: maintainers run it quarterly; a CI job optionally cron-runs it and opens a PR if rates have changed.

## Composition with existing Money APIs

Important non-goal: do **not** modify the core `Money.to_string/2` to know about taxes. The tax functions are an opt-in *surface* that takes a `Money.t()` and produces a *labelled* string. This keeps `Money` itself tax-free (apt, given the criticism).

Composition with `Money.to_range_string/3` (the other planned addition):

```elixir
{:ok, range_string} = Money.to_range_string(Money.new(:GBP, 20), Money.new(:GBP, 40), locale: "en-GB")
# => "£20.00–40.00"

# Add the tax label by post-processing — or define Money.Tax.to_inclusive_range_string/3 if this becomes common
"#{range_string} incl. VAT"
```

If the range-with-tax composite proves common in practice, ship `Money.Tax.to_inclusive_range_string/3` and `to_exclusive_range_string/3` as composite formatters. Defer to user demand; the manual concatenation is fine for now.

Composition with `Localize.Address` (where `:rate_for_address/2` is implemented by a third-party `Money.Tax.Source`):

```elixir
{:ok, address} = Localize.Address.parse("123 Main St, San Francisco, CA 94105, US")
{:ok, %{rate: rate, jurisdiction: jur}} =
  MyApp.TaxJarSource.rate_for_address(address)
# rate combines CA state + SF county + special districts
```

The library defines the seam; the user wires the production tax service in.

## Testing

* **Unit tests**: label lookup for ~30 representative territories; rate lookup for the same; error cases (`:unknown_territory`, US country-level lookup); the `to_string/2` default-convention dispatch (GB → inclusive, US → exclusive).
* **Snapshot tests**: golden-file tests of the formatted output for ~10 representative locales (en-GB, fr-FR, de-DE, ja-JP, en-US, en-AU, en-CA, ar-SA, ko-KR, pt-BR). Detects unexpected drift in the label dataset.
* **Refresh-task tests**: mock the TEDB API, verify the ETF generation handles the response shape and the merge with manual-rates is correct.
* **Property tests**: for any territory in the label dataset, both `to_inclusive_string/2` and `to_exclusive_string/2` produce non-empty strings and `Localize.Message.parse/1`-clean strings (no accidental MF2-syntax injection from the label data).

Integration tests against the real TEDB API gated on `MONEY_TAX_RUN_LIVE_TESTS=1` and run nightly in CI on a separate workflow that's allowed to be flaky (the API is mostly reliable but we don't want it blocking PRs).

## Documentation discipline

Every public function's @doc must include:

1. The **scope-boundary statement**: "This function returns display data only. For computing tax owed, use a `Money.Tax.Source` implementation that integrates with an authoritative tax-calculation service."
2. The `:as_of` semantics: when the function returns a rate, surface the date.
3. A worked example.

The README must lead with the scope-boundary statement before any code example. The package's hex.pm description must include "tax label and rate display" — not "tax calculation" — to set expectations at the package-discovery layer.

## Open questions

* **Territory derivation from locale.** A user-supplied `locale: "en-GB"` clearly maps to `:GB`. But `locale: "en"` doesn't carry a territory; we'd need to fall back to either an explicit `:territory` option or refuse the call. Recommendation: require either an explicit `:territory` option OR a locale with a territory subtag for any tax-display call; raise informatively otherwise.

* **Reduced-rate display.** Should `to_inclusive_string/2` accept a `:rate_kind` option (`:standard` / `:reduced` / `:zero`) to surface "incl. VAT (5%)" vs "incl. VAT (20%)" for product categories with reduced rates? Adds complexity but is a real e-commerce need (children's books in the UK, restaurant food in France). Likely yes; defer to Phase 2.

* **B2B vs B2C display.** EU B2B prices are typically shown tax-exclusive; B2C inclusive. The current API picks one default per territory; doesn't distinguish customer type. A `:customer_type` option (`:b2c` default, `:b2b`) is a small addition. Defer until requested.

* **Reverse-charge / zero-rated B2B EU export rendering.** "VAT 0% (reverse charge)" — specialised invoice text that may be out of scope for `money_tax`. Defer.

* **Territory data licensing.** TEDB is an EU government work, freely usable. Wikipedia is CC BY-SA — using it as a *source* for a curated dataset is fine; mirroring its tables verbatim in code is also fine with attribution. Add a NOTICE file listing source attribution.

* **US sales tax shipping a "best-effort" state-level rate.** Risk: a user reads the rate, doesn't realise it doesn't include county+city, displays it incorrectly. Mitigation: for US, return `{:error, :no_country_level_rate}` from `standard_rate(:US)` and document explicitly that US sub-national lookup needs a `Money.Tax.Source.rate_for_address/2` provider. Better to refuse than to mislead.

* **Provider clients in `money_tax` core vs split packages.** Bundling all three into `money_tax` makes them easy to discover and configure but commits the maintainer to keeping all three current. Splitting into `money_tax_taxjar` / `money_tax_avalara` / `money_tax_stripe` lets each evolve independently and makes the dependency graph honest (a project using only TaxJar shouldn't have to compile Avalara client code). Recommendation: ship Phase 1–3 in `money_tax` (no provider-specific code), ship Phase 4a–4c bundled in the same package on first release for easier UX, and split out into separate packages later if/when they grow beyond ~500 LOC each or develop divergent dependency footprints.

* **HTTP client choice (`Req` vs `Tesla` vs `Finch`)**. For TaxJar and Avalara — which we own end-to-end — `Req` (which depends on Finch) is the modern Elixir convention, has built-in retry/redirect/JSON, and is already in widespread use. Tesla is older but more flexible (middleware-style). Recommendation: `Req` for simplicity. If a user needs different transport semantics (e.g. their own connection pool), the per-provider `request/4` escape hatch lets them override. For Stripe Tax we don't make this choice — `stripity_stripe` brings its own HTTP layer (currently `hackney` via `httpoison`).

* **Idempotency-key generation**. Avalara and Stripe Tax both require idempotency keys for transaction commit. Should the library auto-generate (UUID v4) or require the caller to supply? Auto-generation is friendlier; caller-supplied is safer for distributed systems (the same logical transaction commits across retries). Recommendation: caller-supplied via `:idempotency_key` option, default to UUID v4 if omitted; document the trade-off in the @doc.

* **Currency mismatches between request and provider account**. Each provider account has a base currency configured at signup; sending a transaction in a different currency may either be rejected or silently converted by the provider. Recommendation: validate that all line items in a `Calculation.Request.t()` share a currency, error early on mismatch, and document that the request currency must match the provider account's configured currency.

* **PCI / data-sensitivity review**. None of the request/response shapes in Layer 4 carry payment instruments — only addresses and amounts — so PCI scope is minimal. Confirm with each provider's terms-of-service that we're not accidentally creating a PCI-impacting integration via headers or metadata fields.

* **Rate caching at the library layer**. `rate_for_address/2` for static-address-static-line-item combinations is a candidate for ETS caching with a short TTL (~1 hour) to reduce API call volume. Risk: cache staleness around tax-rate changes (typically announced weeks in advance, but a discontinuity is possible). Defer until users ask; document that the calling layer is the right place to cache.

## Phasing

| Phase | Scope | Estimate | Blocking |
|-------|-------|----------|----------|
| 1 | Layer 1 (label dataset for ~200 territories), `Money.Tax.label/2`, `to_inclusive_string/2`, `to_exclusive_string/2`, `to_string/2`. README with scope-boundary statement. | 1 week | none |
| 2 | Layer 2 (snapshot rate dataset), `Money.Tax.standard_rate/2`, `mix money_tax.refresh` task pulling TEDB. Reduced-rate display (`:rate_kind` option). | 1–2 weeks | Phase 1 |
| 3 | Layer 3 (`Money.Tax.Source` behaviour with all callbacks), `Snapshot` and `Static` default implementations covering `rate_for/2` only. Normalised `Calculation.Request.t()` / `Calculation.t()` / `Transaction.t()` / `Jurisdiction.t()` structs. Telemetry event names defined. | 1 week | Phase 2 |
| 4a | `Money.Tax.Source.TaxJar` — full behaviour implementation (rate, calculate, commit, void), sandbox/production switch, error normalisation, retry, telemetry. | 1 week | Phase 3 |
| 4b | `Money.Tax.Source.Avalara` — same scope as 4a, plus `companyCode` configuration, default `taxCode` handling, address-resolve passthrough. | 1.5 weeks | Phase 3 |
| 4c | `Money.Tax.Source.StripeTax` — wraps `stripity_stripe` (optional dep); thin translation layer between `Money.Tax.*` structs and Stripe's call shape. Documentation of the implicit-vs-standalone calculation distinction and the `automatic_tax` Invoice path. Smaller than 4a/4b because we don't own HTTP/auth/retry/idempotency. | 0.5 weeks | Phase 3 |
| 4d | `Money.Tax.Source.Mock` (Mox-compatible), per-provider sandbox-fixture helpers for integration tests, README provider-comparison guide. | 0.5 weeks | Phases 4a–4c |
| 5 | Range composites (`Money.Tax.to_inclusive_range_string/3`), B2B/B2C distinction in display formatters, end-to-end address-driven sub-national lookup demo using one of the providers. | 1 week | Phases 1–4 + `Money.to_range_string/3` |

Total: ~7–9 weeks for the full library across all five phases. Phase 1 alone is shippable and closes the e-commerce display requirement (T1, T2 in [e_commerce.md](../../localize/localize/plans/e_commerce.md)) without any rate-data or provider-API maintenance burden. Phase 3 unlocks the provider seam without requiring the library to ship any provider client. Phases 4a–4c are independent of each other; can ship in any order or skip entirely if the maintainer decides not to take on provider-client maintenance.

**Provider-client maintenance disclosure**: shipping production HTTP clients commits to keeping them aligned with provider API changes.

* **TaxJar** (Phase 4a): we own the full HTTP stack. API is stable (versioned, slow-changing). Ongoing cost ~1 day per year. The hex.pm survey above showed the existing `tax_jar` package covers only 1 of 4 behaviour callbacks and is unmaintained — there is no upstream client to lean on, so we take the maintenance ourselves. Real ecosystem value: this becomes the de-facto Elixir TaxJar client.
* **Avalara** (Phase 4b): we own the full HTTP stack. API is well-versioned but has more endpoints than TaxJar. Ongoing cost ~1 day per year, plus the larger one-time build (1.5 weeks). No prior Elixir client exists at all (zero packages on hex.pm) — substantial ecosystem-value win.
* **Stripe Tax** (Phase 4c): we depend on `stripity_stripe` (3.3.1, May 2026, 5.7M downloads, actively maintained) as an optional dep. Routine Stripe API-version migrations are absorbed by `stripity_stripe`; our maintenance is limited to the thin translation layer between the normalised `Money.Tax.*` structs and Stripe's call shape. Ongoing cost: minimal, ~half a day per year unless Stripe Tax adds new top-level endpoints.

If even this maintenance is a concern, ship Phases 1–3 only and document the behaviour as the contract — third parties can then publish provider clients as separate Hex packages (`money_tax_taxjar`, `money_tax_avalara`) without `money_tax` itself taking on the maintenance. Stripe Tax users can wire `stripity_stripe` directly via a small inline implementation of `Money.Tax.Source` in their own application, since the wrapping is thin.

## Change log for this plan

* 2026-05-15 — Initial draft. Architecture (3 layers + behaviour), data sources reviewed, API drafted, scope boundary stated.
