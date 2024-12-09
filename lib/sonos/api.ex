defmodule Sonos.Api do
  require Sonos.Api.Meta, as: Meta

  @moduledoc """
  Provides device-specific API modules for different Sonos speaker models.

  This module contains submodules for each supported Sonos device type, automatically
  generated from device specification files. Each device module provides functions
  specific to that device's capabilities, organized by service (like MediaRenderer.AVTransport).

  ## Available Device Modules

  - `Play1` - API for Sonos Play:1 speakers
  - `Playbar` - API for Sonos Playbar soundbars
  - `Beam` - API for Sonos Beam soundbars

  ## Usage
  ```elixir
  # Example usage with a Play:1 speaker
  alias Sonos.Api.Play1.MediaRenderer.{AVTransport, RenderingControl, GroupRenderingControl}

  # Playback control
  AVTransport.play(instance_id, speed)

  # Volume control
  GroupRenderingControl.set_group_volume(device, 50)
  ```

  Each device's API is organized into services that provide specific functionality:
  - MediaRenderer.AVTransport - Controls playback (play, pause, next, etc)
  - MediaRenderer.RenderingControl - Controls volume and audio settings

  Feel free to explore the options in the repl under this module, as functionality available for each
  model of device differs.
  """

  defmodule Play1 do
    @moduledoc """
    API module for Sonos Play:1 speakers.
    """
    Meta.define_device("Play:1", "data/devices/Play:1.json")
  end

  defmodule Playbar do
    @moduledoc """
    API module for Sonos Playbar soundbars.
    """
    Meta.define_device("Playbar", "data/devices/Playbar.json")
  end

  defmodule Beam do
    @moduledoc """
    API module for Sonos Beam soundbars.
    """
    Meta.define_device("Beam", "data/devices/Beam.json")
  end
end
