defmodule Sonos.Api.Response do
  alias __MODULE__
  alias Sonos.Utils
  defstruct command: nil, outputs: nil, via: nil

  def new(command, output, output_types, opts \\ []) do
    via = opts |> Keyword.get(:via, nil)

    output_types = output_types |> Enum.map(fn x -> {x.name, x.data_type} end) |> Map.new()

    output =
      output
      |> Enum.map(fn {name, val} ->
        output_type = output_types |> Map.get(name, nil)

        case {name, output_type} do
          {:zone_group_state, :string} ->
            {name, val |> zone_group_state_parse()}
          {:preset_name_list, :string} ->
            {name, val |> String.split(",")}

          {_, :boolean} ->
            {name, val["-val"] == "1"}

         # {_, x} when x in [:ui1, :ui2, :ui4, :i1, :i2, :i4] ->
         #   {name, val["-val"]}

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

#        "RenderingControl:1" ->
#              |> Enum.reduce(%{}, fn {key, val}, acc ->
#                val =
#                  case key do
#                    # values by channel (LF, RF, Master), as boolean
#                    "Mute" ->
#                      val
#                      |> Sonos.Utils.coerce_to_list()
#                      |> Enum.map(fn val ->
#                        {val["-channel"], val["-val"] == "1"}
#                      end)
#                      |> Map.new()
#
#                    # values by channel (LF, RF, Master), as integers
#                    x when x in ["Loudness", "Volume"] ->
#                      val
#                      |> Sonos.Utils.coerce_to_list()
#                      |> Enum.map(fn val ->
#                        {val["-channel"], val["-val"] |> String.to_integer()}
#                      end)
#                      |> Map.new()
#
#                    # integer values
#                    x
#                    when x in [
#                           "AudioDelay",
#                           "AudioDelayLeftRear",
#                           "AudioDelayRightRear",
#                           "Bass",
#                           "Treble",
#                           "SubEnabled",
#                           "SubGain",
#                           "SubPolarity",
#                           "SurroundLevel",
#                           "DialogLevel",
#                           "HeightChannelLevel",
#                           "MusicSurroundLevel",
#                           "SpeechEnhanceEnabled",
#                           "OutputFixed",
#                           "SpeakerSize",
#                           "SubCrossover",
#                           "SurroundMode"
#                         ] ->
#                      val["-val"] |> String.to_integer()
#
#                    # boolean values (represented as strings of "0" or "1")
#                    x
#                    when x in [
#                           "SurroundEnabled",
#                           "SonarCalibrationAvailable",
#                           "SonarEnabled",
#                           "NightMode"
#                         ] ->
#                      val["-val"]
#                      |> then(fn
#                        "0" -> false
#                        "1" -> true
#                        _ -> nil
#                      end)
#
#                    # comma separated list of strings
#                    "PresetNameList" ->
#                      val["-val"] |> String.split(",")
#                  end
#
#                acc |> Map.put(key, val)
#              end)
#
#            {instance_id |> String.to_integer(), data}
#          end)
#          |> Map.new()


end
