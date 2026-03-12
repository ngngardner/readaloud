defmodule ReadaloudAudiobookTest do
  use ExUnit.Case, async: false
  use Oban.Testing, repo: ReadaloudLibrary.Repo

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(ReadaloudLibrary.Repo)

    {:ok, book} = ReadaloudLibrary.create_book(%{title: "Test", source_type: "epub"})

    content_path = Path.join(System.tmp_dir!(), "test_chapter.html")
    File.write!(content_path, "<p>Hello world this is test content.</p>")

    {:ok, ch1} = ReadaloudLibrary.create_chapter(%{book_id: book.id, number: 1, content_path: content_path})
    {:ok, ch2} = ReadaloudLibrary.create_chapter(%{book_id: book.id, number: 2, content_path: content_path})

    %{book: book, ch1: ch1, ch2: ch2}
  end

  describe "generate_for_chapter/2" do
    test "creates task and enqueues job", %{book: book, ch1: ch1} do
      assert {:ok, task} = ReadaloudAudiobook.generate_for_chapter(book.id, ch1.id)
      assert task.status == "pending"
      assert task.scope == "chapter"
      assert_enqueued(worker: ReadaloudAudiobook.GenerateJob, args: %{task_id: task.id})
    end
  end

  describe "generate_for_book/1" do
    test "creates one task per chapter", %{book: book} do
      assert {:ok, tasks} = ReadaloudAudiobook.generate_for_book(book.id)
      assert length(tasks) == 2
      assert Enum.all?(tasks, &(&1.scope == "chapter"))
    end
  end

  describe "list_tasks/0" do
    test "returns all tasks", %{book: book, ch1: ch1} do
      {:ok, _} = ReadaloudAudiobook.generate_for_chapter(book.id, ch1.id)
      assert length(ReadaloudAudiobook.list_tasks()) == 1
    end
  end
end
