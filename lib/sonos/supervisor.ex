defmodule Sonos.Supervisor do
  use Application
  use Supervisor

  @impl Application
  def start(_type, _args) do
    Supervisor.start_link(Sonos.Supervisor, [], strategy: :one_for_one)
  end

  @impl Supervisor
  def init(_args) do
    [
      {Task.Supervisor, name: Sonos.Tasks},
      {Phoenix.PubSub, name: Sonos.PubSub},
      Sonos.SSDP,
      Sonos.Server,
      SonosWeb.Endpoint
      #      BigBrother.ReloadServer,
    ]
    |> Supervisor.init(strategy: :one_for_one)
  end
end
