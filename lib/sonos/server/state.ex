defmodule Sonos.Server.State do
  alias __MODULE__
  alias Sonos.Device

  defstruct devices: nil,
            usn_by_endpoint: nil,
            our_event_address: nil,
            ssdp_server: nil

  def replace_device(%State{} = state, %Device{} = device) do
    short_usn = device.usn |> Sonos.Api.short_usn()

    %State{
      state
      | devices: state.devices |> Map.put(short_usn, %Device{} = device),
        usn_by_endpoint: state.usn_by_endpoint |> Map.put(device.endpoint, short_usn)
    }
  end

  def remove_device(%State{} = state, %Sonos.SSDP.Device{} = device) do
    endpoint = device |> Sonos.SSDP.Device.endpoint()

    short_usn = device.usn |> Sonos.Api.short_usn()

    %State{
      state
      | devices: state.devices |> Map.delete(short_usn),
        usn_by_endpoint: state.usn_by_endpoint |> Map.delete(endpoint)
    }
  end

  def remove_device(%State{} = state, %Device{} = device) do
    short_usn = device.usn |> Sonos.Api.short_usn()

    %State{
      state
      | devices: state.devices |> Map.delete(short_usn),
        usn_by_endpoint: state.usn_by_endpoint |> Map.delete(device.endpoint)
    }
  end
end
