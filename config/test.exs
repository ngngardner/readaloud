import Config

# --- Library test config ---
config :readaloud_library, ReadaloudLibrary.Repo,
  database: "readaloud_test.db",
  pool: Ecto.Adapters.SQL.Sandbox

config :readaloud_library, Oban, testing: :manual

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :readaloud_web, ReadaloudWebWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "qLh+kHMDzK99zgMZuYSA95mHXA5MBmw9NgP9NJhejfa8s1kJapXJWlY3rOCN+wzv",
  server: false

# PromEx stays enabled so /metrics and the custom plugin are testable, but
# DB-polling groups are dropped: pollers run outside the SQL sandbox owner
# and would only produce ownership-error noise.
config :readaloud_web, ReadaloudWeb.PromEx,
  drop_metrics_groups: [:oban_queue_poll_metrics, :readaloud_snapshot_polling_metrics]

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
