defmodule Sonos.Supervisor do
  use Supervisor

  def start_link(_args) do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_args) do
    [
      {Task.Supervisor, name: Sonos.Tasks},
      {Phoenix.PubSub, name: Sonos.PubSub},
      Sonos.SSDP,
      Sonos.Server,
      SonosWeb.Endpoint
    ]
    |> Supervisor.init(strategy: :one_for_one)
  end
end
