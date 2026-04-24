defmodule DeckingCalc.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      DeckingCalcWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:decking_calc, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: DeckingCalc.PubSub},
      # Start a worker by calling: DeckingCalc.Worker.start_link(arg)
      # {DeckingCalc.Worker, arg},
      # Start to serve requests, typically the last entry
      DeckingCalcWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: DeckingCalc.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    DeckingCalcWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
