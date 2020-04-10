defmodule Sonos.SSDP.Server do
  use GenServer

  alias Sonos

  defmodule State do
    defstruct ports: nil, devices: nil
  end

  def start_link(_args) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_args) do
    state = %State {
      ports: Sonos.SSDP.ports,
      devices: %{}
    }
    {:ok, state}
  end

  def handle_cast(:scan, state) do
    IO.puts("scanning")
    state.ports |> Sonos.SSDP.scan()

    state = %{ state |
      devices: %{}
    }
    {:noreply, state}
  end

  # TODO tidy this stuff up a bit.
  def handle_info({:udp_passive, _port, ip, _something, msg}, state) do
    handle_info({:udp, _port, ip, _something, msg}, state)
  end
  def handle_info({:udp, _port, ip, _something, msg}, state) do

    alias Sonos.{Device,SSDP}

    device = msg |> SSDP.response_parse |> Device.from_headers(ip)

    state = %State { state |
      devices: state.devices |> Map.put(device.id, device)
    }
    {:noreply, state}
  end

  def handle_info(:state, state) do
    state |> IO.inspect(label: "state")
    {:noreply, state}
  end
end
