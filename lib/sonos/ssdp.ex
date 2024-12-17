defmodule Sonos.SSDP do
  alias __MODULE__

  use GenServer
  require Logger

  # multicast group and port, any messages sent here are received by all speakers
  # we can also receive replies from the speakers on this port
  @multicast_group {239, 255, 255, 250}
  @multicast_port 1900

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  defmodule State do
    alias __MODULE__

    defstruct socket: nil,
              # Map(host -> Device)
              devices: %{},
              subscribers: %{}

    def replace_device(%State{} = state, device) do
      devices = state.devices |> Map.put(device.usn, device)
      %State{state | devices: devices}
    end

    def remove_device(%State{} = state, usn) do
      devices = state.devices |> Map.delete(usn)
      %State{state | devices: devices}
    end

    def stale_devices(%State{} = state) do
      state.devices
      |> Map.filter(fn {_usn, device} ->
        # Logger.info("Checking device #{usn} last seen at #{inspect(device.last_seen_at)}")
        Timex.now() |> Timex.after?(device.last_seen_at |> Timex.shift(seconds: device.max_age))
      end)
    end
  end

  def init(_args) do
    state = %State{
      socket: port(),
      devices: %{}
    }

    {:ok, state, {:continue, :startup}}
  end

  def options do
    [
      # general options
      mode: :binary,
      reuseaddr: true,
      active: 10,

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
    "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:reservedSSDPport\r\nMAN: ssdp:discover\r\nMX: 1\r\nST: urn:schemas-upnp-org:device:ZonePlayer:1\r\n"

    # "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: ssdp:discover\r\nMX: 1\r\nST: upnp:rootdevice\r\n"
  end

  def subscribe(subject) do
    {:ok, _} = GenServer.call(__MODULE__, {:subscribe, self(), subject})
  end

  def scan(search \\ search()) do
    __MODULE__ |> GenServer.cast({:scan, search})
  end

  def handle_continue(:startup, state) do
    handle_cast({:scan, search()}, state)
    Process.send_after(self(), :remove_old_devices, :timer.seconds(60))
    {:noreply, state}
  end

  def handle_call(:state, _from, state) do
    {:reply, state, state}
  end

  def handle_call({:subscribe, pid, subject}, _from, state) do
    Logger.info("Subscribing #{__MODULE__} to #{inspect(subject)}")
    subscriber = SSDP.Subscriber.new(pid, subject)
    state = update_in(state.subscribers, &Map.put(&1, pid, subscriber))

    state.devices
    |> Enum.each(fn {_usn, device} ->
      if SSDP.Subscriber.relevant_device(subscriber, device) do
        GenServer.cast(pid, {:update_device, device})
      end
    end)

    pid |> Process.monitor()
    {:reply, {:ok, self()}, state}
  end

  def handle_cast({:scan, search}, state) do
    Logger.info("Scanning for devices...")

    :ok = state.socket |> :gen_udp.send(@multicast_group, @multicast_port, search)
    {:noreply, state}
  end

  def handle_info(:remove_old_devices, state) do
    stale_devices = State.stale_devices(state)

    if stale_devices |> Enum.any?() do
      Logger.info("Removing stale devices #{stale_devices |> Map.keys() |> Enum.join(", ")}")
    end

    state =
      stale_devices
      |> Enum.reduce(state, fn {usn, device}, state ->
        state.subscribers
        |> Enum.each(fn {pid, subscriber} ->
          if SSDP.Subscriber.relevant_device(subscriber, device) do
            GenServer.cast(pid, {:remove_device, usn})
          end
        end)

        State.remove_device(state, usn)
      end)

    Process.send_after(self(), :remove_old_devices, :timer.seconds(60))

    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    subscribers = state.subscribers |> Map.delete(pid)
    {:noreply, state |> Map.put(:subscribers, subscribers)}
  end

  def handle_info({:udp_passive, _port}, state) do
    :inet.setopts(state.socket, active: 10)
    {:noreply, state}
  end

  def handle_info({:udp, _port, ip, _something, body}, state) do
    # Logger.debug("Received message from #{inspect(ip)} from port #{inspect(port)}")

    with {:ok, %SSDP.Message{} = msg} <- body |> SSDP.Message.from_response(),
         {:headers, headers} <- {:headers, msg.headers |> Map.new()},
         {:usn, usn} when is_binary(usn) <- {:usn, headers["usn"]},
         {:nts, nts} <- {:nts, headers["nts"]} do
      action =
        cond do
          # an HTTP response to our scan will not have an nts, but is an advertisement that it exists.
          is_nil(nts) ->
            :update

          # a NOTIFY with an NTS of ssdp:alive is an advertisement that the device is still alive.
          nts == "ssdp:alive" ->
            :update

          # a NOTIFY with NTS of ssdp:byebye means the device is going away.
          nts == "ssdp:byebye" ->
            :remove

          true ->
            # this shouldn't happen, but who knows what non compliant devices are out there.
            Logger.warning("Unhandled NTS on a message from #{inspect(ip)}: #{inspect(nts)}")
            :update
        end

      state =
        case {action, state.devices[usn]} do
          {:remove, nil} ->
            state

          {:remove, device} ->
            Logger.info("Removing device #{inspect(usn)} from network (#{device.server})")

            state.subscribers
            |> Enum.each(fn {pid, subscriber} ->
              if SSDP.Subscriber.relevant_device(subscriber, device) do
                GenServer.cast(pid, {:remove_device, usn})
              end
            end)

            state |> State.remove_device(usn)

          {:update, nil} ->
            with {:ok, %SSDP.Device{} = device} <- SSDP.Device.from_headers(msg, ip) do
              Logger.info("Noticed new device #{inspect(usn)} on network (#{device.server})")

              state.subscribers
              |> Enum.each(fn {pid, subscriber} ->
                if SSDP.Subscriber.relevant_device(subscriber, device) do
                  GenServer.cast(pid, {:update_device, device})
                end
              end)

              state |> State.replace_device(device)
            else
              error ->
                Logger.info("Error parsing message #{inspect(error)}")
                state
            end

          {:update, %SSDP.Device{bootid: old_bootid} = device} ->
            device = device |> SSDP.Device.last_seen_now()
            # the boot id increments when the device reboots, meaning we need to update
            # our knowledge about the device as fields may have changed.
            if headers["bootid.upnp.org"] != old_bootid do
              Logger.info("Replacing device #{inspect(usn)} due to bootid increment")

              state.subscribers
              |> Enum.each(fn {pid, subscriber} ->
                if SSDP.Subscriber.relevant_device(subscriber, device) do
                  GenServer.cast(pid, {:update_device, device})
                end
              end)
            end

            state |> State.replace_device(device)
        end

      {:noreply, state}
    else
      {:usn, _usn} ->
        # There are many messages that aren't relevant to us, such as M-SEARCH requests from
        # other ssdp devices. If there is no usn, it probably isn't an advertisement of a device.
        # body |> IO.inspect(label: "body")
        {:noreply, state}

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
