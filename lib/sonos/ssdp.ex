defmodule Sonos.SSDP do

  def rescan do
    Sonos.SSDP.Server |> GenServer.cast(:scan)
  end

  def ports do
    local_endpoints()
    |> Enum.map(fn local_ip ->
      {:ok, socket} =
        :gen_udp.open(local_port(), [
          :binary,
          reuseaddr: true,
          broadcast: true,
          active: 10,
          multicast_ttl: get_ttl(),
          ip: local_ip,
          add_membership: {get_maddr(), {0, 0, 0, 0}}
        ])

      socket
    end)
  end

  def search do
    "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:reservedSSDPport\r\nMAN: ssdp:discover\r\nMX: 1\r\nST: urn:schemas-upnp-org:device:ZonePlayer:1\r\n"
  end

  def scan(ports) when is_list(ports) do
    ports
    |> Enum.map(fn port ->
      remote_endpoints()
      |> Enum.map(fn remote_ip ->
        :ok = port |> :gen_udp.send(remote_ip, remote_port(), search())
      end)
    end)
  end

  def scan(port) do
    [port] |> scan()
  end

  #  def handle_info(:broadcast, state = %{conn: {addr, port, sock}}) do
  #    :ok = :gen_udp.send(sock, addr, port, ["Peer:#{ node() }"])
  #    Process.send_after(self(), :broadcast, :rand.uniform(4_000) + 3_000)
  #    {:noreply, state}
  #  end
  #  def handle_info(:timeout, state), do: handle_info(:broadcast, state)

  def remote_port, do: 1900

  def remote_endpoints do
    # [{239,255,255,250}, {255,255,255,255}]
    [{239, 255, 255, 250}, {255, 255, 255, 255}]
  end

  defp local_port, do: 1905

  defp local_endpoints do
    # TODO figure out local ip somehow
    # via :inet.getifaddrs?
    [{0, 0, 0, 0} | potential_ips()]
  end

  # defp get_maddr, do: {230,1,1,1}
  defp get_maddr, do: {239, 255, 255, 251}
  defp get_ttl, do: 2

  def potential_ips do
    :inet.getif()
    |> case do
      {:ok, res} -> res
    end
    |> Enum.map(fn {ip, _, _} -> ip end)
    |> Enum.filter(fn
      {127, 0, 0, 1} -> false
      _ -> true
    end)
    |> Enum.map(fn ip ->
      ip |> IO.inspect(label: "flags")
    end)
  end
end
