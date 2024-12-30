defmodule Sonos.Repo.Migrations.Seed do
  use Ecto.Migration

  def change do
    create table(:playlists, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :name, :string, null: false
      add :content, :text, null: false
      timestamps()
    end

    create unique_index(:playlists, [:name])
  end
end
