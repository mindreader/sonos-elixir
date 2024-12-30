defmodule Sonos.Repo.Migrations.CreatePlaylistTracks do
  use Ecto.Migration

  def change do
    create table(:playlist_tracks, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :playlist_id, references(:playlists, type: :binary_id, on_delete: :delete_all)
      add :track_id, references(:tracks, type: :binary_id, on_delete: :delete_all)
      add :position, :integer

      timestamps()
    end

    create unique_index(:playlist_tracks, [:playlist_id, :position])
  end
end
