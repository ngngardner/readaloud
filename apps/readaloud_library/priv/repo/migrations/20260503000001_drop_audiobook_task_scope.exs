defmodule ReadaloudLibrary.Repo.Migrations.DropAudiobookTaskScope do
  use Ecto.Migration

  def change do
    alter table(:audiobook_tasks) do
      remove(:scope, :string, default: "chapter", null: false)
    end
  end
end
