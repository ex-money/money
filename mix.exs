defmodule Money.Mixfile do
  use Mix.Project

  @version "6.0.0"
  @source_url "https://github.com/ex-money/money"

  def project do
    [
      app: :ex_money,
      version: @version,
      elixir: "~> 1.17",
      name: "Money",
      source_url: @source_url,
      docs: docs(),
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      test_coverage: [tool: ExCoveralls],
      aliases: aliases(),
      elixirc_paths: elixirc_paths(Mix.env()),
      dialyzer: [
        plt_add_apps: ~w(inets mix phoenix_html)a,
        flags: [
          :error_handling,
          :unknown,
          :underspecs,
          :extra_return,
          :missing_return
        ]
      ],
      compilers: Mix.compilers()
    ]
  end

  defp description do
    """
    Money functions for operations on and localization of a money data type with support
    for ISO 4217 currencies and ISO 24165 digial tokens (crypto currencies).
    """
  end

  defp package do
    [
      maintainers: ["Kip Cole"],
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => @source_url,
        "Readme" => "#{@source_url}/blob/v#{@version}/README.md",
        "Changelog" => "#{@source_url}/blob/v#{@version}/CHANGELOG.md"
      },
      files: [
        "lib",
        "config",
        "mix.exs",
        "README.md",
        "CHANGELOG.md",
        "LICENSE.md"
      ]
    ]
  end

  def application do
    [
      mod: {Money.Application, [strategy: :one_for_one, name: Money.Supervisor]},
      extra_applications: [:inets, :logger, :decimal]
    ]
  end

  def docs do
    [
      source_ref: "v#{@version}",
      extras: ["README.md", "CHANGELOG.md", "LICENSE.md"],
      main: "readme",
      groups_for_modules: groups_for_modules(),
      logo: "logo.png",
      formatters: ["html", "markdown"],
      skip_undefined_reference_warnings_on: ["changelog", "CHANGELOG.md", "README.md"]
    ]
  end

  defp groups_for_modules do
    [
      "Exchange Rates": ~r/^Money.ExchangeRates.?/,
      Subscriptions: ~r/^Money.Subscription.?/
    ]
  end

  def aliases do
    []
  end

  defp deps do
    [
      {:localize, "~> 0.27"},
      {:digital_token, "~> 2.0", optional: true},
      {:nimble_parsec, "~> 0.5 or ~> 1.0"},
      {:decimal, "~> 1.6 or ~> 2.0 or ~> 3.0"},
      {:phoenix_html, "~> 2.0 or ~> 3.0 or ~> 4.0", optional: true},
      {:dialyxir, "~> 1.0", only: [:dev, :test], runtime: false},
      {:jason, "~> 1.0", optional: true},
      {:stream_data, "~> 1.0", only: [:dev, :test]},
      {:benchee, "~> 1.0", optional: true, only: :dev},
      {:exprof, "~> 0.2", only: :dev, runtime: false},
      {:ex_doc, "~> 0.31", only: [:dev, :release]}
    ] ++ maybe_json_polyfill()
  end

  defp maybe_json_polyfill do
    if Code.ensure_loaded?(:json) do
      []
    else
      [{:json_polyfill, "~> 0.2 or ~> 1.0"}]
    end
  end

  defp elixirc_paths(:test), do: ["lib", "test", "test/support"]
  defp elixirc_paths(:dev), do: ["lib", "mix"]
  defp elixirc_paths(_), do: ["lib"]
end
