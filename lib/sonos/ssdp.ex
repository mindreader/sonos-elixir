defmodule Sonos.SSDP do
  use GenServer
  require Logger

  # multicast group and port, any messages sent here are received by all speakers
  # we can also receive replies from the speakers on this port
  @multicast_group {239, 255, 255, 250}
  @multicast_port 1900

  def start_link(opts) do
    name = opts |> Keyword.get(:name, __MODULE__)
    GenServer.start_link(__MODULE__, [], name: name)
  end

  defmodule State do
    defstruct socket: nil
  end

  def init(_args) do
    state = %State{
      socket: port()
    }

    {:ok, state}
  end

  def options do
    [
      # general options
      mode: :binary,
      reuseaddr: true,
      active: 10,
      # active: true, # TODO FIXME use active: 1 and passive udp

      # multicast receiving options (we're listening on all interfaces)
      add_membership: {@multicast_group, {0, 0, 0, 0}},

      # multicast sending options
      # we're sending through all interfaces which support multicast
      multicast_if: {0, 0, 0, 0},
      # don't send our own events back to ourselves
      multicast_loop: false,
      # hop to at least 2 routers away
      multicast_ttl: 4
    ]
  end

  def port do
    Logger.info("Opening multicast port #{inspect(@multicast_port)}")

    # we also receive messages from the speakers on this port.
    {:ok, socket} = :gen_udp.open(@multicast_port, options())
    socket
  end

  def search do
    "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:reservedSSDPport\r\nMAN: ssdp:discover\r\nMX: 1\r\nST: urn:schemas-upnp-org:device:ZonePlayer:1\r\n"
  end

  def scan(search \\ search()) do
    Logger.info("Scanning for devices...")

    __MODULE__ |> GenServer.cast({:scan, search})
  end

  def handle_cast({:scan, search}, state) do
    :ok = state.socket |> :gen_udp.send(@multicast_group, @multicast_port, search)
    {:noreply, state}
  end

  def handle_info({:udp_passive, _port}, state) do
    :inet.setopts(state.socket, active: 10)
    {:noreply, state}
  end

  def handle_info({:udp, port, ip, _something, body}, state) do
    Logger.info("Received message from #{inspect(ip)} from port #{inspect(port)}")

    msg = body |> response_parse()

    msg |> IO.inspect(label: "SSDP message")

    # msg |> SSDP.response_parse |> Device.from_headers(ip) |> case do
    #   {:ok, %Device{} = device} ->
    #     uuid = device |> Device.uuid()

    #     state = %State { state |
    #       devices: state.devices |> Map.put(uuid, device)
    #     }
    #     Task.start(Sonos, :identify, [device])
    #     {:noreply, state}

    #   _ ->
    #     {:noreply, state}
    # end
    {:noreply, state}
  end

  def handle_info(msg, state) do
    Logger.info("Unhandled message #{inspect(msg)}")
    {:noreply, state}
  end

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

  defmodule Message do
    defstruct type: nil, headers: nil
  end

  def response_parse(str) do
    str
    |> String.split("\r\n")
    |> Enum.reduce(nil, fn
      "NOTIFY * HTTP/1.1", nil ->
        %Message{type: :NOTIFY, headers: %{}}

      "HTTP/1.1 200 OK", nil ->
        %Message{type: :OK, headers: %{}}

      "M-SEARCH * HTTP/1.1", nil ->
        %Message{type: :"M-SEARCH", headers: %{}}

      header, %Message{} = msg ->
        Regex.run(~r/^([^:]+):(?: (.*))?$/, header)
        |> case do
          [_, header, val] ->
            %Message{
              msg
              | headers: msg.headers |> Map.put(header |> String.downcase(), val |> String.trim())
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
  end
end
