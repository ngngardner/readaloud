defmodule ReadaloudLibrary.Repo do
  use Ecto.Repo,
    otp_app: :readaloud_library,
    adapter: Ecto.Adapters.SQLite3
end
