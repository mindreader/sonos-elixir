require Logger

defmodule Sonos do
  def scan do
    Sonos.SSDP.scan()
  end

  def devices do
    Sonos.Server |> GenServer.call(:devices)
  end

  # TODO FIXME these utility functions that are specific to the web could be moved to the web, getting
  # their own modules to represent devices.
  @doc """
    Returns the zone topology of all devices on the network. The topology is stored in every device and
    should theoretically be the same, but we can't guarantee they will match or that the device we pick
    will be the fastest, and we don't want to wait for all of them to respond so we send a request to
    every device and take the two that respond the fastest, then we combine their topologies into one
    coherent topology that we will use as a source of truth.
  """
  def groups do
    devices =
      devices()
      |> Enum.map(fn %Sonos.Device{} = device ->
        {device.usn, device}
      end)
      |> Map.new()

    devices
    |> Map.values()
    |> Task.async_stream(
      fn %Sonos.Device{} = device ->
        device |> Sonos.Device.call(ZonePlayer.ZoneGroupTopology, :get_zone_group_state, [])
      end,
      max_concurrency: 10,
      ordered: false,
      timeout: :timer.seconds(2)
    )
    |> Stream.filter(fn
      {:ok, {:ok, _}} -> true
      _ -> false
    end)
    |> Stream.take(2)
    |> Stream.map(fn {:ok, {:ok, %Sonos.Api.Response{outputs: outputs}}} ->
      outputs[:zone_group_state]
    end)
    |> Enum.to_list()
    |> then(fn topos ->
      topos
      |> Enum.concat()
      |> Enum.group_by(fn zone -> zone.zone_group_id end)
      |> Enum.map(fn {zone_group_id, zones} ->
        leader =
          zones |> Enum.map(fn zone -> zone.zone_group_coordinator end) |> Enum.sort() |> hd

        %{
          id: zone_group_id,
          members:
            zones
            |> Enum.map(fn zone -> zone.members end)
            |> Enum.concat()
            |> Enum.uniq_by(fn zone -> zone.uuid end)
            |> Enum.map(fn member ->
              member
              |> Map.put(:leader, member.uuid == leader)
              |> Map.put(:device, devices[member.uuid])
              |> Map.delete(:uuid)
            end)
            |> Enum.sort_by(fn member -> !member.leader end)
        }
      end)
      |> Enum.sort_by(fn group -> group.id end)
    end)
  end

  def play(%Sonos.Device{} = device) do
    device |> Sonos.Device.call(MediaRenderer.AVTransport, :play, [0, "1"])
  end

  def get_pause(%Sonos.Device{} = device) do
    device |> Sonos.Device.call(MediaRenderer.AVTransport, :get_pause, [0])
  end

  def pause(%Sonos.Device{} = device) do
    device |> Sonos.Device.call(MediaRenderer.AVTransport, :pause, [0])
  end

  def next(%Sonos.Device{} = device) do
    device |> Sonos.Device.call(MediaRenderer.AVTransport, :next, [0])
  end

  def previous(%Sonos.Device{} = device) do
    device |> Sonos.Device.call(MediaRenderer.AVTransport, :previous, [0])
  end

  def get_group_volume(%Sonos.Device{} = device) do
    device |> Sonos.Device.call(MediaRenderer.GroupRenderingControl, :get_group_volume, [0])
  end

  def server_state do
    Sonos.Server |> GenServer.call(:state)
  end

  def ssdp_state do
    Sonos.SSDP |> GenServer.call(:state)
  end
end
