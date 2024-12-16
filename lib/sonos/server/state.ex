defmodule Sonos.Server.State do
  alias __MODULE__
  alias Sonos.Device
  alias Sonos.Utils

  defstruct devices: nil,
            usn_by_endpoint: nil,
            our_event_address: nil,
            ssdp_server: nil

    def replace_device(%State{} = state, %Device{} = device) do
      short_usn = device.usn |> String.replace("::urn:schemas-upnp-org:device:ZonePlayer:1", "")

      %State{
        state |
        devices: state.devices |> Map.put(short_usn, device),
        usn_by_endpoint: state.usn_by_endpoint |> Map.put(device.endpoint, short_usn)
      }
    end

   def remove_device(%State{} = state, %Sonos.SSDP.Device{} = device) do
      endpoint = device |> Sonos.SSDP.Device.endpoint()
      %State {
        state |
        usn_by_endpoint: state.usn_by_endpoint |> Map.delete(endpoint)
      }
    end

    def remove_device(%State{} = state, %Device{} = device) do
      short_usn = device.usn |> String.replace("::urn:schemas-upnp-org:device:ZonePlayer:1", "")

      %State{
        state |
        devices: state.devices |> Map.delete(short_usn),
        usn_by_endpoint: state.usn_by_endpoint |> Map.delete(device.endpoint)
      }
    end

  @doc """
  Parses the current volume related settings from individual devices.
  """
  def current_volume_parse(val) do
    if is_integer(val) do
      val
    else
      val |> IO.inspect(label: "current volume!")
    end
  end

  @doc """
  Parses the ZoneGroupState variable from the Zone Group State events. Sonos devices just send
  opaque xml because it can't be represented easily, so we must make it useful.
  """
  def zone_group_state_parse(val) do
    val |> XmlToMap.naive_map()
    |> then(fn json ->
      json["ZoneGroupState"]["ZoneGroups"]["ZoneGroup"]
      |> then(fn state ->
        # not sure what the use of this is.
        # vanished_devices = state["VanishedDevices"] || []
        state |> Utils.coerce_to_list() |> Enum.map(fn zone ->
          %{
            zone_group_id: zone["-ID"],
            zone_group_coordinator: zone["-Coordinator"],
            members: zone["#content"]["ZoneGroupMember"] |> Utils.coerce_to_list() |> Enum.map(fn member ->
              # there are a multitude of attributes in the member, but little of it is relevant
              # to us.
              %{
                uuid: member["-UUID"],
                zone_name: member["-ZoneName"]
              }
            end)
          }
        end)
      end)
    end)
  end
end
