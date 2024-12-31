defmodule Sonos.Schema.Track do
  use Ecto.Schema

  alias __MODULE__

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "tracks" do
    field(:url, :string)
    field(:protocol_info, :string)
    # in seconds
    field(:duration, :integer)
    field(:creator, :string)
    field(:album, :string)
    field(:title, :string)
    field(:art, :string)
    field(:class, :string)
    field(:item_id, :string)
    field(:parent_id, :string)
    field(:restricted, :boolean)

    many_to_many(:playlists, Sonos.Schema.Playlist, join_through: Sonos.Schema.PlaylistTrack)

    timestamps()
  end

  def changeset(track, attrs) do
    import Ecto.Changeset

    track
    |> cast(attrs, [
      :url,
      :protocol_info,
      :duration,
      :creator,
      :album,
      :title,
      :art,
      :class,
      :item_id,
      :parent_id,
      :restricted
    ])
    |> validate_required([:url, :creator, :title])
    |> unique_constraint(:url)
  end

  def replace_track(attrs) do
    %Sonos.Schema.Track{}
    |> Sonos.Schema.Track.changeset(attrs)
    |> Sonos.Repo.insert(on_conflict: {:replace_all_except, [:id, :inserted_at]})
  end

  def update_track(id, attrs) do
    Sonos.Repo.get(Sonos.Schema.Track, id)
    |> Sonos.Schema.Track.changeset(attrs)
    |> Sonos.Repo.update()
  end

  def delete_track(id) do
    Sonos.Repo.delete(Sonos.Repo.get(Sonos.Schema.Track, id))
  end

  def get_track(id) do
    Sonos.Repo.get(Sonos.Schema.Track, id)
  end

  def query() do
    import Ecto.Query

    from(t in Track, as: :tracks)
    |> join(:left, [tracks: t], p in assoc(t, :playlists), as: :playlists)
  end
end
