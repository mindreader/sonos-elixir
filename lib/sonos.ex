require Logger

defmodule Sonos do
  use Application

  def scan do
    Sonos.SSDP.scan()
  end

  def devices do
    Sonos.Server |> GenServer.call(:devices)
  end

  def start(_type, _args) do
    Supervisor.start_link([Sonos.Supervisor], strategy: :one_for_one)
  end

  def server_state do
    Sonos.Server |> GenServer.call(:state)
  end

  def ssdp_state do
    Sonos.SSDP |> GenServer.call(:state)
  end
end
