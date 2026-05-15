# `money_input` — localizable number and money form input with Phoenix LiveView component

**Status:** planning, last updated 2026-05-15

**Owner:** Money maintainers

**Companion plans:**

* [~/Development/localize/localize/plans/e_commerce.md](../../localize/localize/plans/e_commerce.md) — flagged number/money input as a major missing UX primitive.
* [~/Development/localize/localize_address/plans/localize_address_input.md](../../localize/localize_address/plans/localize_address_input.md) — same three-layer architecture, same Phoenix-optional posture.
* [~/Development/localize/localize_phonenumber/plans/localize_phonenumber_input.md](../../localize/localize_phonenumber/plans/localize_phonenumber_input.md) — sibling pattern; same as-you-type formatting trade-off.

## Why this is the hardest input problem in i18n

Number and money input are notoriously easy to get wrong. The canonical pitfalls, every one of which costs a real e-commerce site UX lawsuits and abandoned carts:

1. **Decimal/grouping separator confusion across locales:**
   * en-US: `1,234.56` (comma thousands, period decimal)
   * de-DE / pt-BR: `1.234,56` (period thousands, comma decimal — *swapped*)
   * fr-FR: `1 234,56` (NBSP thousands, comma decimal)
   * de-CH: `1'234.56` (apostrophe thousands, period decimal)
   * en-IN: `1,23,456.78` (Indian numbering — lakh/crore grouping, not 3-digit)
   * ar (Arabic-Indic digits): `١٬٢٣٤٫٥٦` (U+066B/U+066C separators, U+0660-0669 digits)
   * fa-IR (Persian digits): `۱٬۲۳۴٫۵۶` (U+06F0-06F9 digits)

2. **Native `<input type="number">` is unreliable.** Browsers' decimal handling is locale-blind in unpredictable ways, the spinner is rarely wanted, mobile keyboards are inconsistent, and the `value` attribute always uses period-as-decimal regardless of display. Most production finance UIs avoid it entirely in favour of `<input type="text" inputmode="decimal">`.

3. **As-you-type formatting destroys cursor position** when implemented naively. User types `1234`, formatter inserts thousands separator producing `1,234`, cursor jumps. Critical for finance UX where users routinely type 6+ digit values.

4. **Currency-symbol position varies dramatically:**
   * en-US: `$123.45` (prefix, no space)
   * en-GB: `£123.45` (prefix, no space)
   * fr-FR: `123,45 €` (suffix, NBSP)
   * de-CH (CHF): `CHF 123.45` (ISO prefix, space)
   * ja-JP: `¥123` (prefix, no space, no decimals)
   * ar-SA: `١٢٣٫٤٥ ر.س.` (suffix, RTL)

5. **Decimal precision varies by currency**, not locale: JPY 0 digits, USD 2, BHD 3, CLF 4. The input must respect the *currency's* exponent, not the locale's preference.

6. **Negative-number conventions split**: `-123.45` (most), `(123.45)` (accounting), `123.45-` (some legacy systems). Pick one and document; offer the others as options.

7. **Paste from spreadsheets** routinely contains formatting in a different convention than the user's display locale: a US user pasting from a French colleague's email gets `1 234,56`. Parser must accept this gracefully.

8. **Float storage is wrong.** `0.1 + 0.2 ≠ 0.3` haunts every finance app that uses floats. Storage must be `Decimal` (for plain numbers) or minor units / `Money` (for currency). The input library's job is to bridge the user's text input to one of these without ever touching `Float`.

9. **Currency change mid-input** invalidates digits past the new currency's exponent (USD 12.34 → JPY ?? — round to 12 and warn? truncate to 12? reject?).

10. **Mobile keyboards** must show the right keypad. `inputmode="decimal"` shows the period+comma pad on iOS; `inputmode="numeric"` for integers. `type="number"` is the wrong tool because of point 2.

A library that solves all of these without forcing the user to learn any of them is the goal.

## Components

This package ships three HEEx components that share most of their internals:

* **`<.number_input>`** — locale-aware Decimal input. No currency. Output is a `Decimal.t()` (or integer when `integer: true`). For quantities, percentages, ratings, multipliers — anything that's "just a number".
* **`<.money_input>`** — locale-aware money input. Has a currency (fixed via attr or selectable via the bundled `<.currency_picker>`). Output is a `Money.t()`. Currency-aware precision, currency-aware symbol placement.
* **`<.currency_picker>`** — first-class currency picker with searchable list (by ISO code, currency name, country name, or symbol), flag glyphs, recent-selections memory, and a mobile full-screen sheet variant. Used standalone or composed inside `<.money_input>`. **This is the differentiating component vs every other Elixir money library.**

