defmodule ReadaloudLibrary.Repo.Migrations.AddAudioProfileTracking do
  use Ecto.Migration

  def change do
    alter table(:chapter_audios) do
      add :model, :string
      add :voice, :string
    end

    alter table(:audiobook_tasks) do
      add :attempt_number, :integer, default: 1
    end
  end
end
