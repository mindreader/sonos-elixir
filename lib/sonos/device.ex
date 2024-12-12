defmodule Sonos.Device do
  defstruct usn: nil,
            ip: nil,
            room_name: nil,
            model_name: nil,
            model_number: nil,
            state: nil

  alias __MODULE__
  require Logger

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
        description = resp.body |> Device.Description.from_response()
        device = %Device{
          usn: dev.usn,
          ip: dev.ip,
          room_name: description.room_name,
          model_name: description.model_name,
          model_number: description.model_number,
          state: %{}
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