They share: the JS hook, the server-side parsers (`Localize.Number.Parser.parse/2` and `Money.parse/2`), the cursor-preservation logic, the paste handler, the validation framework, and the RTL handling. The three components are deliberately separate at the public API so users don't have to wrap less-fitting abstractions — but the internals are heavily shared.

### Reference implementations these match or exceed

The component set is benchmarked against the two industry-leading implementations that define the bar for localizable single-currency money input:

* **Stripe Checkout** — single-currency entry in a payment context: locale-aware formatting (commas vs periods, symbol placement), automatic thousand separators as you type, proper mobile keyboards. Matched by `<.money_input>` with `currency:` fixed.
* **Wise (formerly TransferWise) — the input and picker, not the FX flow** — large numeric input, flag-and-code currency picker that's searchable by country name or currency code, strong mobile experience. Matched by `<.money_input>` + `<.currency_picker>`. We're explicitly *not* shipping Wise's paired send/receive FX flow — that's a remittance-app feature outside this package's scope.

The Wise FX flow (paired bidirectional inputs with live exchange-rate conversion) is intentionally out of scope. If a downstream user wants it, they can compose two `<.money_input>` components and wire their own rate provider in their LiveView's `handle_event/3` — the components support this without further library work.

Specific UX features lifted from these benchmarks are flagged inline in the per-component sections below.

## What the existing parsers give us

Both are locale-aware and accept multi-separator-convention input:

* **`Localize.Number.Parser.parse/2`** — already in `Localize`. Takes a string and options (locale, etc.); returns `{:ok, Decimal.t()}` or `{:error, ...}`. Handles thousands/decimal separator inversion across locales.
* **`Money.parse/2`** — already in `Money`. Takes a string with or without currency symbol/code; returns `{:ok, Money.t()}` or `{:error, ...}`. Recognises symbols and ISO codes; defaults the currency from options or the locale.

The input library does **no parsing of its own**. Server-side it forwards to these. Client-side (JS hook) it does *display formatting* only — the source of truth is always the server-side parser.

## Best-practice survey

Patterns observed across major locale-aware finance/commerce inputs:

| Source | Pattern |
|--------|---------|
| **Stripe Elements** (Card, Amount) | `<input type="text" inputmode="decimal">`. Amount Element handles minor-unit conversion internally. Live formatting via small JS, cursor-preserving. Display is always pretty; storage is always minor units. |
| **Shopify storefront price input** | Text input; format on blur; right-aligned; symbol as left adornment outside the input. Currency selector as separate `<select>`. |
| **Wise (TransferWise) sender amount** | Aggressive live formatting; cursor preservation; currency picker with flag inline; converts to receiver currency in adjacent field on debounced input. |
| **Square POS** | Text input with locale-aware formatting; symbol position respects locale; mobile uses native keypad with the locale's decimal key. |
| **PayPal checkout amount** | Text input with currency dropdown to the left; format on blur only; tolerant paste handler. |
| **AutoNumeric.js** (the de-facto open-source library for this) | Live formatting; per-locale decimal/thousands separators; cursor preservation; paste sanitisation; minor-unit serialisation. ~50 KB minified, MIT licence, actively maintained. The library most production sites use under the hood. |
| **Cleave.js** | Lighter (~15 KB) input-masking library; less feature-complete than AutoNumeric but easier to integrate. |
| **Banking apps generally** | Right-aligned digits; symbol prefix/suffix as adornment (not in input); format on blur; numeric keypad on mobile. |
| **Excel / Google Sheets** | Text input; format applied via cell format string; locale-aware decimal separator following the user's regional settings. The "industrial standard" for what this UX should feel like. |

Cross-pattern conclusions:

* **`<input type="text" inputmode="decimal">`** is the universal substrate. Not `type="number"`.
* **Format on blur** is the minimum acceptable; **format-as-you-type with cursor preservation** is the gold standard. Ship both.
* **Symbol as adornment outside the input**, not inside it. The user shouldn't have to type `$`.
* **Right-align numerals** is universal in finance contexts; left-align is conventional for "just a number" (quantity, count). Default per component differs.
* **Paste handler must be aggressive** about stripping formatting and tolerating any locale's separators.
* **Mobile keyboard discipline**: `inputmode="decimal"` (or `numeric` for integers).

## Architecture

Same three-layer pattern as `localize_address_input` and `localize_phonenumber_input`:

