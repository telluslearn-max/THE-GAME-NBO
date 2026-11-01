import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :the_game, TheGame.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "the_game_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :the_game, TheGameWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "dud4razGShvoLGgw/0AZvsLmH/FjZHBhNUUU1TsM9O1v19+SBQSp7g+SyFiWb+qg",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Payments: deterministic tests. No background sweeper, no auto-settling fake.
config :the_game,
  start_sweeper: false,
  stk_cooldown_seconds: 0,
  mpesa_callback_token: "test-token"
