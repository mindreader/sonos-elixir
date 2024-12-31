defmodule Sonos.Schema.Playlist do
  use Sonos.Schema
  import Ecto.Query

  alias __MODULE__

  schema "playlists" do
    field(:name, :string)

    many_to_many(
      :tracks,
      Sonos.Schema.Track,
      join_through: Sonos.Schema.PlaylistTrack,
      preload_order: {__MODULE__, :preload_position_order, []}
    )

    timestamps()
  end

  def preload_position_order do
    import Ecto.Query

    [asc: dynamic([assoc, join], join.position)]
  end

  def changeset(playlist, attrs) do
    import Ecto.Changeset

    playlist
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> unique_constraint(:name)
  end

  def create_playlist(name) do
    %Sonos.Schema.Playlist{}
    |> Sonos.Schema.Playlist.changeset(%{name: name})
    |> Sonos.Repo.insert()
  end

  def get_playlist(id) do
    Sonos.Repo.get(Sonos.Schema.Playlist, id)
  end

  def update_playlist(id, attrs) do
    Sonos.Repo.get(Sonos.Schema.Playlist, id)
    |> Sonos.Schema.Playlist.changeset(attrs)
    |> Sonos.Repo.update()
  end

  def delete_playlist(id) do
    Sonos.Repo.delete(Sonos.Repo.get(Sonos.Schema.Playlist, id))
  end

  def query() do
    import Ecto.Query
    from(p in Playlist, as: :playlists)
  end
end