```
                 Localize.Number.Parser     Money.parse
                 (existing — server-side    (existing — server-side
                  authoritative parser)      authoritative parser)
                            │                        │
                            └────────────┬───────────┘
                                         ▼
                ┌────────────────────────────────────────────┐
                │  Money.Input.Parser                        │
                │  * unified front-door for parsing input    │
                │  * dispatches to Number or Money parser    │
                │  * tolerant paste handling                 │
                │  * minor-unit ↔ major-unit conversion      │
                └────────────────────────────────────────────┘
                                         │
                ┌────────────────────────┼────────────────────────┐
                ▼                        ▼                        ▼
        Money.Input.            Money.Input.             Money.Input.
        Validator               Formatter                Locale
        ───────────────         ──────────────           ─────────────
        * server-side check     * format for display     * separator characters
        * range, precision,     * blur formatter         * grouping rules
          required              * Locale-aware           * digit-system
                                                          (Latin/Arabic/Persian)
                                         │
                                         ▼
              Money.Input.LiveComponent + Money.Input.NumberLiveComponent
              ────────────────────────────────────────────────────────────
              * <.number_input form={@form} field={:qty} />
              * <.money_input form={@form} field={:price} currency={:USD} />
              * shared JS hook (priv/static/money_input.js)
              * shared HEEx primitives, separate public components
```

Three layers, increasing optional-ness — Phoenix-optional same as the sibling input libraries:

1. **Headless data + parser/formatter/validator** — pure Elixir, no Phoenix dep. Usable from JSON APIs / non-LiveView projects.
2. **Form helpers** — depends on `phoenix_html` only.
3. **LiveView components + JS hook** — depends on `phoenix_live_view`. The drop-in `<.number_input>` and `<.money_input>` components.

## Native HTML baseline

The base markup the LiveView component renders, before any JS enhancement:

```html
<!-- number input, en-US -->
<div class="money-input-wrapper" data-money-input="number" data-locale="en">
  <input
    type="text"
    inputmode="decimal"
    name="form[quantity]"
    value="1,234.56"
    aria-describedby="form-quantity-help"
    autocomplete="off"
  >
</div>

<!-- money input, en-US, USD -->
<div class="money-input-wrapper" data-money-input="money" data-locale="en" data-currency="USD">
  <span class="money-input-symbol money-input-prefix">$</span>
  <input
    type="text"
    inputmode="decimal"
    name="form[price]"
    value="1,234.56"
    aria-describedby="form-price-help money-input-price-currency"
    autocomplete="off"
  >
  <span id="money-input-price-currency" class="sr-only">US dollars</span>
</div>

<!-- money input, fr-FR, EUR (suffix-position symbol with NBSP) -->
<div class="money-input-wrapper" data-money-input="money" data-locale="fr" data-currency="EUR">
  <input ... value="1 234,56">
  <span class="money-input-symbol money-input-suffix">&nbsp;€</span>
  <span class="sr-only">euros</span>
</div>
```

This baseline works without JS:

* `inputmode="decimal"` shows the right mobile keypad.
* The symbol is rendered as an adornment outside the input, positioned per the locale's currency-symbol convention.
* The hidden screen-reader label gives the currency name in the locale's language.
* `autocomplete="off"` prevents the browser auto-completing prior numeric entries (almost always wrong for amounts).
* `aria-describedby` points at help text and currency name.
* No JS = no live formatting (formatting happens on submit via server-side parsing). Acceptable degradation.

JS hook upgrades this to live formatting + cursor preservation + paste sanitisation.

## JS hook strategy — the critical UX decision

Three paths considered, ordered worst-to-best:

### Path A — server-side via `phx-change` only

Every keystroke fires `phx-change`; server formats; LiveView replaces input value. Latency 100–300ms; cursor jumps; fundamentally laggy.

**Verdict:** unacceptable as the primary path. Acceptable as a JS-disabled fallback because at least the form *works*.

### Path B — wrap AutoNumeric.js

AutoNumeric (`autonumeric` on npm, MIT licence, ~50 KB minified, actively maintained) is the de-facto solution. Provides every feature we need: per-locale separators, cursor preservation, paste handling, minor-unit serialisation, scientific-notation rejection, range enforcement.

**Pros:** battle-tested across thousands of production sites; covers every edge case we'd otherwise re-implement; one upgrade away from new locale support.

**Cons:** 50 KB JS dep; opinionated configuration surface; tight coupling to one library.

### Path C — small custom JS hook (~5–10 KB)

Hand-written JS that does the minimum: format on input event, preserve cursor, sanitise paste. Reads locale separator characters from `data-` attributes set by the server-side render; no per-locale data shipped in JS.

**Pros:** tiny dep; full control; no external upgrade pressure.

**Cons:** weeks of UX bug-tail; cursor preservation is a notorious tar pit; we'll re-discover edge cases AutoNumeric already solved.

**Recommendation: Path B.** Wrap AutoNumeric. The 50 KB cost is justified by the years of UX edge-case work the AutoNumeric maintainers have already done. We add a thin hook that:

