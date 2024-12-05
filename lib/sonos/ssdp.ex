defmodule Sonos.SSDP do

  require Logger

  @multicast_group {239, 255, 255, 250}
  @multicast_port 1900


  def portoptions do
    [
      # general options
      mode: :binary,
      reuseaddr: true,
      # active: 10,
      active: true, # TODO FIXME use active: 1 and passive udp

      # multicast receiving options (we're listening on all interfaces)
      add_membership: {@multicast_group, {0, 0, 0, 0}},

      # multicast sending options
      multicast_if: {0, 0, 0, 0}, # we're sending from all interfaces which support multicast
      multicast_loop: false, # don't send our own events back to ourselves
      multicast_ttl: 2, # hop to at least 2 routers away
    ]
  end

  def port do
    Logger.info("Opening port #{inspect(port)}")
    # we receive messages from the speakers on this port.
    {:ok, socket} = :gen_udp.open(@multicast_port, portoptions())
    socket
  end

  def search do
    "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:reservedSSDPport\r\nMAN: ssdp:discover\r\nMX: 1\r\nST: urn:schemas-upnp-org:device:ZonePlayer:1\r\n"
  end

  def scan(port) when is_port(port) do
    Logger.info("Scanning...")

    :ok = port |> :gen_udp.send(@multicast_group, @multicast_port, search())
  end

  #  def handle_info(:broadcast, state = %{conn: {addr, port, sock}}) do
  #    :ok = :gen_udp.send(sock, addr, port, ["Peer:#{ node() }"])
  #    Process.send_after(self(), :broadcast, :rand.uniform(4_000) + 3_000)
  #    {:noreply, state}
  #  end
  #  def handle_info(:timeout, state), do: handle_info(:broadcast, state)

  def response_parse(str) do
    str |> String.split("\r\n") |> Enum.reduce(%{}, fn
      "HTTP/1.1 200 OK", accum -> accum
      header, accum ->

        Regex.run(~r/^([^:]+):(?: (.*))?$/, header) |> case do
        [_, header, val] -> accum |> Map.put(header |> String.downcase(), val |> String.trim())
        [_, header] -> accum |> Map.put(header |> String.downcase(), nil)
          _ -> accum
      end
    end)
  end
end
