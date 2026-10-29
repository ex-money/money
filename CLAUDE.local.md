# Session context

Last updated: 2026-10-30 by Claude (session: release review of ex_money 6.3.0)

## Where things stand

* Branch `main` at `3b45bec`, matching origin. Working tree dirty with the release-review fixes, uncommitted: `.github/workflows/ci.yml` (Elixir patch bump), `CHANGELOG.md` (release date), `LICENSE.md` (copyright year), `README.md` (three bare fences tagged `elixir`, `## License` section), `mix.exs` (`groups_for_modules` covers every public module), `mix.lock` (Localize 1.3.0 → 1.5.0; the committed lock had not been updated when `mix.exs` moved to `~> 1.5`), `CLAUDE.local.md`.

* Current sprint: ex_money 6.3.0, parsing moved onto Localize 1.5. Everything is landed; the release review is done and the release is ready to commit, tag and publish.

* Last release v6.2.1 on 2026-08-04 (confirmed with `mix hex.info ex_money`). Unreleased: 6.3.0, `@version` already 6.3.0, README install `~> 6.3`.

* Gates on this tree (Elixir 1.20.4 / OTP 29.1.2, the mise-current toolchain; mise is one patch behind Elixir 1.20.5): format, compile with warnings as errors, credo strict (0), 627 tests (175 doctests), `MIX_ENV=release mix docs --warnings-as-errors` clean. Dialyzer not run this session (CI lint row runs it; it was 0 on 2026-10-29). All 44 `guides/parsing.md` examples and the README examples match real output, except three README examples that need the live exchange-rate service and two subscription examples that depend on a `plan` bound in prose.

* Open PRs: #208 and #209 (@rubas) are to be closed in favour of Localize's parser; #211 is to be closed with a thank-you. The user posts the replies.

## Decisions

* 2026-10-28 — Exchange-rates errors are normalized to `{:error, {module, message}}` (user). Because callers otherwise handled a bare binary, `:invalid_date` and `{module, binary}`.

* 2026-10-28 — Parsing moves to Localize: `Localize.Number.Parser.parse_currency_amount/2` replaces `Money.Parser` and `Money.Combinators`; `Money.new/3` reads string amounts with `Localize.Number.Parser.parse/2`. Because ex_money's own grammar could not read much of what Localize formats.

* 2026-10-28 — Compatibility first (user): every pre-existing parsing test passes unchanged after the switch.

* 2026-10-29 — `Money.new/3` string amounts keep reading three fraction digits; only `Money.parse/2` refuses them in a currency of fewer places (user). Because a string given to `Money.new/3` is a program's decimal, not text.

* 2026-10-29 — (user) `en-AU` "€5" reads; an uninstalled locale returns `Localize.LocaleNotFoundInCacheError` from `Money.parse/2` and string-amount `Money.new/3`; a token/currency symbol clash goes to the locale's own currency (`mn` "₮5"); a token name is read only when one token, or one native token, has it; the token identifier always works (`Money.parse("Q9PB7XDNF 5")`); inspect writes a token by its identifier where its short name does not read back as it.

* 2026-10-30 — `CLAUDE.local.md` is committed in this repository (user, commit `63da680`), not gitignored as the global convention has it.

* 2026-10-30 — `Jason.Encoder` stays as an optional protocol implementation for consumers who use Jason (`lib/money/protocol/jason.ex`); ex_money itself decodes with `:json`. Removing it would break consumers.

## Gotchas

* Running the gates needs `mix deps.get` first whenever `mix.lock` moves; the test run silently did nothing until the Localize 1.5.0 dep was fetched.

* `test/money_parse_test.exs` keeps the exact `{Money.UnknownCurrencyError, …}` and `{Money.Invalid, …}` messages, which ex_money builds itself after mapping Localize's `UnknownCurrencyError`, `ParseError :missing_currency` and `ParseError :unexpected_input`.

* `Money.parse/2` keeps `:default_currency` (`nil` is the locale's currency, `false` an error) and digital tokens, which Localize does not know.

* JPY and IRR round to whole units, so a 1234.56 input formats as 1,235 and reading it back is not a parse failure.

## Next steps

* [ ] User commits the review fixes, tags v6.3.0, publishes to hex, closes #208, #209 and #211 with the drafted replies.