1. Reads locale and currency from `data-` attributes the server-side render sets.
2. Constructs the AutoNumeric configuration from those attributes.
3. Subscribes to AutoNumeric's `formatted` event and pushes the parsed `Decimal`/`Money`-compatible string back to LiveView via `pushEvent` (debounced 300ms).
4. On submit, ensures the final value sent to the server is the canonical form (period as decimal, no thousands separators) — AutoNumeric's `getNumber()` returns this directly.

Server-side validation always runs regardless of JS — defence in depth.

The hook ships in `priv/static/money_input.js` and is registered in the user's `assets/js/app.js` via:

```js
import { MoneyInput, NumberInput } from "money_input"
let Hooks = {}
Hooks.MoneyInput = MoneyInput
Hooks.NumberInput = NumberInput
```

The user's `package.json` adds `autonumeric` as a peer dep. We don't bundle it in our priv asset because (a) users may already have it for other reasons and (b) it lets users version-pin independently if needed.

### Fallback discipline

When the hook fails to load (no JS, network issue, CSP blocked AutoNumeric), the form must still work:

* The input value remains visible and editable as text.
* On blur, the server-side `Money.Input.Formatter.format/3` (Path A) reformats the value via `phx-change`.
* On submit, the server-side parser interprets whatever string the user typed.

Document this as the explicit fallback — accessibility-conscious projects can opt for Path A only via `js: false`.

## Public API — number_input

```elixir
attr :form, Phoenix.HTML.Form, required: true
attr :field, :atom, required: true
attr :value, :any, default: nil,
  doc: "Initial value. Accepts Decimal, integer, float, or string. If nil, reads from the form."
attr :locale, :string, default: nil,
  doc: "Locale identifier; defaults to Localize.get_locale/0."
attr :integer, :boolean, default: false,
  doc: "When true, accepts only integer input (no decimal separator); inputmode=numeric."
attr :min, :any, default: nil,
  doc: "Minimum value (any type the parser accepts). Validated server-side; passed to AutoNumeric for client-side enforcement when js: true."
attr :max, :any, default: nil
attr :decimals, :integer, default: nil,
  doc: "Maximum decimal places. Default reads from locale's number-of-fraction-digits."
attr :align, :atom, default: :left, values: [:left, :right, :center],
  doc: "Text alignment within the input. Default :left for plain numbers; :right for tabular contexts."
attr :placeholder, :string, default: nil,
  doc: "Placeholder text. Default uses the locale's example formatting (e.g. '1,234')."
attr :on_change, :string, default: nil
attr :js, :boolean, default: true
attr :class, :string, default: nil
attr :input_class, :string, default: nil
```

Worked example:

```heex
<.number_input form={@form} field={:quantity} integer={true} min={1} max={999} />
<!-- en-US: <input type="text" inputmode="numeric" value="5" min="1" max="999" />  -->
<!-- de-DE: same — integers don't show separators below 1000 -->

<.number_input form={@form} field={:rating} min={0} max={5} decimals={1} />
<!-- en-US: value="4.5" -->
<!-- de-DE: value="4,5" -->
```

## Public API — money_input

```elixir
attr :form, Phoenix.HTML.Form, required: true
attr :field, :atom, required: true
attr :currency, :atom, default: nil,
  doc: "Fixed currency. If nil, currency must be selectable via the :currency_picker slot or be present in the value as a Money.t()."
attr :value, :any, default: nil,
  doc: "Initial value. Accepts Money.t(), Decimal, integer, or string. If nil, reads from the form."
attr :locale, :string, default: nil
attr :min, :any, default: nil
attr :max, :any, default: nil
attr :align, :atom, default: :right,
  doc: "Default :right for money — universal in finance UIs."
attr :symbol_position, :atom, default: :auto, values: [:auto, :prefix, :suffix],
  doc: ":auto follows the locale's currency-position rule. Override with :prefix/:suffix only when designing for a specific layout."
attr :symbol_kind, :atom, default: :symbol, values: [:symbol, :iso, :narrow, :none],
  doc: "Which currency marker to display: :symbol ($), :iso (USD), :narrow ($ for USD but ... see CLDR narrowSymbol data), :none (no marker, just the digits)."
attr :on_change, :string, default: nil
attr :on_currency_change, :string, default: nil,
  doc: "Event fired when the currency picker emits a change."
attr :js, :boolean, default: true
attr :class, :string, default: nil
attr :input_class, :string, default: nil
attr :symbol_class, :string, default: nil

attr :currency_picker, :boolean, default: false,
  doc: "When true, embeds the bundled <.currency_picker> as the symbol adornment. Currency change events fire `on_currency_change`. Use the :currency_picker slot for a custom picker."

attr :allowed_currencies, :list, default: nil,
  doc: "When :currency_picker is true, restrict the picker to these currencies (e.g. for service-area limits). Default: Money.known_currencies/0."

attr :preferred_currencies, :list, default: [],
  doc: "When :currency_picker is true, pin these currencies to the top of the picker."

slot :currency_picker,
  doc: "Optional slot — render your own currency picker. Receives the current currency and a `change` event handler. Overrides the bundled picker when present."
```

