import Config

config :ex_money, Money.Repo,
  adapter: Ecto.Adapters.Postgres,
  username: "kip",
  database: "money_dev",
  hostname: "localhost",
  pool_size: 10

config :ex_money, ecto_repos: [Money.Repo]

config :localize,
  default_locale: :en,
  allow_runtime_locale_download: true

config :ex_money,
  exchange_rates_retrieve_every: :never,
  open_exchange_rates_app_id: {:system, "OPEN_EXCHANGE_RATES_APP_ID"},
  api_module: Money.ExchangeRatesMock,
  log_failure: nil,
  log_info: nil,
  json_library: Jason
