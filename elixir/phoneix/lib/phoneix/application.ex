defmodule Phoneix.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    OpentelemetryPhoenix.setup()

    children = [
      PhoneixWeb.Telemetry,
      Phoneix.Repo,
      {DNSCluster, query: Application.get_env(:phoneix, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Phoneix.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: Phoneix.Finch},
      # Start a worker by calling: Phoneix.Worker.start_link(arg)
      # {Phoneix.Worker, arg},
      # Start to serve requests, typically the last entry
      PhoneixWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Phoneix.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    PhoneixWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
