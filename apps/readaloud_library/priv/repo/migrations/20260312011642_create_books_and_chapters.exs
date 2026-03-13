defmodule ReadaloudLibrary.Repo.Migrations.CreateBooksAndChapters do
  use Ecto.Migration

  def change do
    create table(:books) do
      add(:title, :string, null: false)
      add(:author, :string)
      add(:cover_path, :string)
      add(:source_type, :string, null: false)
      add(:total_chapters, :integer, default: 0)
      timestamps()
    end

    create table(:chapters) do
      add(:book_id, references(:books, on_delete: :delete_all), null: false)
      add(:title, :string)
      add(:number, :integer, null: false)
      add(:volume, :integer)
      add(:content_path, :string)
      add(:word_count, :integer, default: 0)
      timestamps()
    end

    create(index(:chapters, [:book_id]))
    create(unique_index(:chapters, [:book_id, :number]))
  end
end
