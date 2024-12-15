defmodule Sonos.Server do
  use GenServer

  alias Sonos.Device
  require Logger

  defmodule State do
    defstruct devices: nil,
              usn_by_endpoint: nil,
              our_event_address: nil

    def replace_device(%State{} = state, %Device{} = device) do
      %State{
        state |
        devices: state.devices |> Map.put(device.usn, device),
        usn_by_endpoint: state.usn_by_endpoint |> Map.put(device.endpoint, device.usn)
      }
    end

   def remove_device(%State{} = state, %Sonos.SSDP.Device{} = device) do
      endpoint = device |> Sonos.SSDP.Device.endpoint()
      %State {
        state |
        usn_by_endpoint: state.usn_by_endpoint |> Map.delete(endpoint)
      }
    end

    def remove_device(%State{} = state, %Device{} = device) do
      %State{
        state |
        devices: state.devices |> Map.delete(device.usn),
        usn_by_endpoint: state.usn_by_endpoint |> Map.delete(device.endpoint)
      }
    end

    def device_seen(%State{} = state, usn, last_seen_at) do
      state.devices[usn] |> then(fn
        nil -> state
        %Device{} = device ->
          device = %Device{device | last_seen_at: last_seen_at}
          State.replace_device(state, device)
      end)
    end
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

  def cache_fetch(endpoint, service, outputs) when is_list(outputs) do
    output_original_names = outputs |> Enum.map(fn x -> x.original_name end)

    __MODULE__ |> GenServer.call({:cache_fetch, endpoint, service, output_original_names})
    |> then(fn
      {:ok, %{outputs: result}} ->
        result = outputs |> Enum.map(fn x ->
          {x.name, result[to_string(x.original_name)]}
        end)
        |> Map.new()
        {:ok, %{outputs: result}}
      err ->
        err
    end)
  end

  def handle_cast({:update_device_state, usn, service, vars}, state) do
    state = state.devices[usn] |> then(fn
      nil ->
        Logger.warning("No device found for event received for usn #{usn}")
        state
      %Device{} = device ->
        device = device |> Device.update_state(service, vars)
        State.replace_device(state, device)
    end)

    {:noreply, state}
  end

  def handle_cast({:device_seen, usn, last_seen_at}, state) do
    Logger.debug("Device seen #{usn} at #{inspect(last_seen_at)}")
    state = State.device_seen(state, usn, last_seen_at)
    {:noreply, state}
  end

  def handle_cast({:update_device, %Sonos.SSDP.Device{} = device}, state) do
    # we need this because it is possible that a device has changed to an ip
    # that used to be used by some other device, and we should avoid confusion
    # if possible.
    state = State.remove_device(state, device)

    device |> Device.identify_task()

    {:noreply, state}
  end

  def handle_cast({:remove_device, usn}, state) do
    device = state.devices[usn]
    state = State.remove_device(state, device)

    {:noreply, state}
  end

  def handle_call(:state, _from, state) do
    {:reply, state, state}
  end

  def handle_call({:cache_fetch, endpoint, service_module, vars}, _from, state) do
    state.usn_by_endpoint[endpoint] |> then(fn
      nil ->
        {:reply, {:error, :unsubscribed_device}, state}
      usn ->
        state.devices[usn] |> then(fn
          nil ->
            {:reply, {:error, :unsubscribed_device}, state}

          %Sonos.Device{} = device ->
            service = service_module.service_type()

            device.state[service] |> then(fn
              nil ->
                # there is nothing cached, so subscribe so next time we will have it.
                device |> Device.subscribe_task(service_module, state.our_event_address)

                {:reply, {:error, :unsubscribed_event}, state}

              %Device.State{} = devstate ->
                # user has shown interest in this data, keep it up to date.
                if devstate |> Device.State.expiring?() do
                  device |> Device.subscribe_task(service_module, state.our_event_address)
                end
                vars = vars |> Enum.map(&to_string/1)

                res = devstate.state |> Map.take(vars)
                if res |> Enum.count() < vars |> Enum.count do
                  missing_vars = vars |> Enum.filter(fn v -> res |> Map.has_key?(v) end)
                  {:reply, {:error, {:missing_vars, missing_vars}}, state}
                else
                  {:reply, {:ok, %{outputs: res}}, state}
                end
            end)
        end)
    end)
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
