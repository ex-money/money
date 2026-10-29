defimpl Inspect, for: Money do
  import Money, only: [is_digital_token: 1]

  # `:digital_token` is an optional dependency. See `Money` for context.
  @compile {:no_warn_undefined, DigitalToken}

  def inspect(%Money{currency: token_id} = money, opts) when is_digital_token(token_id) do
    money
    |> Map.put(:currency, token_name(token_id))
    |> do_inspect(opts)
  end

  def inspect(money, opts) do
    do_inspect(money, opts)
  end

  def do_inspect(%Money{format_options: []} = money, _opts) do
    "Money.new(#{inspect(money.currency)}, #{inspect(Decimal.to_string(money.amount))})"
  end

  def do_inspect(money, _opts) do
    format_options =
      money.format_options
      |> inspect()
      |> String.trim_leading("[")
      |> String.trim_trailing("]")

    "Money.new(#{inspect(money.currency)}, #{inspect(Decimal.to_string(money.amount))}, #{format_options})"
  end

  # A token's short name where `Money.new/3` reads it back as the same token,
  # as it does "BTC", and otherwise its identifier: "USDT" names one token
  # per chain, and "EUR", the short name of a token too, is the euro.
  defp token_name(token_id) do
    if Code.ensure_loaded?(DigitalToken) do
      readable_name(apply(DigitalToken, :short_name, [token_id]), token_id)
    else
      token_id
    end
  end

  defp readable_name({:ok, name}, token_id) do
    money = Money.new(name, 0)

    if match?(%Money{currency: ^token_id}, money) do
      name
    else
      token_id
    end
  end

  defp readable_name(_no_name, token_id) do
    token_id
  end
end
