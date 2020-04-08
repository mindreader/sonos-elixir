defmodule Sonos.SSDP.Server do
  use GenServer

  defmodule State do
    defstruct ports: nil, devices: nil
  end

  def start_link(_args) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_args) do
    state = %State {
      ports: Sonos.SSDP.ports,
      devices: []
    }
    {:ok, state}
  end

  def handle_cast(:scan, state) do
    IO.puts("scanning")
    state.ports |> Sonos.SSDP.scan()

    state = %{ state |
      devices: []
    }
    {:noreply, state}
  end

  def handle_info({:udp, port, ip, _something, msg}, state) do
    state = %State { state |
      devices: [ {port, ip, msg} | state.devices]
    }
    {:noreply, state}
  end

  def handle_info(:state, state) do
    state |> IO.inspect(label: "state")
    {:noreply, state}
  end
end
