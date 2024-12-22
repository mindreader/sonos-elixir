require Logger

# TODO
# Sonos.Api.Play1.MediaRenderer.AVTransport.get_position_info(device.endpoint, 0)
#  gives track: 3, track_duration: 216, track_metadata: big bunch of xml.
# get_media_info returns (some stuff)

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
            |> Enum.filter(fn member ->
              devices[member.uuid]
            end)
            |> Enum.map(fn member ->
              member
              |> Map.put(:leader, member.uuid == leader)
              |> Map.put(:device, devices[member.uuid])
              |> Map.delete(:uuid)
            end)
            |> Enum.sort_by(fn member -> !member.leader end)
        }
      end)
      |> Enum.filter(fn group ->
        group.members |> Enum.count() > 0
      end)
      |> Enum.sort_by(fn group -> group.id end)
    end)
  end

  def play(%Sonos.Device{} = device) do
    device |> Sonos.Device.call(MediaRenderer.AVTransport, :play, [0, "1"])
  end

  def is_playing?(%Sonos.Device{} = device) do
    device |> Sonos.Device.call(MediaRenderer.AVTransport, :get_transport_info, [0])
    |> then(fn {:ok, %Sonos.Api.Response{outputs: outputs}} ->

      outputs[:current_transport_state] in ["TRANSITIONING", "PLAYING"]
    end)
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

  def shuffle_enabled?(play_state) when is_atom(play_state) do
    play_state in [:shuffle, :shuffle_norepeat, :shuffle_repeat_one]
  end

  def continue_enabled?(play_state) when is_atom(play_state) do
    play_state in [:repeat_all, :repeat_one, :shuffle_repeat_one, :shuffle]
  end

  def set_play_state(%Sonos.Device{} = device, state) do
    state = case state do
      :normal -> "NORMAL"
      :repeat_one -> "REPEAT_ONE"
      :repeat_all -> "REPEAT_ALL"
      :shuffle -> "SHUFFLE"
      :shuffle_norepeat -> "SHUFFLE_NOREPEAT"
      :shuffle_repeat_one -> "SHUFFLE_REPEAT_ONE"
    end

    device |> Sonos.Device.call(MediaRenderer.AVTransport, :set_play_mode, [0, state])
  end

  def get_play_state(%Sonos.Device{} = device) do
    device |> Sonos.Device.call(MediaRenderer.AVTransport, :get_transport_settings, [0])
    |> then(fn {:ok, %Sonos.Api.Response{outputs: outputs}} ->
      case outputs[:play_mode] do
        "NORMAL" -> :normal
        "REPEAT_ONE" -> :repeat_one
        "REPEAT_ALL" -> :repeat_all
        "SHUFFLE" -> :shuffle
        "SHUFFLE_NOREPEAT" -> :shuffle_norepeat
        "SHUFFLE_REPEAT_ONE" -> :shuffle_repeat_one
      end
    end)
  end

  def get_group_volume(%Sonos.Device{} = device) do
    device |> Sonos.Device.call(MediaRenderer.GroupRenderingControl, :get_group_volume, [0])
  end

  def set_group_volume(%Sonos.Device{} = device, volume) when is_integer(volume) and volume >= 0 and volume <= 100 do
    device |> Sonos.Device.call(MediaRenderer.GroupRenderingControl, :set_group_volume, [0, volume])
  end

  def server_state do
    Sonos.Server |> GenServer.call(:state)
  end

  def ssdp_state do
    Sonos.SSDP |> GenServer.call(:state)
  end
end
