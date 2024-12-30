defmodule Sonos.Schema.PlaylistTrack do
  use Sonos.Schema

  alias Sonos.Schema.Playlist
  alias Sonos.Schema.Track

  schema "playlist_tracks" do
    belongs_to :playlist, Playlist
    belongs_to :track, Track

    field :position, :integer

    timestamps()
  end

  @required_fields [:playlist_id, :track_id, :position]

  def changeset(playlist_track, attrs) do
    import Ecto.Changeset

    playlist_track
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:playlist_id)
    |> foreign_key_constraint(:track_id)
    |> unique_constraint([:playlist_id, :position], name: :playlist_tracks_position_index)
  end

  def query() do
    import Ecto.Query

    from(pt in __MODULE__, as: :playlist_tracks)
    |> join(:inner, [playlist_tracks: pt], p in Playlist, on: pt.playlist_id == p.id, as: :playlists)
  end
end
