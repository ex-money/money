defmodule Money.LocaleNotInstalledTest do
  # The test puts fallback data in place of a locale's own, which every
  # process sees, so it runs alone.
  use ExUnit.Case, async: false

  alias Localize.Locale.Provider.PersistentTerm

  # A locale no other test reads, given English data as Localize's loader
  # gives it when the locale is not installed and cannot be downloaded.
  @locale :"en-MT"

  setup do
    {:ok, english} = PersistentTerm.load(:en)
    :ok = PersistentTerm.store(@locale, Map.put(english, :name, :en))

    on_exit(fn ->
      case PersistentTerm.load(@locale) do
        {:ok, own} -> PersistentTerm.store(@locale, Map.put(own, :name, @locale))
        {:error, _not_installed} -> :ok
      end
    end)
  end

  # With English data, "$5" would be US dollars wherever the locale is.
  test "parsing refuses a locale whose data is not installed" do
    assert {:error, %Localize.LocaleNotFoundInCacheError{locale_id: @locale}} =
             Money.parse("$5", locale: @locale)

    assert {:error, %Localize.LocaleNotFoundInCacheError{locale_id: @locale}} =
             Money.new(:EUR, "1.234", locale: @locale)
  end

  test "a money amount needs no locale data" do
    assert %Money{} = Money.new(:EUR, 1234, locale: @locale)
    assert %Money{} = Money.new(:EUR, Decimal.new("1.234"), locale: @locale)
  end
end
