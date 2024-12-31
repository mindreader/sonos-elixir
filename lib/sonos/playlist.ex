defmodule Sonos.Playlist do
  alias __MODULE__

  alias Sonos.Track

  defstruct name: nil, tracks: nil

  @doc """
  Streams playlists.

  ## Options

  - `sort_by`: The field to sort by. Defaults to `:inserted_at`.
  - `order`: The order to sort by. Defaults to `:desc`.

  iex> Sonos.Repo.transaction(fn ->
  iex>   Sonos.Playlist.stream_playlists(sort_by: :name, order: :asc)
  iex>   |> Enum.to_list()
  iex> end)
  """
  def playlist_query(opts \\ []) do
    import Ecto.Query

    sort_by = Keyword.get(opts, :sort_by, :inserted_at)

    default_order =
      case sort_by do
        :name -> :asc
        :inserted_at -> :desc
        :updated_at -> :desc
      end

    order = Keyword.get(opts, :order, default_order)

    order_by = [{order, sort_by}]

    from(pl in Sonos.Schema.Playlist)
    |> order_by(^order_by)
  end

  def from_schema(%Sonos.Schema.Playlist{} = playlist) do
    playlist = playlist |> Sonos.Repo.preload([:tracks])

    %Playlist{
      name: playlist.name,
      tracks:
        playlist.tracks |> Enum.sort_by(& &1.content.position) |> Enum.map(&Track.from_schema/1)
    }
  end

  def get(id) do
    id
    |> Sonos.Schema.Playlist.get_playlist()
    |> from_schema()
  end

  def update(%Playlist{} = playlist, attrs) do
    playlist
    |> Sonos.Schema.Playlist.update_playlist(attrs)
    |> from_schema()
  end

  def delete(id) do
    id
    |> Sonos.Schema.Playlist.delete_playlist()
  end

  def stream(opts \\ []) do
    playlist_query(opts)
    |> Sonos.Repo.stream()
  end

  def add_track(%Playlist{} = playlist, %Track{} = track) do
    %Playlist{
      tracks: [track | playlist.tracks |> Enum.reject(&(&1.url == track.content.url))]
    }
  end
end
