# NOTES
# bootid.upnp.org - increments each time the device rebooted,
#    signifying that its information may have changed.

# first line in ssdp is always one of
# - NOTIFY * HTTP/1.1\r\n
# - M-SEARCH * HTTP/1.1\r\n
# - HTTP/1.1 200 OK\r\n

# uniquely identify a device by the following (bootid update means remove the old one)
# "usn" + "bootid.upnp.org"

# descriptions of all of these services
# https://sonos.svrooij.io/services/queue

# nt - notification type (such as urn:smartspeaker-audio:service:SpeakerGroup:1)
#    "upnp:rootdevice" - root device
#    " anything else" - various sub services of the device
# usn -> unique service name such as:
#   - uuid:RINCON_48A6B870E00401400::urn:smartspeaker-audio:service:SpeakerGroup:1)
#   - uuid:RINCON_347E5C76283501400_MR::urn:schemas-upnp-org:service:GroupRenderingControl:1
#   - uuid:RINCON_347E5C76283501400_MR::urn:schemas-sonos-com:service:Queue:1
#   - uuid:RINCON_347E5C76283501400_MR::urn:schemas-upnp-org:service:AVTransport:1
#   - uuid:RINCON_347E5C76283501400::urn:schemas-tencent-com:service:QPlay:1

# location - http resource for the device to find info about the device
# securelocation.upnp.org - https resource for the device for the above

defmodule Sonos.SSDP.Message do
  alias __MODULE__
  defstruct type: nil, headers: %{}

  def from_response(str) do
    res =
      str
      |> String.split("\r\n")
      # |> IO.inspect(label: "SSDP message")
      |> Enum.reduce(nil, fn
        "NOTIFY * HTTP/1.1", nil ->
          %Message{type: :NOTIFY}

        "HTTP/1.1 200 OK", nil ->
          %Message{type: :OK}

        "M-SEARCH * HTTP/1.1", nil ->
          %Message{type: :"M-SEARCH"}

        header, %Message{} = msg ->
          Regex.run(~r/^([^:]+):(?: (.*))?$/, header)
          |> case do
            [_, header, val] ->
              %Message{
                msg
                | headers:
                    msg.headers |> Map.put(header |> String.downcase(), val |> String.trim())
              }

            [_, header] ->
              %Message{msg | headers: msg.headers |> Map.put(header |> String.downcase(), nil)}

            nil ->
              msg

            other ->
              other |> IO.inspect(label: "SSDP response parse error")
              msg
          end
      end)
      |> case do
        %Message{headers: headers} = msg ->
          headers =
            headers
            |> Enum.sort_by(fn {k, _} ->
              # sort all headers that are like foo.upnp.org together instead of randomly and get
              # some sort of predictable order out of them.
              k |> String.split(".") |> Enum.reverse() |> Enum.join(".")
            end)

          %Message{msg | headers: headers}

        _ ->
          nil
      end
    # TODO FIXME some actual error detection here would be nice.
    {:ok, res}
  end
end
