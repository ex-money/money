defmodule Money.ExceptionTest do
  use ExUnit.Case, async: true

  # Exception modules whose `exception/1` accepts a message string and whose
  # message is returned verbatim by `Exception.message/1`.
  @message_exceptions [
    Money.UnknownCurrencyError,
    Money.InvalidCurrencyError,
    Money.FormatError,
    Money.ExchangeRateError,
    Money.InvalidAmountError,
    Money.InvalidDigitsError,
    Money.Invalid,
    Money.ParseError,
    Money.Subscription.NoCurrentPlan,
    Money.Subscription.PlanError,
    Money.Subscription.DateError,
    Money.Subscription.PlanPending
  ]

  describe "message-style exceptions" do
    test "build from a string and expose it via Exception.message/1" do
      for module <- @message_exceptions do
        exception = module.exception("boom")

        assert exception.__struct__ == module
        assert Exception.message(exception) == "boom"
      end
    end

    test "can be raised and rescued with the given message" do
      for module <- @message_exceptions do
        assert_raise module, "boom", fn -> raise module, "boom" end
      end
    end
  end

  describe "CurrencyAlreadyDefinedError" do
    test "formats a message from its currency binding" do
      exception = Money.CurrencyAlreadyDefinedError.exception(currency: :USD)

      assert exception.currency == :USD
      assert Exception.message(exception) == "The currency :USD is already defined."
    end
  end

  describe "CurrencyNotSavedError" do
    test "formats a message pointing at the currency store" do
      exception = Money.CurrencyNotSavedError.exception(currency: :XBT)

      assert exception.currency == :XBT
      message = Exception.message(exception)
      assert message =~ ":XBT"
      assert message =~ "could not be saved"
      assert message =~ "Money.Currency.Store"
    end
  end
end
