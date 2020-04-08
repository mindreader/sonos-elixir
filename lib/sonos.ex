defmodule Sonos do
  use Application

  def start(_type, _args) do
    Supervisor.start_link([Sonos.Supervisor], strategy: :one_for_one)
  end
end
