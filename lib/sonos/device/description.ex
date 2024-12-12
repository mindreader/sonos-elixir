defmodule Sonos.Device.Description do
  defstruct room_name: nil,
            model_name: nil,
            model_number: nil

  alias __MODULE__

  def from_response(doc) do
    root = doc |> XmlToMap.naive_map() |> Map.get("root") |> Map.get("device")

    %Description{
      room_name: root["roomName"],
      model_name: root["modelName"],
      model_number: root["modelNumber"]
    }
  end
end
