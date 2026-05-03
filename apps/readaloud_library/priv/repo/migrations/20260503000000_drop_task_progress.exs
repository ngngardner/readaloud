defmodule ReadaloudLibrary.Repo.Migrations.DropTaskProgress do
  use Ecto.Migration

  def change do
    alter table(:audiobook_tasks) do
      remove(:progress, :float, default: 0.0)
    end

    alter table(:import_tasks) do
      remove(:progress, :float, default: 0.0)
    end
  end
end
