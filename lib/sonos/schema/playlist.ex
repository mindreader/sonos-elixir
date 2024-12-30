defmodule Sonos.Schema.Playlist do
  use Sonos.Schema

  alias __MODULE__

  schema "playlists" do
    field :name, :string
    field :content, :string

    timestamps()
  end

  def changeset(playlist, attrs) do
    import Ecto.Changeset

    playlist
    |> cast(attrs, [:name, :content])
    |> validate_required([:name, :content])
    |> unique_constraint(:name)
  end

  def create_playlist(name, content) do
    %Sonos.Schema.Playlist{}
    |> Sonos.Schema.Playlist.changeset(%{name: name, content: content})
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