Worked example:

```heex
<%!-- Single fixed currency (Stripe Checkout pattern) --%>
<.money_input form={@form} field={:price} currency={:USD} />
<!-- en-US: $[1,234.56] (right-aligned, $ adornment on the left) -->
<!-- de-DE: [1.234,56] € (right-aligned, € adornment on the right) -->
<!-- ja-JP, currency={:JPY}: ¥[1,234] (no decimals, ¥ adornment on the left) -->

<%!-- Currency-selectable (with the bundled picker) --%>
<.money_input
  form={@form}
  field={:price}
  currency={:USD}
  currency_picker={true}
  preferred_currencies={[:USD, :EUR, :GBP]}
/>
<!-- Renders the bundled <.currency_picker> in place of the static symbol adornment.
     User can switch currency; precision adapts; existing amount is rounded to new currency's exponent. -->

<%!-- Custom picker via slot --%>
<.money_input form={@form} field={:price}>
  <:currency_picker :let={current}>
    <MyApp.FancyCurrencyPicker.render current={current} on_change="currency_changed" />
  </:currency_picker>
</.money_input>
```

## Public API — currency_picker

The first-class currency picker — what differentiates this library from every other Elixir money library. Designed against the Wise and Revolut pickers as the explicit benchmark.

### Behaviour

* **Trigger** — small button showing the current currency's flag glyph + ISO code (e.g. `🇺🇸 USD`). Tap/click opens the picker overlay.
* **Search field** — when the overlay opens, focus jumps to a search input. Filters across all of: ISO code (`USD`), currency name (`United States Dollar`), country/territory name (`United States`, `États-Unis`, `アメリカ合衆国`), currency symbol (`$`). Match-highlighting in the result list.
* **Recent selections section** — at the top of the list, the user's most recent ~5 currency picks (stored in `localStorage`, scoped per-app). Empty on first use; persists across sessions. Revolut's hallmark behaviour.
* **Preferred currencies section** — below recents, currencies the developer pinned via `preferred:` attr (e.g. `[:USD, :EUR, :GBP]` for a US-focused remittance app). Configurable per picker instance.
* **All currencies section** — the rest, sorted via `Localize.Collation` for the active locale (so `Ä`/`Á`/`Å` collate near `A` in Swedish; the JS hook uses `Intl.Collator` for equivalent client-side sort).
* **Per-row content** — flag glyph (Unicode regional-indicator pair, generated at compile time), ISO code, currency name (locale-resolved), and the dial-code-style symbol (`$`, `£`, `¥`).
* **Keyboard navigation** — arrow keys, Enter to select, Esc to close, type-ahead jump. Standard combobox semantics with `aria-activedescendant`.
* **Mobile** — opens as a full-screen sheet (not a small dropdown), with the search field pinned at the top and large tap targets (~48px row height). Smooth slide-up animation. Matches Wise's mobile picker exactly.
* **Locale-detected default** — when `preferred:` isn't set and there are no recents, the first row is the locale's natural currency (en-US → USD, fr-FR → EUR, ja-JP → JPY) derived from `Localize.Currency.currency_for_locale/1`.

### API

```elixir
attr :current, :atom, required: true,
  doc: "The currently-selected currency (atom: :USD, :EUR, …)."
attr :on_change, :string, required: true,
  doc: "Phoenix event name fired when the user picks a different currency. Event payload is %{currency: atom}."
attr :allowed, :list, default: nil,
  doc: "Restrict the picker to these currencies (e.g. for service-area limits). Default: Money.known_currencies/0."
attr :preferred, :list, default: [],
  doc: "Pin these currencies to the top of the picker, after the recents section."
attr :recents_limit, :integer, default: 5,
  doc: "How many recent selections to remember in localStorage."
attr :locale, :string, default: nil
attr :variant, :atom, default: :auto, values: [:auto, :dropdown, :sheet],
  doc: ":auto picks based on viewport (sheet on mobile, dropdown on desktop). Override only for design-system reasons."
attr :class, :string, default: nil
attr :button_class, :string, default: nil
attr :overlay_class, :string, default: nil
attr :row_class, :string, default: nil
```

### Worked example

