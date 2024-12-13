defmodule Sonos.Server do
  use GenServer

  alias Sonos.Device
  require Logger

  defmodule State do
    defstruct devices: nil,
              usn_by_endpoint: nil,
              our_event_address: nil
  end

  def start_link(_args) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_args) do
    Logger.info("Starting Sonos server")

    with {:ok, our_event_address} <- Sonos.Utils.our_event_address() do
      state = %State{
        our_event_address: "#{our_event_address}/event",
        # Map of usn -> device
        devices: %{},
        # Map of endpoint -> usn
        # purpose of this is to allow this to be used a as a cache for api calls
        # to a certain endpoint, without needing to pass in a usn.
        usn_by_endpoint: %{}
      }

      {:ok, state, {:continue, :subscribe}}
    else
      err -> err
    end
  end

  def update_device_state(usn, service, vars) do
    __MODULE__ |> GenServer.cast({:update_device_state, usn, service, vars})
  end

  def cache_fetch(endpoint, service, vars) when is_list(vars) do
    __MODULE__ |> GenServer.call({:cache_fetch, endpoint, service, vars})
  end

  def handle_cast({:update_device_state, usn, service, vars}, state) do
    state = state.devices[usn] |> then(fn
      nil ->
        Logger.warning("No device found for event received for usn #{usn}")
        state
      %Device{} = device ->
        device_state = device.state |> Map.put(service, vars)
        device = %Device{device | state: device_state}
        %State{state | devices: state.devices |> Map.put(usn, device)}
    end)

    {:noreply, state}
  end

  def handle_cast({:update_device, %Sonos.SSDP.Device{} = device}, state) do
    # if the device has changed ip, we need to make sure the old one is removed, lest
    # we have two endpoints pointing to the same device.
    state = update_in(state.usn_by_endpoint, &Map.delete(&1, device |> Sonos.SSDP.Device.endpoint()))

    device |> Device.identify_task()

    {:noreply, state}
  end

  def handle_cast({:remove_device, usn}, state) do
    device = state.devices[usn]

    state = if device do
      update_in(state.usn_by_endpoint, &Map.delete(&1, device.endpoint))
    else
      state
    end

    state = update_in(state.devices, &Map.delete(&1, usn))

    {:noreply, state}
  end

  def handle_call(:state, _from, state) do
    {:reply, state, state}
  end

  def handle_call({:cache_fetch, endpoint, service, vars}, _from, state) do
    with {:usn, usn} when is_binary(usn) <- {:usn, state.usn_by_endpoint[endpoint]},
         %Device{} = device <- state.devices[usn],
          {:cache, cache} when is_map(cache) <- {:cache, device.state[service]} do

          # TODO we have fetched from the cache, we need to resubscribe to ensure we
          # keep this state up to date, in case we keep needing data from it.

          res = cache |> Map.take(vars)
          {:reply, {:ok, res}, state}
    else
      {:usn, nil} -> {:reply, {:error, :unsubscribed_device}, state}
      {:cache, nil} ->
        # TODO we were unsubscribed, we should subscribe so that we will have the data
        # next time if it is needed.
        {:reply, {:error, :unsubscribed_event}, state}
      err ->
        Logger.error("""
        Error fetching state:
          endpoint #{endpoint}
          service #{service}
          vars #{inspect(vars)}
          err #{inspect(err)}
        """)
        raise err
    end
  end

  def handle_continue(:subscribe, state) do
    # ZonePlayer is the root device type for all sonos devices, so far as I am aware.
    # Each one has two sub devices: MediaRenderer and MediaServer.
    "urn:schemas-upnp-org:device:ZonePlayer:1" |> Sonos.SSDP.subscribe()
    {:noreply, state}
  end

  def handle_info({_ref, {:ok, %Device{} = device}}, state) do
    state = update_in(state.devices, &Map.put(&1, device.usn, device))
    state = update_in(state.usn_by_endpoint, &Map.put(&1, device.endpoint, device.usn))

    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    {:noreply, state}
  end
end
