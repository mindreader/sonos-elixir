defmodule Sonos.Server do
  use GenServer

  alias Sonos.Device
  require Logger

  defmodule State do
    defstruct devices: nil, our_event_address: nil
  end

  def start_link(_args) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_args) do
    with {:ok, our_event_address} <- Sonos.Utils.our_event_address() do
      state = %State{
        our_event_address: our_event_address,
        # Map of usn -> device
        devices: %{}
      }

      {:ok, state, {:continue, :scan}}
    else
      err -> err
    end
  end

  def handle_call(:state, _from, state) do
    {:reply, state, state}
  end

  def handle_continue(:scan, state) do
    IO.puts("CONTINUE")
    {:noreply, state}
  end
end
