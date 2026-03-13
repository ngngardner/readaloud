defmodule ReadaloudLibrary.Repo.Migrations.CreateReadingProgress do
  use Ecto.Migration

  def change do
    create table(:reading_progress) do
      add(:book_id, references(:books, on_delete: :delete_all), null: false)
      add(:current_chapter_id, references(:chapters, on_delete: :nilify_all))
      add(:scroll_position, :float, default: 0.0)
      add(:audio_position_ms, :integer, default: 0)
      add(:last_read_at, :utc_datetime)
      timestamps()
    end

    create(unique_index(:reading_progress, [:book_id]))
  end
end
