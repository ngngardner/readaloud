defmodule ReadaloudImporterTest do
  use ExUnit.Case, async: false
  use Oban.Testing, repo: ReadaloudLibrary.Repo

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(ReadaloudLibrary.Repo)
  end

  describe "import_file/2" do
    test "creates import task and enqueues job" do
      assert {:ok, task} = ReadaloudImporter.import_file("/tmp/test.epub", "epub")
      assert task.status == "pending"
      assert task.file_type == "epub"
      assert_enqueued(worker: ReadaloudImporter.ParseJob, args: %{task_id: task.id})
    end
  end

  describe "list_tasks/0" do
    test "returns all import tasks" do
      {:ok, _} = ReadaloudImporter.import_file("/tmp/a.epub", "epub")
      {:ok, _} = ReadaloudImporter.import_file("/tmp/b.pdf", "pdf")
      assert length(ReadaloudImporter.list_tasks()) == 2
    end
  end
end
