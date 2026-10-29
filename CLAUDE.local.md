# Session context

Last updated: 2026-10-29 by Claude (session: PR review, #211 adopted, CI aligned, parsing moved to Localize)

## Where things stand

* 2026-10-30: branch `main` at `615a35d`, two commits ahead of origin (`f176115`). Working tree: the whole 6.3.0 parsing move, uncommitted and ready but for one thing: `mix.exs` still has the TEMPORARY `{:localize, path: "../../localize/localize", override: true}` because Localize 1.5.0 is not on hex (1.4.3 is). Done today: `@version` 6.3.0, README `~> 6.3`, the `iso_digits` dialyzer suppression removed, the upgrade paragraph in the CHANGELOG (error modules, string-amount cost). Gates on this tree: format, compile, credo, 627 tests, docs with warnings as errors, dialyzer 0. Once 1.5.0 is published: `{:localize, "~> 1.5"}`, `mix deps.get`, rerun the suite and dialyzer, set the CHANGELOG date, commit. money_sql 2.1.1's cast fix is committed by the user. **Pre-publish check 2026-10-30:** the Localize 1.5.0 hex tarball (`mix hex.build` from `main` `92cdcd37`, unpacked in the session scratchpad `hexcheck/pkg`) was used as a path dep by lock-free scratch copies of ex_money (`{:localize, "~> 1.5"}`, no override) and money_sql (`localize_sql` 1.1.0 wants `~> 1.4`): ex_money 627 passed, money_sql 178 passed and 5 MySQL skips, Localize compiled without warnings, the 27 non-bundled locales downloaded from `https://elixir-localize.com/locales/v49.0.0/` (CLDR data version, not the release version) and verified against the manifest. Every Localize module, function, option and error-struct field ex_money and money_sql use exists in the package; the `Localize.Utils.*` modules it uses are `@moduledoc false`.

* Current sprint: ex_money 6.3.0. Landed: #207 and #210 merged; #211 adopted and widened, so every exchange-rates error is `{:error, {module, message}}` and 26 error specs are corrected; CI on the standard ten-row matrix with a PLT cache and a docs check. In flight: moving `Money.parse/2` and `Money.new/3` string amounts onto Localize.

* Last release v6.2.1 on 2026-08-04. Unreleased: the `## Money v6.2.2` CHANGELOG section, to be renamed v6.3.0 (decided 2026-10-28). `@version` is still 6.2.1. `mix.lock` has Localize 1.3.0; hex has 1.4.3.

* Open PRs: #208 and #209 (@rubas) are to be closed in favour of Localize's parser; the closing reply is drafted in the session, for the user to post. #211 is to be closed with the drafted thank-you.

## Decisions

* 2026-10-28 — Exchange-rates errors are normalized to `{:error, {module, message}}` (user). Because callers otherwise handled a bare binary, `:invalid_date` and `{module, binary}`.

* 2026-10-28 — Parsing moves to Localize: `Localize.Number.Parser.parse_currency_amount/2` (user's choice of name) replaces `Money.Parser` and `Money.Combinators`, and `Money.new/3` reads string amounts with `Localize.Number.Parser.parse/2` and `currency:`. Because ex_money's own grammar cannot read much of what Localize formats.

* 2026-10-28 — Compatibility comes first (user): every existing parsing test must still pass unchanged after the switch to Localize. Baseline before the switch: 389 pass (137 doctests, 1 property, 251 tests) across `money_parse_test`, `money_test`, `sigil_test`, `robustness_test`, `atom_safety_test`, `coverage_test`, `money_token_test`, `custom_currency_test`. Because existing users depend on today's results and error tuples.

* 2026-10-28 — This ships as ex_money 6.3.0, requiring the Localize release that carries `parse_currency_amount/2` (planned 1.5.0).

* 2026-10-29 — `Money.new/3` string amounts keep reading three fraction digits (`Money.new(:USD, "1.234")`); only `Money.parse/2` refuses them in a currency of fewer places (user). Because a string given to `Money.new/3` is a program's decimal, not text, and refusing it would break callers.

* 2026-10-29 — Release confidence pass (user): `guides/parsing.md` added (43 examples checked against real output), README parsing section replaced by a link to it, stale README `format: :long` example fixed, `digial` typo. The open questions it raised were decided the same day (next line).

* 2026-10-29 — Decisions (user): `en-AU` "€5" reads (currency signs naming one currency, Localize); parsing returns `Localize.LocaleNotFoundInCacheError` for a locale that is not installed, from `Money.parse/2` and `Money.new/3` string amounts (`string_amount/3`); a token clash goes to the locale's own currency (`mn` "₮5"); a token name is read only when one token, or one native token, has it (`token_id/2`, `one_token/3`): BTC, SOL read, ETH (13 native), USDT, USDC, DAI refused in `parse/2` and `new/3`, the identifier works in both (`Money.parse("Q9PB7XDNF 5")`, Localize reads a `:caller_currency` word with digits, user 2026-10-29). Inspect writes a token by its identifier where its short name does not read back as it (`protocol/inspect.ex`). Gates green (625 tests, credo, dialyzer 0, docs), guide 43 examples match; README's 15 differing examples are pre-existing (prose bindings, live rates).

## Gotchas

* `test/money_parse_test.exs` needs, beyond the Localize plan: a trailing minus (`€ 127,54-`, nl), a sign between currency and amount (`kr-127,54`, da), `($-127.54)` reading as positive, multi-word names (`12 346 dollar australien`), `separators: :standard`, and the exact `{Money.UnknownCurrencyError, …}` and `{Money.Invalid, …}` messages, which ex_money keeps building itself.

* Localize's `parse_currency_amount/2` (landed uncommitted 2026-10-28) takes `:default_currency` (code or text, resolved under the same filters), `:unknown_currency` (fun/1 → `{:ok, currency}`, for digital tokens; pass it only without `:fuzzy`, as ex_money never tries tokens when fuzzy), `:only`, `:except`, `:fuzzy`, `:separators`. Errors to map: `UnknownCurrencyError{currency: text}` → `Money.UnknownCurrencyError` message, `ParseError :missing_currency` → `Money.Invalid`, `ParseError :unexpected_input` → `Money.ParseError "Could not parse …"`. ex_money resolves `default_currency: nil` to the locale's currency itself.

* `Money.parse/2` keeps `:default_currency` (`nil` is the locale's currency, `false` an error) and digital tokens, which Localize does not know.

* A round trip of 80 Localize-formatted amounts: 37 read back clean with `scan` + `resolve_currencies`. JPY and IRR round to whole units, so a 1234.56 input formats as 1,235 and is not a parse failure.

* Toolchain: `export PATH="$(mise where erlang)/bin:$(mise where elixir)/bin:$PATH"` in every command; `mise current` is Elixir 1.20.4 on OTP 29.1.2.

## In flight (uncommitted, 2026-10-28)

* `Money.parse/2` runs on Localize's `parse_currency_amount/2`; `Money.Parser`, `Money.Combinators` (`lib/money/parser/`) and the `nimble_parsec` dependency are deleted; `.credo.exs` exclusions for them removed; CHANGELOG section renamed v6.3.0 with parse entries. Full suite 576/576, as the baseline.

* TEMPORARY in `mix.exs`: `{:localize, path: "../../localize/localize", override: true}`. `mix.lock` changed with it (decimal 3.2.0; cldr_utils, poison, unicode unlocked). Before any commit: Localize 1.5.0 on hex, restore `{:localize, "~> 1.5"}`, `mix deps.get`, retest.

* Localize side (uncommitted there): `Localize.InvalidAmountError{currency, amount, cause}` (user's choice 2026-10-28), which `Money.parse/2` maps to `Money.Invalid` "Unable to create money from …".

* `Money.new/3` string amounts now read by `Localize.Number.Parser.parse/2` with plain separators (no `:currency`); old reader (`symbol_preference`, `number_symbols_for_number_system`) deleted. User 2026-10-28: unambiguously wrong old results are bugs and are refused; tests added in `money_test.exs` and `money_parse_test.exs`. Suite 578.

* Done 2026-10-28 (user): a decimal mark may open or close an amount (".5 USD", "5.USD"); a mark between currency and digits is the currency's if CLDR writes it so ("kr.5" da), the number's if it is the decimal mark ("$.50" = 0.50, was 50), else refused ("kr.5" nb). Correctness first: refuse what is ambiguous (memory money-correctness-first).

* Done 2026-10-28 (user chose option 3 + sizes grouping): `Money.new/3` and `Money.parse/2` read string amounts with `grouping: :sizes` and the currency; in de-AT and fr-CH both separator sets are read and a conflict is refused ("1.234 EUR" de-AT). 864-case comparison vs old: 0 changed values, 146 refusals (all wrong or ambiguous old readings), 32 new readings. Suite 581. Then (user 2026-10-28) token amounts: Localize `root_separators: true` (caller currencies get it automatically in `parse_currency_amount/2`), ex_money `maybe_token/1` matches `DigitalToken.symbols/0`, `Money.new/3` reads token amounts with root too. Suite 584. Then (user 2026-10-28) Localize `:unknown_currency` renamed `:caller_currency`, consulted for every currency text and refusing text CLDR and the caller name differently; ex_money passes `token_currency/1` only when `Code.ensure_loaded?(DigitalToken)`, and it stands aside for ISO 4217 codes (20 codes are token short names, e.g. EUR). Refused: `₮`, `K`, `ZK`. Suite 586.

* Fixed 2026-10-28: `open_exchange_rates_test.exs` "sets app_id to nil when not configured" failed when it ran first and OPEN_EXCHANGE_RATES_APP_ID was set (`config/test.exs` reads it); the test now deletes the key itself and setup restores env keys instead of deleting them. Commit it on its own, by path.

## Next steps

* [ ] After Localize 1.5.0 is on hex: `{:localize, "~> 1.5"}` in `mix.exs`, `mix deps.get`, rerun `mix test` and `mix dialyzer`, set the CHANGELOG release date, then the user commits and publishes 6.3.0.

* [ ] Next performance target: the string path of `Money.new/3` (20 µs against 6 in 6.2.1), which is Localize's amount path.
