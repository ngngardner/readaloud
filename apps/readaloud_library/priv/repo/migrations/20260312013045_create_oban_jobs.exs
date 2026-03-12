defmodule ReadaloudLibrary.Repo.Migrations.CreateObanJobs do
  use Ecto.Migration

  def up, do: Oban.Migrations.SQLite.up(%{})
  def down, do: Oban.Migrations.SQLite.down(%{})
end
