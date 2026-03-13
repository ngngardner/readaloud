defmodule ReadaloudLibrary.Repo.Migrations.CreateImportTasks do
  use Ecto.Migration

  def change do
    create table(:import_tasks) do
      add(:file_path, :string, null: false)
      add(:file_type, :string, null: false)
      add(:file_size, :integer)
      add(:status, :string, default: "pending", null: false)
      add(:progress, :float, default: 0.0)
      add(:error_message, :text)
      add(:book_id, references(:books, on_delete: :nilify_all))
      timestamps()
    end
  end
end
