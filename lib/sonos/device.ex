defmodule Sonos.Device do
  defmodule State do
    alias __MODULE__
    defstruct state: nil, subscription_id: nil, timeout: nil, max_age: nil, last_updated_at: nil

    def new(subscription_id, opts \\ []) do
      timeout = opts[:timeout] || 60 * 5
      max_age = opts[:max_age] || 60

      %State{
        # service_key is a truncated version of the service type. It is truncated so that
        # it can be specified in our endpoint url. (sonos devices don't support long urls)
        # Map (service_key -> Map (var_name -> value))
        state: nil,

        # returned from the original subscribe call
        subscription_id: subscription_id,

        # we request this timeout on subscribe/resubscribe soap calls.
        timeout: timeout,

        # this is how long it is willing to persist a subscription
        max_age: max_age,

        # this is the last time we saw a message from them for this device.
        last_updated_at: Timex.now()
      }
    end

    def update(%State{} = state, vars, _opts \\ []) do
      %State{state | state: vars, last_updated_at: Timex.now()}
    end

    def resubscribed(%State{} = state, %DateTime{} = dt) do
      %State{state | last_updated_at: dt}
    end

    def expiring?(%State{} = state) do
      half_max_age = state.max_age |> div(2)
      state.last_updated_at |> Timex.shift(seconds: half_max_age) |> Timex.before?(Timex.now())
    end

    def var_replacements(%State{} = state, service, inputs, missing_vars) do
      case service.service_type() do
        "urn:schemas-upnp-org:service:RenderingControl:1" ->
          alternative_vars = %{
            "CurrentVolume" => fn state ->
              state[inputs[:InstanceID]]["Volume"]["#{inputs[:Channel]}"]
            end,
            "CurrentMute" => fn state ->
              state[inputs[:InstanceID]]["Mute"]["#{inputs[:Channel]}"]
            end,
            "CurrentLoudness" => fn state ->
              state[inputs[:InstanceID]]["Loudness"]["#{inputs[:Channel]}"]
            end,
            "CurrentValue" => fn state ->
              state[inputs[:InstanceID]]["#{inputs[:EQType]}"]
            end
          }

          res =
            missing_vars
            |> Enum.reduce(%{}, fn var, accum ->
              case alternative_vars[var] do
                nil -> accum
                f -> accum |> Map.put(var, f.(state.state))
              end
            end)

          if res |> Enum.count() == missing_vars |> Enum.count() do
            {:ok, res}
          else
            still_missing_vars = missing_vars |> Enum.reject(fn v -> res |> Map.has_key?(v) end)
            {:error, {:still_missing_vars, still_missing_vars}}
          end

        "urn:schemas-upnp-org:service:GroupRenderingControl:1" ->
          alternative_vars = %{
            "CurrentVolume" => "GroupVolume",
            "CurrentMute" => "GroupMute"
          }

          res =
            missing_vars
            |> Enum.reduce(%{}, fn var, accum ->
              case alternative_vars[var] do
                nil ->
                  accum

                alternate ->
                  accum |> Map.put(var, state.state[alternate])
              end
            end)

          if res |> Enum.count() == missing_vars |> Enum.count() do
            {:ok, res}
          else
            still_missing_vars = missing_vars |> Enum.reject(fn v -> res |> Map.has_key?(v) end)
            {:error, {:still_missing_vars, still_missing_vars}}
          end

        _ ->
          {:error, {:still_missing_vars, missing_vars}}
      end
    end
  end

  defstruct usn: nil,
            ip: nil,
            endpoint: nil,
            room_name: nil,
            model_name: nil,
            model_number: nil,
            state: nil,
            api: nil,
            max_age: nil,
            last_seen_at: nil

  alias __MODULE__
  require Logger

  def replace_state(%Device{} = device, service, %State{} = state) when is_binary(service) do
    %Device{device | state: device.state |> Map.put(service, state)}
  end

  def rebuscribed(%Device{} = device, service, %DateTime{} = dt) when is_binary(service) do
    device_state = device.state |> Map.replace_lazy(service, fn %State{} = state ->
      %State{} = state |> State.resubscribed(dt)
    end)

    %Device{device | state: device_state}
  end

  def update_state(%Device{} = device, service, vars) when is_binary(service) do
    device_state = device.state |> Map.replace_lazy(service, fn %State{} = state ->
      %State{} = state |> State.update(vars)
    end)
    %Device{device | state: device_state}
  end

  #  as much as I'd like to background this, I have to be ready to receive the events
  #  from the subscription it creates, before those events can be processed.
  #  def subscribe_task(%Sonos.Device{} = device, service, event_address, opts \\ []) do
  #    Task.Supervisor.async(Sonos.Tasks, fn ->
  #      {:subscribed, service, subscribe(device, service, event_address, opts)}
  #    end)
  #  end

  def subscribe(%Sonos.Device{} = device, service, event_address, opts \\ []) when is_atom(service) do
    timeout = opts[:timeout] || 60 * 5

    Logger.info("subscribing to #{service.service_type()} on #{device.usn}")

    event_endpoint = "#{event_address}/#{device.usn}/#{service.service_type()}"

    service
    |> apply(:subscribe, [device.endpoint, event_endpoint, [timeout: timeout]])
    |> then(fn
      {:ok, %HTTPoison.Response{headers: headers, status_code: 200}} ->
        # this is the "subscription id", and it can be used to renew a subscription that
        # has not yet expired.
        {:ok, {sid, max_age}} = headers |> Sonos.Utils.subscription_parse()

        device_state = State.new(sid, max_age: max_age, timeout: timeout)

        if sid do
          {:ok, %State{} = device_state}
        else
          {:error, :no_sid}
        end

      err ->
        err
    end)
  end

  def resubscribe_task(%Sonos.Device{} = device, service) when is_atom(service) do
    Task.Supervisor.async(Sonos.Tasks, fn ->
      service_key =
        service.service_type()
        |> String.replace("urn:schemas-upnp-org:service:", "")

      {:resubscribed, device.usn, service_key, resubscribe(device, service)}
    end)
  end

  def resubscribe(%Sonos.Device{} = device, service) do
    service_key =
      service.service_type()
      |> String.replace("urn:schemas-upnp-org:service:", "")

    device.state[service_key]
    |> then(fn
      nil ->
        {:error, :no_state}

      %State{} = state ->
        service
        |> apply(:resubscribe, [device.endpoint, state.subscription_id, [timeout: state.timeout]])
        |> then(fn
          {:ok, %HTTPoison.Response{status_code: 200}} ->
            {:ok, Timex.now()}
        end)
    end)
  end

  def identify_task(%Sonos.SSDP.Device{} = dev, opts \\ []) do
    Task.Supervisor.async(Sonos.Tasks, fn ->
      {:identified, identify(dev, opts)}
    end)
  end

  def identify(%Sonos.SSDP.Device{} = dev, opts \\ []) do
    retries = opts[:retries] || 3

    opts = [
      timeout: 2000,
      recv_timeout: 1000
    ]

    dev.location
    |> HTTPoison.get([], opts)
    |> case do
      {:ok, %HTTPoison.Response{status_code: 200} = resp} ->
        endpoint = dev |> Sonos.SSDP.Device.endpoint()
        description = resp.body |> Device.Description.from_response()

        device = %Device{
          usn: dev.usn,
          ip: dev.ip,
          endpoint: endpoint,
          room_name: description.room_name,
          model_name: description.model_name,
          model_number: description.model_number,
          state: %{},
          api: Sonos.Utils.model_detection(description.model_number),
          max_age: dev.max_age,
          last_seen_at: dev.last_seen_at
        }

        {:ok, device}

      {:error, err} ->
        if retries == 0 do
          {:error, {:cannot_identify, err}}
        else
          dev |> identify(retries: retries - 1)
        end
    end
  end
end
