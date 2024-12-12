defmodule Sonos.SSDP do
  alias __MODULE__.Message
  alias __MODULE__.Device

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
    defstruct socket: nil,
              # Map(host -> Device)
              devices: %{}

    def replace_device(state, device) do
      devices = state.devices |> Map.put(device.usn, device)
      state |> Map.put(:devices, devices)
    end

    def remove_device(state, usn) do
      devices = state.devices |> Map.delete(usn)
      state |> Map.put(:devices, devices)
    end
  end

  def init(_args) do
    state = %State{
      socket: port(),
      devices: %{}
    }

    {:ok, state, {:continue, :scan}}
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
    # This technically gets all sonos devices I'm aware of, but I'm going to get constant chatter from other
    # ssdp enabled devices and will have to filter them out anyways, so I might as well use the standard ssdp
    # root device query instead in case there is some future where a device doesn't advertise ZonePlayer.
    # "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:reservedSSDPport\r\nMAN: ssdp:discover\r\nMX: 1\r\nST: urn:schemas-upnp-org:device:ZonePlayer:1\r\n"
    "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: ssdp:discover\r\nMX: 1\r\nST: upnp:rootdevice\r\n"
  end

  def scan(search \\ search()) do
    __MODULE__ |> GenServer.cast({:scan, search})
  end

  def handle_continue(:scan, state) do
     handle_cast({:scan, search()}, state)
  end

  def handle_call(:state, _from, state) do
    {:reply, state, state}
  end

  def handle_cast({:scan, search}, state) do
    Logger.info("Scanning for devices...")

    :ok = state.socket |> :gen_udp.send(@multicast_group, @multicast_port, search)
    {:noreply, state}
  end

  def handle_info({:udp_passive, _port}, state) do
    :inet.setopts(state.socket, active: 10)
    {:noreply, state}
  end

  def handle_info({:udp, port, ip, _something, body}, state) do
    Logger.info("Received message from #{inspect(ip)} from port #{inspect(port)}")

    with {:ok, %Message{} = msg} <- body |> Message.from_response(),
         headers <- msg.headers |> Map.new(),
         usn when is_binary(usn) <- headers["usn"],
         nts <- headers["nts"] do
      # device = Sonos.Device.from_headers(msg.headers, ip)
      # device |> IO.inspect(label: "SSDP device")


      action = cond do
        # an HTTP response to our scan will not have an nts, but is an advertisement that it exists.
        is_nil(nts) -> :update
        # a NOTIFY with NTS of ssdp:byebye means the device is going away.
        nts == "ssdp:byebye" -> :remove
        # a NOTIFY with any other NTS (always ssdp:alive) is an advertisement that the device is still alive.
        nts == "ssdp:alive" -> :update
        true ->
          # this shouldn't happen, but who knows what non compliant devices are out there.
          Logger.warn("Unhandled NTS on a message from #{inspect(ip)}: #{inspect(nts)}")
          :update
      end

      state =
        case {action, state.devices[usn]} do
          {:remove, nil} ->
            state

          {:remove, device} ->
            state |> State.remove_device(usn)

          {:update, nil} ->
            with {:ok, %Device{} = device} <- Device.from_headers(msg, ip) do
              # TODO cast a new device to Server
              state |> State.replace_device(device)
            else
              error ->
                Logger.info("Error parsing message #{inspect(error)}")
                state
            end

          {:update, %Device{bootid: old_bootid} = device} ->
            device = device |> Device.last_seen_now()
            # the boot id increments when the device reboots, meaning we need to update
            # our knowledge about the device as fields may have changed.
            if headers["bootid.upnp.org"] != old_bootid do
              # TODO cast a device refresh to Server
            end


            state |> State.replace_device(device)
        end

      {:noreply, state}
    else
      error ->
        Logger.info("Error parsing message #{inspect(error)}")
        {:noreply, state}
    end
  end

  def handle_info(msg, state) do
    Logger.info("Unhandled message #{inspect(msg)}")
    {:noreply, state}
  end
end
