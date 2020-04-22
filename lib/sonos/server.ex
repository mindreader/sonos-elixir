defmodule Sonos.Server do
  use GenServer

  alias Sonos.Device
  require Logger

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
    {:ok, state, {:continue, :scan}}
  end

  def handle_cast(:scan, state) do
    Logger.debug("Scanning...")
    state.ports |> Sonos.SSDP.scan()
    {:noreply, state}
  end

  def handle_cast({:identify, %Device{} = device, %Device.Description{} = description}, state) do
    uuid = device |> Device.uuid()

    state.devices[uuid] |> case do
      nil ->
        Logger.debug("Attempted to identify a device that has gone away #{inspect(device)}")
        {:noreply, state}
      %Device{} = dev ->
        state = update_in(state.devices, fn devices ->
          devices|> Map.put(uuid, %Device{ dev |
            description: description
          })
        end)
        {:noreply, state}
    end
  end

  def handle_call(:devices, _from, state) do
    {:reply, state.devices |> Map.values, state}
  end

  def handle_call(:state, _from, state) do
    {:reply, state, state}
  end

  # TODO tidy this stuff up a bit.
  def handle_info({:udp_passive, port, ip, something, msg}, state) do
    handle_info({:udp, port, ip, something, msg}, state)
  end
  def handle_info({:udp, _port, ip, _something, msg}, state) do

    alias Sonos.{Device,SSDP}

    msg |> SSDP.response_parse |> Device.from_headers(ip) |> case do
      {:ok, %Device{} = device} ->
        uuid = device |> Device.uuid()

        state = %State { state |
          devices: state.devices |> Map.put(uuid, device)
        }
        Task.start(Sonos, :identify, [device])
        {:noreply, state}

      _ ->
        {:noreply, state}
    end
  end

  def handle_continue(:scan, state) do
    handle_cast(:scan, state)
  end
end
