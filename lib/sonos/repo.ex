defmodule Sonos.Repo do
  use Ecto.Repo,
    otp_app: :sonos_elixir,
    adapter: Ecto.Adapters.SQLite3
end
