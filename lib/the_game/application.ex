defmodule TheGame.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      TheGameWeb.Telemetry,
      TheGame.Repo,
      {DNSCluster, query: Application.get_env(:the_game, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: TheGame.PubSub},
      # Start a worker by calling: TheGame.Worker.start_link(arg)
      # {TheGame.Worker, arg},
      # Start to serve requests, typically the last entry
      TheGameWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: TheGame.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    TheGameWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
