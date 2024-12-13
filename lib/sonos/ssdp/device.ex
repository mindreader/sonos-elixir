defmodule Sonos.SSDP.Device do

  alias __MODULE__
  alias Sonos.SSDP.Message

  defstruct bootid: nil,
            usn: nil,
            ip: nil,
            location: nil,
            server: nil,
            max_age: nil,
            last_seen: nil


  def endpoint(%Device{} = device) do
    # strictly speaking, the various endpoints of devices could be different,
    # but in practice they are all the same device ip and port as the main
    # device description, and that makes things a lot simpler for us.
    device.location
    |> URI.parse()
    |> Map.put(:path, nil)
    |> URI.to_string()
  end

  def last_seen_now(%Device{} = msg) do
    %Device{ msg | last_seen: Timex.now() |> Timex.to_unix() }
  end

  def from_headers(%Message{} = msg, ip) do
    type = msg.type
    headers = msg.headers |> Map.new()

    bootid = headers["bootid.upnp.org"]
    server = headers["server"]
    usn = headers["usn"]
    location = headers["location"]

    last_seen = Timex.now() |> Timex.to_unix()

    max_age = headers |> Sonos.Utils.max_age_parse()

    if type in [:NOTIFY, :OK] && bootid && location && server && usn do
      res = %__MODULE__{
        bootid: bootid,
        ip: ip,
        location: location,
        server: server,
        usn: usn,
        max_age: max_age,
        last_seen: last_seen
      }

      {:ok, res}
    else
      {:error, {:invalid_message, msg}}
    end
  end
end
