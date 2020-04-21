require Logger

defmodule Sonos.Server do
  use GenServer

  alias Sonos.Device

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

  def handle_cast({:identify, %Device{} = device, %Device.Description{} = description}, state) do
    case device |> Device.uuid() do
      {:ok, uuid} ->
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
      err ->
        Logger.debug("Cannot identify device #{inspect(err)}")
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

    device = msg |> SSDP.response_parse |> Device.from_headers(ip)

    case device |> Device.uuid() do
      {:ok, uuid} ->
        state = %State { state |
          devices: state.devices |> Map.put(uuid, device)
        }
        {:noreply, state}
      _ ->
        Logger.debug("Unable to get uuid for device #{inspect(device)}")
        {:noreply, state}
    end
  end

end
