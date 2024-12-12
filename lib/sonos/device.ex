defmodule Sonos.Device do
  defstruct ip: nil,
            port: nil,
            usn: nil,
            room_name: nil,
            model_name: nil,
            model_number: nil

  alias __MODULE__
  require Logger

  def identify(%Sonos.SSDP.Device{} = dev, opts \\ []) do
    retries = opts[:retries] || 3

    opts = [
      timeout: 2000,
      recv_timeout: 1000
    ]

    dev.description_url
    |> HTTPoison.get([], opts)
    |> case do
      {:ok, %HTTPoison.Response{status_code: 200} = resp} ->
        description = resp.body |> Device.Description.from_response()
        device = %Device{
          ip: dev.ip,
          port: dev.port,
          usn: dev.usn,
          room_name: description.room_name,
          model_name: description.model_name,
          model_number: description.model_number
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
