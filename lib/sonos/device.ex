defmodule Sonos.Device do
  defstruct ip: nil, usn: nil, description_url: nil, household: nil, description: nil

  alias __MODULE__

  def from_headers(headers, ip) do
    house = headers["x-rincon-household"] || :unknown_household
    location = headers["location"] || :unknown_location
    usn = headers["usn"] || :unknown_location

    %Sonos.Device {
      usn: usn,
      ip: ip,
      description_url: location,
      household: house,
    }
  end

  def uuid(%Device{} = dev) do
    Regex.run(~r/(uuid:RINCON[^:]+)::/, dev.usn) |> case do
      [_,res] -> {:ok, res}
      _ -> {:error, {:invalid_usn, dev.usn}}
    end
  end

  def endpoint(%Device{} = device) do
    #FIXME ipv6?
    "http://#{device.ip}:1400"
  end

  def identified?(%Device{} = dev) do
    !is_nil(dev.description)
  end

  def identify(%Device{} = dev, opts \\ []) do
    retries = opts[:retries] || 3

    opts = [
      timeout: 2000,
      recv_timeout: 1000,
    ]
    dev.description_url |> HTTPoison.get([], opts) |> case do
      {:ok, %HTTPoison.Response{ status_code: 200 } = resp} ->
        {:ok, resp.body |> Device.Description.from_response()}
      {:error, err} ->
        if retries == 0 do
          {:error, {:cannot_identify, err}}
        else
          dev |> identify(retries: retries - 1)
        end
    end
  end
end
