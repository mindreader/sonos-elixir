defmodule Sonos.Device do
  alias Sonos.Device.Subscription

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

  def replace_state(%Device{} = device, service, %Subscription{} = state)
      when is_binary(service) do
    %Device{device | state: device.state |> Map.put(service, state)}
  end

  def merge_state(%Device{} = device, service, vars) when is_binary(service) do
    device_state =
      device.state
      |> Map.replace_lazy(service, fn %Subscription{} = state ->
        %Subscription{} = state |> Subscription.merge(service, vars)
      end)

    %Device{device | state: device_state}
  end

  def subscribe_task(%Sonos.Device{} = device, service, event_address, opts \\ [])
      when is_atom(service) do
    timeout = opts[:timeout] || 60 * 5

    service_key = service.short_service_type()

    Task.Supervisor.async(Sonos.Tasks, fn ->
      {:subscribed, device.usn, device.room_name, service_key,
       subscribe(device, service, event_address, opts)}
    end)

    device_state = Subscription.new(timeout: timeout)
    device = device |> replace_state(service_key, device_state)

    {:ok, %Device{} = device}
  end

  def call(%Sonos.Device{} = device, service, function, inputs)
      when is_atom(service) and is_atom(function) do
    Module.concat([device.api, service]) |> apply(function, [device.endpoint | inputs])
  end

  def subscribe(%Sonos.Device{} = device, service, event_address, opts \\ [])
      when is_atom(service) do
    timeout = opts[:timeout] || 60 * 5

    Logger.info(
      "subscribing to #{service.short_service_type()} on #{device.usn |> Sonos.Api.short_usn()} (#{device.room_name})"
    )

    event_endpoint = "#{event_address}/#{device.usn}/#{service.service_type()}"

    service
    |> apply(:subscribe, [device.endpoint, event_endpoint, [timeout: timeout]])
    |> then(fn
      {:ok, %HTTPoison.Response{headers: headers, status_code: 200}} ->
        # this is the "subscription id", and it can be used to renew a subscription that
        # has not yet expired.
        {:ok, {_sid, _max_age}} = headers |> Sonos.Utils.subscription_parse()

      err ->
        err
    end)
  end

  def subscribed(%Device{} = device, service, sid, max_age) when is_binary(service) do
    device_state =
      device.state
      |> Map.replace_lazy(service, fn %Subscription{} = state ->
        %Subscription{state | subscription_id: sid, max_age: max_age}
      end)

    %Device{device | state: device_state}
  end

  def resubscribe_task(%Sonos.Device{} = device, service) when is_atom(service) do
    service_key = service.short_service_type()

    device.state[service_key]
    |> then(fn
      nil ->
        {:error, :no_state}

      %Subscription{subscription_id: nil} ->
        # we process the subscription request asynchronously because we don't want to block the
        # caller, we should never attempt this but if something wierd happens, better not to crash.
        {:error, :no_subscription_id_yet}

      %Subscription{} = state ->
        Task.Supervisor.async(Sonos.Tasks, fn ->
          {:resubscribed, device.usn, device.room_name, service_key,
           resubscribe(device, service, state)}
        end)

        device_state = state |> Subscription.resubscribe_sent(Timex.now())
        device = device |> replace_state(service_key, device_state)
        {:ok, %Device{} = device}
    end)
  end

  def resubscribe(%Sonos.Device{} = device, service, %Subscription{} = state) do
    if state.resubscribe_last_sent_at &&
         state.resubscribe_last_sent_at
         |> Timex.after?(Timex.now() |> Timex.shift(seconds: -10)) do
      {:ok, state.resubscribe_last_sent_at}
    else
      service
      |> apply(:resubscribe, [device.endpoint, state.subscription_id, [timeout: state.timeout]])
      |> then(fn
        {:ok, %HTTPoison.Response{status_code: 200}} ->
          {:ok, Timex.now()}

        {:ok, %HTTPoison.Response{} = resp} ->
          {:error, {:unable_to_resubscribe, resp}}

        err ->
          err
      end)
    end
  end

  def rebuscribed(%Device{} = device, service, %DateTime{} = dt) when is_binary(service) do
    device_state =
      device.state
      |> Map.replace_lazy(service, fn %Subscription{} = state ->
        %Subscription{} = state |> Subscription.resubscribed(dt)
      end)

    %Device{device | state: device_state}
  end

  def resubscribe_failed(%Device{} = device, service) when is_binary(service) do
    device_state = device.state |> Map.delete(service)
    %Device{device | state: device_state}
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
