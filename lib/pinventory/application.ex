defmodule Pinventory.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      PinventoryWeb.Telemetry,
      Pinventory.Repo,
      {DNSCluster, query: Application.get_env(:pinventory, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Pinventory.PubSub},
      # Start a worker by calling: Pinventory.Worker.start_link(arg)
      # {Pinventory.Worker, arg},
      # Start to serve requests, typically the last entry
      PinventoryWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Pinventory.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    PinventoryWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
