defmodule Sonos.Server do
  use GenServer

  alias Sonos.Device
  require Logger

  defmodule State do
    defstruct devices: nil, our_event_address: nil
  end

  def start_link(_args) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_args) do
    Logger.info("Starting Sonos server")

    with {:ok, our_event_address} <- Sonos.Utils.our_event_address() do
      state = %State{
        our_event_address: our_event_address,
        # Map of usn -> device
        devices: %{}
      }

      {:ok, state, {:continue, :subscribe}}
    else
      err -> err
    end
  end

  def handle_cast({:update_device, %Sonos.SSDP.Device{} = device}, state) do
    # state = update_in(state.devices, &Map.put(&1, device.usn, device))

    device |> Device.identify_task()

    {:noreply, state}
  end

  def handle_cast({:remove_device, usn}, state) do
    state = update_in(state.devices, &Map.delete(&1, usn))

    {:noreply, state}
  end

  def handle_call(:state, _from, state) do
    {:reply, state, state}
  end

  def handle_continue(:subscribe, state) do
    Sonos.SSDP.subscribe("urn:schemas-upnp-org:device:ZonePlayer:1")
    {:noreply, state}
  end

  def handle_info({ref, {:ok, %Device{} = device}}, state) do
    state = update_in(state.devices, &Map.put(&1, device.usn, device))

    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    {:noreply, state}
  end
end
