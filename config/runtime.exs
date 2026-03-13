import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.

if config_env() == :prod do
  config :readaloud_library, ReadaloudLibrary.Repo,
    database: System.get_env("DATABASE_PATH", "/data/readaloud.db")

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST", "localhost")
  port = String.to_integer(System.get_env("PORT", "4000"))

  config :readaloud_web, ReadaloudWebWeb.Endpoint,
    url: [host: host, port: port],
    http: [ip: {0, 0, 0, 0}, port: port],
    secret_key_base: secret_key_base,
    server: true

  config :readaloud_tts,
    base_url: System.get_env("LOCALAI_URL", "http://localai:8080")
end
