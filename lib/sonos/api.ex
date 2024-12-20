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

  def short_usn(usn) do
    usn
    |> String.replace("::urn:schemas-upnp-org:device:ZonePlayer:1", "")
  end

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

  # unfortunately I don't have any of these devices, so I can't define them, but if you should
  # run across one, you can define it here by pulling the device specification from the device
  # via the Analaytis module, storing their json in the data/devices directory
  defmodule Play3 do
    @moduledoc """
    API module for Sonos Play:3 speakers.
    """
    # Meta.define_device("Play:3", "data/devices/Play:3.json")
  end

  defmodule One do
    @moduledoc """
    API module for Sonos One speakers.
    """
    # Meta.define_device("One", "data/devices/One.json")
  end

  defmodule OneSL do
    @moduledoc """
    API module for Sonos One SL speakers.
    """
    # Meta.define_device("OneSL", "data/devices/OneSL.json")
  end

  defmodule Play5 do
    @moduledoc """
    API module for Sonos Play:5 speakers.
    """
    # Meta.define_device("Play:5", "data/devices/Play:5.json")
  end

  defmodule Roam do
    @moduledoc """
    API module for Sonos Roam speakers.
    """
    # Meta.define_device("Roam", "data/devices/Roam.json")
  end

  defmodule SymfoniskBookshelf do
    @moduledoc """
    API module for SYMFONISK Bookshelf speakers.
    """
    # Meta.define_device("SymfoniskBookshelf", "data/devices/SymfoniskBookshelf.json")
  end

  defmodule Sub do
    @moduledoc """
    API module for Sonos Sub subwoofer.
    """
    # Meta.define_device("Sub", "data/devices/Sub.json")
  end
end
