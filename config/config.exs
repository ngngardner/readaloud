# This file is responsible for configuring your umbrella
# and **all applications** and their dependencies with the
# help of the Config module.
#
# Note that all applications in your umbrella share the
# same configuration and dependencies, which is why they
# all use the same configuration file. If you want different
# configurations or dependencies per app, it is best to
# move said applications out of the umbrella.
# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

# --- Library (Ecto + Oban) ---
config :readaloud_library,
  ecto_repos: [ReadaloudLibrary.Repo]

config :readaloud_library, ReadaloudLibrary.Repo, database: "readaloud_dev.db"

config :readaloud_library, Oban,
  engine: Oban.Engines.Lite,
  repo: ReadaloudLibrary.Repo,
  queues: [import: 2, tts: 1]

# --- Web ---
config :readaloud_web,
  generators: [timestamp_type: :utc_datetime]

# Configure the endpoint
config :readaloud_web, ReadaloudWebWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: ReadaloudWebWeb.ErrorHTML, json: ReadaloudWebWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: ReadaloudWeb.PubSub,
  live_view: [signing_salt: "Stsep6Eo"]

# Prometheus metrics (PromEx). No standalone metrics server and no Grafana
# dashboard upload — metrics are served by PromEx.Plug on the Phoenix port
# and scraped by the Grafana Alloy agent on the host.
config :readaloud_web, ReadaloudWeb.PromEx,
  disabled: false,
  manual_metrics_start_delay: :no_delay,
  grafana: :disabled,
  metrics_server: :disabled

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  readaloud_web: [
    args:
      ~w(js/app.ts --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.) ++
        [~s|--define:process.env.NODE_ENV="production"|],
    cd: Path.expand("../apps/readaloud_web/assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  readaloud_web: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("../apps/readaloud_web", __DIR__)
  ]

# Configure Elixir's Logger. The metadata keys are set per-process by the
# reader LiveView (book_id/chapter_id), the TTS worker (task_id), and
# Plug.RequestId (request_id) — they render as `key=value` pairs in journald
# lines, which Loki picks up via the Alloy journal source on the host.
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :book_id, :chapter_id, :task_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"

# Sample configuration:
#
#     config :logger, :console,
#       level: :info,
#       format: "$date $time [$level] $metadata$message\n",
#       metadata: [:user_id]
#
