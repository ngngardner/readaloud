defmodule ReadaloudLibrary.Repo.Migrations.AddAudioPreferencesAndModel do
  use Ecto.Migration

  def change do
    alter table(:books) do
      add(:audio_preferences, :map)
    end

    alter table(:audiobook_tasks) do
      add(:model, :string)
    end
  end
end
