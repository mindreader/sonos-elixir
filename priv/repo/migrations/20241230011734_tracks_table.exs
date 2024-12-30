defmodule Sonos.Repo.Migrations.TrackTable do
  use Ecto.Migration

  def change do
    create table(:tracks, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :url, :string
      add :protocol_info, :string
      add :duration, :integer # in seconds
      add :creator, :string
      add :album, :string
      add :title, :string
      add :art, :string
      add :class, :string

      add :item_id, :string
      add :parent_id, :string
      add :restricted, :boolean

      timestamps()
    end

    create unique_index(:tracks, [:url])
  end
end
