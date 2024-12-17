defmodule Sonos.Server do
  use GenServer

  alias Sonos.Device
  alias Sonos.Server.State

  require Logger

  @default_subscribe_timeout 60 * 5

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

  def update_device_state(usn, service, vars) when is_binary(service) do
    vars =
      case service do
        # This one is special because it returns a big xml blob that has to be parsed specially.
        "RenderingControl:1" ->
          vars["LastChange"]
          |> XmlToMap.naive_map()
          |> Map.get("Event")
          |> Sonos.Utils.coerce_to_list()
          |> Enum.map(fn %{"InstanceID" => %{"-val" => instance_id, "#content" => data}} ->
            data |> IO.inspect(label: "data")
            # Map (instance_id -> state)
            data = %{
              "Loudness" =>
                data["Loudness"]
                |> Sonos.Utils.coerce_to_list()
                |> Enum.map(fn val ->
                  {val["-channel"], val["-val"] |> String.to_integer()}
                end)
                |> Map.new(),
              "Volume" =>
                data["Volume"]
                |> Sonos.Utils.coerce_to_list()
                |> Enum.map(fn val ->
                  {val["-channel"], val["-val"] |> String.to_integer()}
                end)
                |> Map.new(),
              "Mute" =>
                data["Mute"]
                |> Sonos.Utils.coerce_to_list()
                |> Enum.map(fn val ->
                  {val["-channel"], val["-val"] == "1"}
                end)
                |> Map.new(),
              "AudioDelay" => data["AudioDelay"]["-val"] |> String.to_integer(),
              "AudioDelayLeftRear" => data["AudioDelayLeftRear"]["-val"] |> String.to_integer(),
              "AudioDelayRightRear" => data["AudioDelayRightRear"]["-val"] |> String.to_integer(),
              "Bass" => data["Bass"]["-val"] |> String.to_integer(),
              "Treble" => data["Treble"]["-val"] |> String.to_integer(),
              "SubEnabled" => data["SubEnabled"]["-val"] |> String.to_integer(),
              "SubGain" => data["SubGain"]["-val"] |> String.to_integer(),
              "SubPolarity" => data["SubPolarity"]["-val"] |> String.to_integer(),
              "SurroundLevel" => data["SurroundLevel"]["-val"] |> String.to_integer(),
              "DialogLevel" => data["DialogLevel"]["-val"] |> String.to_integer(),
              "HeightChannelLevel" => data["HeightChannelLevel"]["-val"] |> String.to_integer(),
              "MusicSurroundLevel" => data["MusicSurroundLevel"]["-val"] |> String.to_integer(),
              "SpeechEnhanceEnabled" =>
                data["SpeechEnhanceEnabled"]["-val"] |> String.to_integer(),
              "OutputFixed" => data["OutputFixed"]["-val"] |> String.to_integer(),
              "SpeakerSize" => data["SpeakerSize"]["-val"] |> String.to_integer(),
              "SubCrossover" => data["SubCrossover"]["-val"] |> String.to_integer(),
              "SurroundMode" => data["SurroundMode"]["-val"] |> String.to_integer(),
              "SurroundEnabled" =>
                data["SurroundEnabled"]["-val"]
                |> then(fn
                  "0" -> false
                  "1" -> true
                  _ -> nil
                end),
              "SonarCalibrationAvailable" =>
                data["SonarCalibrationAvailable"]["-val"]
                |> then(fn
                  "0" -> false
                  "1" -> true
                  _ -> nil
                end),
              "SonarEnabled" =>
                data["SonarEnabled"]["-val"]
                |> then(fn
                  "0" -> false
                  "1" -> true
                  _ -> nil
                end),
              "NightMode" =>
                data["NightMode"]["-val"]
                |> then(fn
                  "0" -> false
                  "1" -> true
                  _ -> nil
                end),
              "PresetNameList" =>
                case data["PresetNameList"]["-val"] do
                  str when is_binary(str) -> str |> String.split(",")
                  _ -> nil
                end
            }

            {instance_id |> String.to_integer(), data}
          end)
          |> Map.new()

        _ ->
          vars
      end

    __MODULE__ |> GenServer.cast({:update_device_state, usn, service, vars})
  end

  @doc """
  Attempts to fetch cached state values for a device from its endpoint.

  ## Parameters
    * `endpoint` - The device endpoint URL (e.g. "http://192.168.1.96:1400")
    * `service` - The service module to fetch state for (e.g. Sonos.Api.AVTransport)
    * `outputs` - List of output variable specifications to fetch, containing:
      * `original_name` - Original SOAP variable name (eg. "CurrentTrack")
      * `name` - Normalized variable name (eg. "CurrentTrack" -> :current_track)
      * `data_type` - Data type (:boolean, :string, :ui1, etc)

  ## Returns
    * `{:ok, %{outputs: result}}` - Map of variable names to coerced values
    * `{:error, reason}` - Many possibilities that are internal to the cache.
  """
  def cache_fetch(endpoint, service, inputs, outputs) when is_atom(service) and is_list(outputs) do
    output_original_names = outputs |> Enum.map(fn x -> x.original_name end)

    __MODULE__
    |> GenServer.call({:cache_fetch, endpoint, service, inputs, output_original_names})
    |> then(fn
      {:ok, %{outputs: result}} ->
        result =
          outputs
          |> Enum.map(fn x ->
            result = result[to_string(x.original_name)]
            result = Sonos.Utils.coerce_data_type(result, x.data_type)
            {x.name, result}
          end)
          |> Map.new()

        {:ok, %{outputs: result}}

      err ->
        err
    end)
  end

  def handle_cast({:update_device_state, usn, service, vars}, %State{} = state) when is_binary(service) do
    short_usn = usn |> String.replace("::urn:schemas-upnp-org:device:ZonePlayer:1", "")

    devices =
      state.devices
      |> Map.replace_lazy(short_usn, fn %Device{} = device ->
        %Device{} = device |> Device.update_state(service, vars)
      end)

    state = %State{state | devices: devices}

    {:noreply, %State{} = state}
  end

  def handle_cast({:update_device, %Sonos.SSDP.Device{} = device}, state) do
    # we need this because it is possible that a device has changed to an ip
    # that used to be used by some other device, and we should avoid confusion
    # if possible.
    state = State.remove_device(state, device)

    device |> Device.identify_task()

    {:noreply, %State{} = state}
  end

  def handle_cast({:remove_device, usn}, state) do
    state = state.devices[usn]
    |> then(fn
      nil -> :ok
      %Device{} = device ->
        state |> State.remove_device(device)
    end)

    {:noreply, %State{} = state}
  end

  def handle_call(:state, _from, state) do
    {:reply, state, %State{} = state}
  end

  def handle_call({:cache_fetch, endpoint, service, inputs, vars}, _from, %State{} = state) when is_atom(service) do
    state.usn_by_endpoint[endpoint]
    |> then(fn
      nil ->
        {:reply, {:error, :unsubscribed_device}, %State{} = state}

      usn ->
        short_usn = usn |> String.replace("::urn:schemas-upnp-org:device:ZonePlayer:1", "")
        state.devices[short_usn]
        |> then(fn
          nil ->
            {:reply, {:error, :unsubscribed_device}, %State{} = state}

          %Sonos.Device{} = device ->
            service_key = service.service_type() |> String.replace("urn:schemas-upnp-org:service:", "")

            device.state[service_key]
            |> then(fn
              nil ->
                # there is nothing cached, so subscribe so next time we will have it.
                {:ok, device_state} =
                  device
                  |> Device.subscribe(
                    service,
                    state.our_event_address,
                    timeout: @default_subscribe_timeout
                  )

                %Device{} = device = device |> Device.replace_state(service_key, device_state)
                %State{} = state = State.replace_device(state, device)

                {:reply, {:error, :unsubscribed_event}, %State{} = state}

              %Device.State{state: nil} ->
                # We have subscribed to this event type, but haven't received an initial event yet.
                {:reply, {:error, :unsubscribed_event}, %State{} = state}

              %Device.State{} = devstate ->
                # user has shown interest in this data, keep it up to date.
                if devstate |> Device.State.expiring?() do
                  device |> Device.resubscribe_task(service)
                end

                vars = vars |> Enum.map(&to_string/1)

                res = devstate.state |> Map.take(vars)

                if res |> Enum.count() < vars |> Enum.count() do
                  missing_vars = vars |> Enum.reject(fn v -> res |> Map.has_key?(v) end)

                  case Sonos.Device.State.var_replacements(
                         devstate,
                         service,
                         inputs,
                         missing_vars
                       ) do
                    {:ok, replacement_vars} ->
                      res = res |> Map.merge(replacement_vars)
                      {:reply, {:ok, %{outputs: res}}, %State{} = state}

                    {:error, {:still_missing_vars, missing_vars}} ->
                      {:reply, {:error, {:missing_vars, missing_vars}}, %State{} = state}
                  end
                else
                  {:reply, {:ok, %{outputs: res}}, %State{} = state}
                end
            end)
        end)
    end)
  end

  def handle_continue(:subscribe, state) do
    # ZonePlayer is the root device type for all sonos devices, so far as I am aware.
    # Each one has two sub devices: MediaRenderer and MediaServer.
    {:ok, ssdp_server} = "urn:schemas-upnp-org:device:ZonePlayer:1" |> Sonos.SSDP.subscribe()
    ref = Process.monitor(ssdp_server)
    state = state |> Map.put(:ssdp_server, ref)

    {:noreply, state}
  end

  def handle_info({_ref, {:resubscribed, usn, service_key, {:ok, %DateTime{} = dt}}}, state) do
    Logger.info("resubscribed to #{service_key} on #{usn}")
    usn = usn |> String.replace("::urn:schemas-upnp-org:device:ZonePlayer:1", "")
    state = %State{
      state
      | devices:
          state.devices
          |> Map.replace_lazy(usn, fn device ->
            device |> Device.rebuscribed(service_key, dt)
         end)
    }

    {:noreply, state}
  end

  def handle_info({_ref, {:identified, {:ok, %Device{} = device}}}, state) do
    short_usn = device.usn |> String.replace("::urn:schemas-upnp-org:device:ZonePlayer:1", "")
    state = update_in(state.devices, &Map.put(&1, short_usn, device))
    state = update_in(state.usn_by_endpoint, &Map.put(&1, device.endpoint, short_usn))

    {:noreply, state}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    if state.ssdp_server == ref do
      # our subscription to SSDP has died, so we need to restart to renew it.
      Logger.warning("SSDP server died, restarting Sonos server")
      {:stop, :normal, state}
    else
      {:noreply, state}
    end
  end
end
