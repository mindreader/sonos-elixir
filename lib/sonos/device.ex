defmodule Sonos.Device do
  defstruct usn: nil,
            ip: nil,
            endpoint: nil,
            room_name: nil,
            model_name: nil,
            model_number: nil,
            state: nil,
            api: nil

  alias __MODULE__
  require Logger

  def api(%Device{} = device, device_name, service_name)
    when is_atom(device_name) and is_atom(service_name) do
    Module.concat([device.api, device_name, service_name])
  end

  def call(%Device{} = device, device_name, service_name, function_name, args \\ [])
    when is_atom(device_name) and is_atom(service_name) and is_atom(function_name) do
    args = [device.endpoint | args]
    api(device, device_name, service_name) |> apply(function_name, args)
  end

  def subscribe_task(%Device{} = device, event_address) do
    [
      ZonePlayer.AlarmClock
    ]
    |> Enum.each(fn service ->
      mod = device.api |> Module.concat(service)
      event_endpoint = "#{event_address}/#{device.usn}/#{mod.service_type()}" |> IO.inspect(label: "event_endpoint")
      mod |> apply(:subscribe, [device.endpoint, event_endpoint])
    end)

  end

  def identify_task(%Sonos.SSDP.Device{} = dev, opts \\ []) do

    Task.Supervisor.async(Sonos.Tasks, fn ->
      identify(dev, opts)
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
          api: Sonos.Utils.model_detection(description.model_number)
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