```heex
<.currency_picker
  current={@form[:currency].value || :USD}
  on_change="currency_changed"
  preferred={[:USD, :EUR, :GBP, :JPY]}
/>

<%!-- Standalone, not in a money_input — also works for "show me prices in" UI --%>
<.currency_picker
  current={@viewing_currency}
  on_change="viewing_currency_changed"
  variant={:dropdown}
/>
```

### What this picker matches/exceeds in each benchmark

* **Wise picker** — searchable across code/name/country/symbol ✓; flag glyphs ✓; mobile full-screen sheet ✓; recent selections persisted ✓ (a Wise feature too, not just Revolut's).
* **Stripe Checkout** — Stripe's checkout doesn't ship a currency picker (one currency per session); for that use case our `<.money_input currency={:USD} />` without `currency_picker:` matches by being equally minimal.

## Currency-change behaviour inside `<.money_input>`

When the user changes the currency via the embedded picker (or via the `:currency_picker` slot), the input must adapt cleanly:

* **Precision adjusts** — JPY → 0 decimals, USD → 2, BHD → 3. The currently-typed value is rounded to the new currency's exponent (USD `12.34` → JPY `12`). When this happens, an `on_currency_change` event fires with the rounded value so the consumer can show a toast ("Amount rounded to 12 for JPY precision").
* **Symbol position adjusts** — the adornment moves from prefix to suffix (or vice versa) per the locale + new currency's CLDR `currencyFormat`. Smooth ~150ms CSS transition on the adornment's position so the swap doesn't visually jar.
* **Validation re-runs** — min/max thresholds (if set in the currency the user picked away from) are re-checked against the new currency. The plan deliberately doesn't auto-convert the threshold — that's an FX concern outside this package.
* **`prefers-reduced-motion`** — when the OS-level accessibility setting is on, the symbol-position swap snaps directly with no transition.

## Storage and DX

The component owns the bridge between the user's text and the structured Elixir value. The form's submitted value is **always** structured:

* `<.number_input>` → the form gets `Decimal.t()` (or integer when `integer: true`).
* `<.money_input>` → the form gets `Money.t()` with the currency baked in.

The input never exposes the raw text or a float to the consuming changeset. This is the central DX promise: **the user types whatever locale form they like; the developer always receives a `Decimal` / `Money`**.

### Embedded changeset integration

Money's existing `Money.Ecto.Composite.Type` works directly. Add `field :price, Money.Ecto.Composite.Type` to the schema; the component populates it correctly.

For changesets validating min/max:

```elixir
schema "products" do
  field :price, Money.Ecto.Composite.Type
end

def changeset(product, attrs) do
  product
  |> cast(attrs, [:price])
  |> Money.Input.Validator.validate_money(:price, min: Money.new(:USD, "0.01"), max: Money.new(:USD, 9999))
end
```

`Money.Input.Validator.validate_money/3` handles currency-aware min/max comparison and produces translatable error messages.

## Validation strategy

Three passes, parallel to the sibling input libraries:

1. **JS-side** (when AutoNumeric is loaded) — AutoNumeric enforces min/max/decimals/range live, blocks invalid characters at the input event, sanitises paste. Pure UX; zero round-trip.
2. **Server-side per-keystroke** (debounced 300ms `phx-change`) — `Money.Input.Validator.validate_partial/3` checks the in-progress value, surfaces inline errors. Looser than submit-time validation (allows trailing decimals, in-progress negatives).
3. **Server-side on submit** — `Money.Input.Validator.changeset/2` runs the strict validation: parses to `Decimal`/`Money`, checks min/max/precision, ensures currency matches when `currency` is fixed.

Currency-aware precision: the validator reads the currency's CLDR exponent (USD: 2, JPY: 0, BHD: 3) and rejects more decimals than the currency allows. The client-side hook also enforces this via AutoNumeric's `decimalPlaces` config.

## RTL and accessibility

* **RTL locales** — number digits remain LTR (universal convention; numerals don't flip in RTL the way letters do). The input gets `dir="ltr"` explicitly so RTL stylesheets don't accidentally reverse the digits. The currency adornment swaps sides — what's `prefix` in LTR becomes `suffix` in RTL when the locale's convention is "symbol before number". For locales that natively put the symbol on the right (most Arabic locales), the convention matches naturally.
* **Right-align in RTL** — `align: :right` for money + RTL locale = the digits sit at the *end* of the input, which in RTL means the left-hand side. Works because the input is `dir="ltr"` so right-edge alignment is consistent regardless of page direction.
* **Screen reader output** — `aria-describedby` points at a hidden `<span class="sr-only">` carrying the locale-formatted value plus the currency name. The screen reader announces `"twelve point three four US dollars"` not `"$ space twelve dot three four"`. The currency name comes from `Money.currency_name/2` in the user's locale.
* **Keyboard users** — Tab order is the input then the currency picker (when present). The currency picker is a real `<select>` (or ARIA-compliant combobox in JS-enhanced mode). No keyboard trap.
* **Validation announcements** — errors render in a live region (`aria-live="polite"`), so screen readers hear "Price must be at least one cent" without the user having to navigate back to the field.
* **`pattern` attribute** is *not* used — pattern attributes on numeric text inputs trigger annoying browser validation behaviour that conflicts with our own validation. We rely on `inputmode` for keyboard hints and our validator for actual rules.

## Composition with existing primitives

The library does **no parsing or formatting** of its own — it composes:

* **Server-side parse**: `Localize.Number.Parser.parse/2` for numbers; `Money.parse/2` for money. Both already locale-aware.
* **Server-side format**: `Localize.Number.to_string/2` for numbers; `Money.to_string/2` for money. Both already locale-aware.
* **Currency precision**: `Money.currency_data(:USD).iso_digits` (or equivalent — the existing API for "how many decimals does this currency have").
* **Currency name for SR**: `Money.currency_name/2` (or whatever the existing helper is — already exists on Money).
* **Locale separators (for the JS hook config)**: `Localize.Number.Symbol.symbols_for/2` returns the locale's decimal/grouping/digit characters; the server passes these into the `data-` attributes the hook reads.

The hook bridges between AutoNumeric's config and the locale data the server side already knows about. No locale data is duplicated client-side beyond what's needed for the active component.

## Testing strategy

* **Unit tests for the headless parser front-door** — for ~10 representative locales (en, en-IN, de, fr, fr-CH, ja, ar, fa, pt-BR, zh-Hans), assert: parsing accepts the locale's native form, accepts pasted alternative forms, rejects ambiguous input, handles negative formats, handles currency symbols where present.
* **Unit tests for the validator** — min/max/decimals/precision per currency; required vs optional; range error messages.
* **Property tests for round-trip** — for any `Decimal` value and locale, `format(value, locale) → parse(formatted, locale) == value`.
* **Snapshot tests for the LiveView component HEEx output** — for ~10 locale × currency × component-type combinations.
* **Phoenix.LiveViewTest integration tests** — fill input, submit, assert the changeset has the correct `Decimal`/`Money`. Change currency, assert precision adapts. Trigger min/max, assert error renders.
* **JS hook unit tests (Vitest)** — AutoNumeric initialisation per locale, paste sanitisation, cursor preservation across formatting events, fallback behaviour when AutoNumeric load fails.
* **Cross-browser e2e tests (Playwright, gated on CI nightly)** — Chrome, Firefox, Safari (desktop + mobile). Verify the inputmode keyboard appears correctly on iOS/Android simulators.
* **Accessibility tests** — Lighthouse / axe-core in CI on the example app's input demos.

## Open questions

* **AutoNumeric vs hand-rolled JS.** Recommendation above is AutoNumeric. Counterargument: every dep we add to the front-end is a long-term maintenance cost, and AutoNumeric is one maintainer. Mitigation: pin to a known-good version, document the upgrade procedure, keep the Path C fallback documented as a viable alternative if AutoNumeric ever stops being maintained.

* **Currency change mid-input behaviour.** When the user has typed `12.34` in USD then switches to JPY (which has 0 decimals), what happens? Options: (a) round to JPY precision (`12`), (b) truncate (`12`), (c) reject the currency change. Recommendation: (a) round, with a `phx-event` so the parent can show a toast ("Amount adjusted from 12.34 to 12 for JPY precision"). Document the trade-off; let the component user override via an option.

* **Negative-number conventions.** `(123.45)` accounting style and `123.45-` trailing-minus are both used in real apps. Recommendation: ship `:negative_format` option with `:standard` (default, leading minus), `:accounting` (parens), `:trailing` (trailing minus). The parser accepts all three regardless of the display convention.

* **Empty / null / "0" semantics.** Is an empty input "0" or "no value"? Different forms want different semantics. Recommendation: empty string → `nil` (no value). Explicit `0` (or `"0"` typed) → `Decimal.new(0)` / `Money.new(currency, 0)`. Document; let consumers wrap in `validate_required` if they want to enforce non-nil.

* **Maximum input length.** Very large numbers cause UI layout problems. Default to `maxlength` based on `max:` config when supplied; fall back to a sensible default (16 digits) when no `max:` is set. Document.

* **Scientific notation in input.** Banking apps universally reject `1.5e10`. Recommendation: AutoNumeric rejects this by default; we don't expose a way to enable it. Edge case for scientific applications; out of scope for this package.

* **Currency picker scope.** The slot lets users plug in their own picker; should we ship a default? Most users only need 1–3 currencies and a simple `<select>` is fine. Recommendation: provide a minimal default (a `<select>` of `Money.known_currencies/0` or a configurable subset); document a fancier picker as a possible future spin-out (`localize_currency_picker`).

* **Keyboard shortcuts** — many finance apps support arrow-key increment/decrement. Worth shipping? AutoNumeric supports it natively (`alwaysAllowDecimalCharacter`, etc.). Recommendation: opt-in via `:keyboard_increment` option; off by default to match standard text-input conventions.

* **i18n of the validation messages.** Errors like "must be at least $0.01" need locale formatting of the threshold. Use Gettext with the threshold formatted via `Money.to_string/2` interpolated into the message.

## Phasing

| Phase | Scope | Estimate | Blocking |
|-------|-------|----------|----------|
| 1 | Headless layer: `Money.Input.Parser` (front-door wrapping `Localize.Number.Parser` + `Money.parse`), `Money.Input.Formatter` (server-side blur formatter), `Money.Input.Validator` (range, precision, required), `Money.Input.Locale` (separator/digit-system data for client). | 1 week | none |
| 2 | Form helpers: `Money.Input.Form` integration with `Phoenix.HTML.Form`. The `Embedded` schemas. Changeset helpers. | 0.5 weeks | Phase 1 |
| 3 | Native-HTML `<.number_input>` and `<.money_input>` (currency fixed via attr, no picker), server-side blur formatting, validation, RTL and accessibility, screen-reader copy. Functions correctly without JS — the Path A fallback. | 1.5 weeks | Phase 2 |
| 4 | JS hook wrapping AutoNumeric: live formatting, cursor preservation, paste sanitisation, debounced `pushEvent` to LiveView. Vitest coverage. | 1 week | Phase 3 |
| 5 | **`<.currency_picker>` first-class component** — searchable by code/name/country/symbol, flag glyphs, recent-selections memory (localStorage), preferred-currencies pinning, mobile full-screen sheet variant, locale-detected default, full keyboard nav with combobox semantics. Includes the JS hook for the search/sheet behaviour. | 1.5 weeks | Phase 4 |
| 6 | `<.money_input>` integration with `<.currency_picker>` (the `currency_picker: true` attr). Currency-change reactivity (precision adapts; existing amount rounds to new currency's exponent; symbol-position smooth transition; `prefers-reduced-motion` honoured). | 0.5 weeks | Phase 5 |
| 7 | Documentation: README with worked examples for each of the three components, full guide on integrating with Ecto / Ash / Phoenix forms, JS-hook setup. Sample app at `examples/` with a Stripe-style checkout demo, a multi-currency price display, and a quantity-plus-price line-item editor. Playwright e2e tests across desktop+mobile browsers. | 1 week | Phase 6 |

Total: **~7 weeks** for the full library. Phases 1–4 ship the foundational `<.number_input>` + `<.money_input>` (matches the Stripe Checkout bar). Phases 5–6 ship the `<.currency_picker>` (matches the Wise picker bar) and integrate it into `<.money_input>`. Phase 7 is the polish that makes the library actually usable by drop-in.

Phase ordering is deliberate: a developer can stop after Phase 4 and have a Stripe-grade single-currency input; Phases 5–6 unlock the picker for multi-currency apps. Each phase is independently shippable and useful.

Compare to address-input (~7 weeks) and phone-number-input (~4 weeks) — money_input lands at the same scope as address-input. The bar is Wise's input + picker quality (not its FX feature) and Stripe Checkout's locale-aware single-currency entry; both are matched without scoping in the bidirectional-FX flow that would push the estimate higher.

## Dependencies

```elixir
# mix.exs deps for money_input
{:money, "~> 6.0"},
{:localize, "~> 0.36"},
{:phoenix_html, "~> 4.0", optional: true},            # Phase 2
{:phoenix_live_view, "~> 1.0", optional: true},       # Phase 3
{:ecto, "~> 3.10", optional: true},                   # Phase 2
{:gettext, "~> 0.26", optional: true}                 # Phase 3 validation messages
```

JavaScript-side (Phase 4):

```json
{
  "dependencies": {
    "autonumeric": "^4.10.0"
  }
}
```

The JS hook ships in `priv/static/money_input.js`; users add `autonumeric` to their `package.json` and import the hook in `assets/js/app.js`. The hook is ~3 KB; AutoNumeric is ~50 KB.

## Change log for this plan

* 2026-05-15 — Initial draft. Two-component, one-library architecture; AutoNumeric chosen over hand-rolled JS for live formatting; native HTML baseline degrades gracefully without JS; storage always Decimal/Money never float.
