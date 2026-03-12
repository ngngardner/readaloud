defmodule ReadaloudLibrary.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      ReadaloudLibrary.Repo,
      {Oban, Application.fetch_env!(:readaloud_library, Oban)}
    ]

    opts = [strategy: :one_for_one, name: ReadaloudLibrary.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
