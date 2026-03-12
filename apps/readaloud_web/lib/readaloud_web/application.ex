defmodule ReadaloudWeb.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      ReadaloudWebWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:readaloud_web, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: ReadaloudWeb.PubSub},
      # Start a worker by calling: ReadaloudWeb.Worker.start_link(arg)
      # {ReadaloudWeb.Worker, arg},
      # Start to serve requests, typically the last entry
      ReadaloudWebWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ReadaloudWeb.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ReadaloudWebWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
