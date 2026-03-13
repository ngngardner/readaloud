defmodule ReadaloudLibrary.Repo.Migrations.CreateAudiobookTables do
  use Ecto.Migration

  def change do
    create table(:audiobook_tasks) do
      add(:book_id, references(:books, on_delete: :delete_all), null: false)
      add(:chapter_id, references(:chapters, on_delete: :delete_all))
      add(:scope, :string, null: false, default: "chapter")
      add(:voice, :string)
      add(:speed, :float, default: 1.0)
      add(:status, :string, default: "pending", null: false)
      add(:progress, :float, default: 0.0)
      add(:error_message, :text)
      timestamps()
    end

    create(index(:audiobook_tasks, [:book_id]))
    create(index(:audiobook_tasks, [:status]))

    create table(:chapter_audios) do
      add(:chapter_id, references(:chapters, on_delete: :delete_all), null: false)
      add(:audio_path, :string, null: false)
      add(:duration_seconds, :float)
      add(:word_timings, :text)
      timestamps()
    end

    create(unique_index(:chapter_audios, [:chapter_id]))
  end
end
