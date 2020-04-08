defmodule Sonos.SSDP.Server do
  use GenServer

  def start_link(_args) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_args) do
    {:ok, nil}
  end

  def handle_info(:state, state) do
    state |> IO.inspect(label: "state")
    {:noreply, state}
  end
end
