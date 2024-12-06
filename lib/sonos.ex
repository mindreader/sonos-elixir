require Logger

defmodule Sonos do
  use Application

  alias Sonos.Device

  # TODO move these into the sonos.ex module
  def rescan do
    Sonos.Server |> GenServer.cast(:scan)
  end

  def state do
    Sonos.Server |> GenServer.call(:state)
  end

  def identify_all do
    devices()
    |> Task.async_stream(&identify/1, ordered: false, on_timeout: :kill_task)
    |> Stream.run()
  end

  def identify(%Device{} = dev) do
    dev
    |> Device.identify()
    |> case do
      {:ok, desc} ->
        dev |> identify_device(desc)

      err ->
        Logger.debug("Failed to identify a device #{err}")
    end
  end

  def identify_device(%Device{} = dev, %Device.Description{} = desc) do
    Sonos.Server |> GenServer.cast({:identify, dev, desc})
  end

  def devices do
    Sonos.Server |> GenServer.call(:devices)
  end

  def start(_type, _args) do
    Supervisor.start_link([Sonos.Supervisor], strategy: :one_for_one)
  end
end
