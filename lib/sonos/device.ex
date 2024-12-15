defmodule Sonos.Device do

  defmodule State do
    alias __MODULE__
    defstruct state: nil, expires_at: nil

    def new(vars, opts \\ []) do
      timeout = opts[:timeout] || 60

      %State{
        state: vars,
        expires_at: Timex.now() |> Timex.shift(seconds: timeout)
      }
    end

    def should_refresh?(%State{} = state) do
      within_20_seconds = Timex.now() |> Timex.shift(seconds: 20)
      state.expires_at |> Timex.before?(within_20_seconds)
    end

    def expiring?(%State{} = state) do
      state.expires_at |> Timex.before?(Timex.now())
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

  def update_state(%Device{} = device, service, vars) do
    %Device{ device |
      state: device.state |> Map.put(service, State.new(vars))
    }
  end

  def subscribe_task(%Sonos.Device{} = device, service, event_address) do
    IO.puts("subscribing to #{service.service_type()} on #{device.usn}")
    event_endpoint = "#{event_address}/#{device.usn}/#{service.service_type()}"
    service |> apply(:subscribe, [device.endpoint, event_endpoint])
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
