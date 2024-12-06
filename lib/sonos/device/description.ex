defmodule Sonos.Device.Description do
  defstruct room_name: nil, model_description: nil

  import SweetXml
  alias __MODULE__

  def from_response(doc) do
    # FIXME gotta be a better way
    attrs =
      doc
      |> xpath(~x"//device",
        model_description: ~x"./modelName/text()",
        room_name: ~x"./roomName/text()"
      )

    %Description{
      model_description: attrs.model_description,
      room_name: attrs.room_name
    }
  end
end
