defmodule Sonos.Server do
  use GenServer

  alias Sonos.Device
  alias Sonos.Server.State

  require Logger

  @default_subscribe_timeout 60 * 10

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

      # TODO FIXME there needs to be a periodic purging of expiring subscriptions

      {:ok, state, {:continue, :startup}}
    else
      err -> err
    end
  end

  def update_device_state(usn, service, vars) when is_binary(service) do
    # LastChange is a special element that allows you to piecemeal update variables rather than
    # replacing them all. But it is always under an InstanceID for some reason, which I've never
    # seen be anything other than 0, nonetheless we should endeavour to preserve that as the
    # instance id is used in various function calls.
    vars =
      case vars["LastChange"] do
        last_change when is_binary(last_change) ->
          last_change
          |> XmlToMap.naive_map()
          |> Map.get("Event")
          |> Sonos.Utils.coerce_to_list()
          |> Enum.map(fn
            %{"InstanceID" => %{"-val" => instance_id, "#content" => data}} ->
              [{instance_id, data}]

            %{"QueueID" => content} ->
              content
              |> Sonos.Utils.coerce_to_list()
              |> Enum.map(fn %{"-val" => queue_id, "#content" => data} ->
                {queue_id, data}
              end)
          end)
          |> Enum.concat()
          |> Map.new()

        # most if not all other types of services are just simple key-value pairs, so we can just
        # merge them with the existing state variable by variable. All states I have seen send the
        # entire value of each variable, even if they are large. For example, the `ZoneGroupState`
        # sends the state of all devices even if this one is not grouped with any others.
        _ ->
          vars
      end

    __MODULE__ |> GenServer.cast({:update_device_state, usn, service, vars})
  end

  def cache_service(endpoint, service) when is_atom(service) do
    __MODULE__ |> GenServer.cast({:cache_service, endpoint, service})
    :ok
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
  def cache_fetch(endpoint, service, inputs, outputs)
      when is_atom(service) and is_list(outputs) do
    f = Sonos.Device.Subscription.fetch_vars(inputs, outputs)

    __MODULE__
    |> GenServer.call({:cache_fetch, endpoint, service, f})
  end

  def handle_cast({:update_device_state, usn, service, vars}, %State{} = state)
      when is_binary(service) do
    short_usn = usn |> Sonos.Api.short_usn()

    state = state |> merge_state(short_usn, service, vars)

    Phoenix.PubSub.broadcast(Sonos.PubSub, "Sonos.Event", {:service_updated, short_usn, service})

    # we keep track of the last song listened to for every device
    state =
      if service == "AVTransport:1" do
        state |> song_listened_to(short_usn, vars)
      else
        state
      end

    {:noreply, %State{} = state}
  end

  def handle_cast({:update_device, %Sonos.SSDP.Device{} = device}, state) do
    # we need this because it is possible that a device has changed to an ip
    # that used to be used by some other device, and we should avoid confusion
    # if possible.
    state = State.remove_device(state, device)
    state = refresh_avtransport(state)

    device |> Device.identify_task()

    {:noreply, %State{} = state}
  end

  def handle_cast({:remove_device, usn}, %State{} = state) do
    state =
      state.devices[usn]
      |> then(fn
        nil ->
          state

        %Device{} = device ->
          state |> State.remove_device(device)
      end)

    {:noreply, %State{} = state}
  end

  def handle_cast({:cache_service, endpoint, service}, %State{} = state) do
    # We don't care about actually fetching anything, but we need to do basically
    # the exact same as it would be in the cache fetch version, but with a guaranteed no output.
    # TODO we could just factor out the logic into a separate function and have both call it.
    {:reply, _, state} =
      handle_call({:cache_fetch, endpoint, service, &Function.identity/1}, nil, state)

    {:noreply, %State{} = state}
  end

  def handle_call(:state, _from, state) do
    {:reply, state, %State{} = state}
  end

  def handle_call(:devices, _from, state) do
    devices =
      state.devices
      |> Enum.map(fn {_usn, %Sonos.Device{} = device} ->
        %Sonos.Device{
          device
          | usn:
              device.usn
              |> String.trim_leading("uuid:")
              |> String.trim_trailing("::urn:schemas-upnp-org:device:ZonePlayer:1"),
            state: nil
        }
      end)

    {:reply, devices, %State{} = state}
  end

  def handle_call({:cache_fetch, endpoint, service, state_fetcher}, _from, %State{} = state)
      when is_atom(service) do
    state.usn_by_endpoint[endpoint]
    |> then(fn
      nil ->
        {:reply, {:error, :unsubscribed_device}, %State{} = state}

      usn ->
        short_usn = usn |> Sonos.Api.short_usn()

        state.devices[short_usn]
        |> then(fn
          nil ->
            {:reply, {:error, :unsubscribed_device}, %State{} = state}

          %Sonos.Device{} = device ->
            service_key = service.short_service_type()

            device.state[service_key]
            |> then(fn
              nil ->
                # there is nothing cached, so subscribe so next time we will have it.
                {:ok, %Device{} = device} =
                  device
                  |> Device.subscribe_task(
                    service,
                    state.our_event_address,
                    timeout: @default_subscribe_timeout
                  )

                %State{} = state = State.replace_device(state, device)

                {:reply, {:error, :unsubscribed_event}, %State{} = state}

              %Device.Subscription{state: nil} ->
                # We have already subscribed to this event type, but haven't received an initial event yet.
                {:reply, {:error, :unsubscribed_event}, %State{} = state}

              # TODO subscription is well past due, unset it and resubscribe from scratch.
              %Device.Subscription{} = subscription ->
                # user has shown interest in this data, keep it up to date.
                if subscription |> Device.Subscription.expired?() do
                  # we have device state but it is so old it could be stale, so we need to
                  # resubscribe from scratch.
                  {:ok, device} =
                    device
                    |> Device.subscribe_task(
                      service,
                      state.our_event_address,
                      timeout: @default_subscribe_timeout
                    )

                  state = state |> State.replace_device(device)
                  {:reply, {:error, :expired_subscription}, %State{} = state}
                else
                  # we have the state, but it is going to expire at some point, so we should
                  # resubscribe to keep it up to date for awhile longer.
                  state =
                    if subscription |> Device.Subscription.expiring?() do
                      {:ok, device} = device |> Device.resubscribe_task(service)
                      state |> State.replace_device(device)
                    else
                      state
                    end

                  res = subscription |> state_fetcher.()

                  {:reply, {:ok, %{outputs: res}}, %State{} = state}
                end
            end)
        end)
    end)
  end

  def handle_continue(:startup, state) do
    # ZonePlayer is the root device type for all sonos devices, so far as I am aware.
    # Each one has two sub devices: MediaRenderer and MediaServer.

    {:ok, ssdp_server} = "urn:schemas-upnp-org:device:ZonePlayer:1" |> Sonos.SSDP.subscribe()
    ref = Process.monitor(ssdp_server)
    state = state |> Map.put(:ssdp_server, ref)

    # to follow songs, we have to always have a subscription to the AVTransport service, and
    # we must maintain it at all costs.
    self() |> Process.send_after(:periodic_update, :timer.seconds(10))

    {:noreply, state}
  end

  def handle_info(:periodic_update, %State{} = state) do
    state = state |> refresh_avtransport()
    self() |> Process.send_after(:periodic_update, :timer.seconds(20))

    {:noreply, %State{} = state}
  end

  def handle_info(
        {_ref, {:subscribed, usn, room_name, service_key, {:ok, {sid, max_age}}}},
        %State{} = state
      ) do
    Logger.info(
      "subscribed to #{service_key} on #{room_name} at #{Timex.now()} with sid #{sid} and max_age #{max_age}"
    )

    usn = usn |> Sonos.Api.short_usn()

    state = %State{
      state
      | devices:
          state.devices
          |> Map.replace_lazy(usn, fn device ->
            device |> Device.subscribed(service_key, sid, max_age)
          end)
    }

    {:noreply, %State{} = state}
  end

  def handle_info(
        {_ref, {:resubscribed, usn, room_name, service_key, res}},
        %State{} = state
      ) do
    state =
      case res do
        {:error, {:unable_to_resubscribe, res}} ->
          usn = usn |> Sonos.Api.short_usn()

          # this can happen if we waited too long, not a huge deal but we should try to minimize
          # this if possible. It could also happen if the device rebooted and lost our subscription.
          # this just means next time we run a command for this service we will have to fetch it, and at
          # that time we will create a new subscription.
          Logger.warning(
            "unable to resubscribe to #{service_key} on #{usn} (#{room_name}) at #{Timex.now()}: #{inspect(res)}"
          )

          %State{
            state
            | devices:
                state.devices
                |> Map.replace_lazy(
                  usn,
                  fn device -> device |> Device.resubscribe_failed(service_key) end
                )
          }

        {:ok, %DateTime{} = dt} ->
          usn = usn |> Sonos.Api.short_usn()

          Logger.info("resubscribed to #{service_key} on #{usn} (#{room_name}) at #{Timex.now()}")

          %State{
            state
            | devices:
                state.devices
                |> Map.replace_lazy(usn, fn device ->
                  device |> Device.rebuscribed(service_key, dt)
                end)
          }
      end

    {:noreply, %State{} = state}
  end

  def handle_info({_ref, {:identified, {:ok, %Device{} = device}}}, %State{} = state) do
    short_usn = device.usn |> Sonos.Api.short_usn()
    state = update_in(state.devices, &Map.put(&1, short_usn, device))
    state = update_in(state.usn_by_endpoint, &Map.put(&1, device.endpoint, short_usn))

    {:noreply, %State{} = state}
  end

  def handle_info({_ref, {:identified, {:error, {:cannot_identify, err}}}}, %State{} = state) do
    Logger.warning("could not identify #{inspect(err)}")

    {:noreply, %State{} = state}
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

  # For each known device, ensure that we have an active up to date subscription to the AVTransport service.
  # This is the only service that we need to ensure is always up to date, as it is the only one that
  # is needed to know what tracks are being played by a device, which is something we have to track ourselves.
  defp refresh_avtransport(%State{} = state) do
    %State{} =
      state.usn_by_endpoint
      |> Enum.reduce(state, fn {endpoint, usn}, state ->
        api = state.devices[usn].api
        service = Module.concat(api, MediaRenderer.AVTransport)
        {:noreply, state} = handle_cast({:cache_service, endpoint, service}, state)
        state
      end)
  end

  defp song_listened_to(%State{} = state, short_usn, vars) do
    if vars |> Enum.count() > 1 do
      # If this ever happens I'd like to know about it so I can find out what circumstances it happens.
      Logger.warning("multiple queues for avtransport: #{inspect(vars)}")
    end

    case vars do
      %{"0" => %{"CurrentTrackMetaData" => %{"-val" => track_meta_data}}}
      when track_meta_data != "" ->
        devices =
          state.devices
          |> Map.replace_lazy(short_usn, fn %Device{} = device ->
            device |> Device.song_played(track_meta_data)
          end)

        %State{state | devices: devices}

      _ ->
        state
    end
  end

  defp merge_state(%State{} = state, short_usn, service, vars) do
    devices =
      state.devices
      |> Map.replace_lazy(short_usn, fn %Device{} = device ->
        %Device{} = device |> Device.merge_state(service, vars)
      end)

    %State{state | devices: devices}
  end
end
