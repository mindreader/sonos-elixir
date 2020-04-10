defmodule Sonos.Supervisor do
  use Supervisor

  def start_link(_args) do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_args) do
    [
      Sonos.SSDP.Server,
      Plug.Cowboy.child_spec(scheme: :http, plug: Sonos.Router, port: 4001)
    ]
    |> Supervisor.init(
      strategy: :one_for_one,
      name: __MODULE__
    )
  end
end
