defmodule Sonos.Api do
  require Sonos.Api.Meta, as: Meta

  defmodule Play1 do
    Meta.define_device("Play:1", "data/devices/Play:1.json")
  end

  defmodule Playbar do
    Meta.define_device("Playbar", "data/devices/Playbar.json")
  end

  defmodule Beam do
    Meta.define_device("Beam", "data/devices/Beam.json")
  end
end
