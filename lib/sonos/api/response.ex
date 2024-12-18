defmodule Sonos.Api.Response do
  alias __MODULE__
  alias Sonos.Utils
  defstruct command: nil, outputs: nil, via: nil

  def new(command, output, opts \\ []) do
    via = opts |> Keyword.get(:via, nil)

    output =
      output
      |> Enum.map(fn {name, val} ->
        case name do
          :zone_group_state ->
            {name, val |> zone_group_state_parse()}

          _ ->
            {name, val}
        end
      end)

    %Response{command: command, outputs: output, via: via}
  end

  @doc """
  Parses the ZoneGroupState variable from the Zone Group State events. Sonos devices just send
  opaque xml because it can't be represented easily in plain soap variables, so we must parse.
  """
  def zone_group_state_parse(val) do
    val
    |> XmlToMap.naive_map()
    |> then(fn json ->
      json["ZoneGroupState"]["ZoneGroups"]["ZoneGroup"]
      |> then(fn state ->
        # not sure what the use of this is.
        # vanished_devices = state["VanishedDevices"] || []
        state
        |> Utils.coerce_to_list()
        |> Enum.map(fn zone ->
          %{
            zone_group_id: zone["-ID"],
            zone_group_coordinator: zone["-Coordinator"],
            members:
              zone["#content"]["ZoneGroupMember"]
              |> Utils.coerce_to_list()
              |> Enum.map(fn member ->
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
