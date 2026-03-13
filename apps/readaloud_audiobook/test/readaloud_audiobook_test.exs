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

  describe "list_tasks/0" do
    test "returns all tasks", %{book: book, ch1: ch1} do
      {:ok, _} = ReadaloudAudiobook.generate_for_chapter(book.id, ch1.id)
      assert length(ReadaloudAudiobook.list_tasks()) == 1
    end
  end

  describe "AudiobookTask.changeset/2" do
    test "casts attempt_number" do
      changeset = ReadaloudAudiobook.AudiobookTask.changeset(
        %ReadaloudAudiobook.AudiobookTask{},
        %{book_id: 1, scope: "chapter", attempt_number: 2}
      )
      assert changeset.changes[:attempt_number] == 2
    end

    test "attempt_number not cast when not in cast list" do
      changeset = ReadaloudAudiobook.AudiobookTask.changeset(
        %ReadaloudAudiobook.AudiobookTask{},
        %{book_id: 1, scope: "chapter", attempt_number: 5}
      )
      assert changeset.changes[:attempt_number] == 5
    end
  end

  describe "ChapterAudio.changeset/2" do
    test "casts model and voice" do
      changeset = ReadaloudAudiobook.ChapterAudio.changeset(
        %ReadaloudAudiobook.ChapterAudio{},
        %{chapter_id: 1, audio_path: "/tmp/test.wav", model: "kokoro", voice: "af_heart"}
      )
      assert changeset.changes[:model] == "kokoro"
      assert changeset.changes[:voice] == "af_heart"
    end
  end

  describe "generate_for_chapter/3 with attempt_number" do
    test "passes attempt_number to task", %{book: book, ch1: ch1} do
      assert {:ok, task} = ReadaloudAudiobook.generate_for_chapter(book.id, ch1.id, attempt_number: 2)
      assert task.attempt_number == 2
    end

    test "defaults attempt_number to 1", %{book: book, ch1: ch1} do
      assert {:ok, task} = ReadaloudAudiobook.generate_for_chapter(book.id, ch1.id)
      assert task.attempt_number == 1
    end
  end

  describe "ensure_audio_generated/2" do
    test "returns {:ok, 0} when audio_preferences is nil", %{book: book} do
      chapters = ReadaloudLibrary.list_chapters(book.id)
      assert {:ok, 0} = ReadaloudAudiobook.ensure_audio_generated(book, chapters)
    end

    test "queues chapters missing audio", %{book: book, ch1: _ch1, ch2: _ch2} do
      {:ok, book} = ReadaloudLibrary.update_book(book, %{audio_preferences: %{"model" => "kokoro", "voice" => "af_heart"}})
      chapters = ReadaloudLibrary.list_chapters(book.id)

      assert {:ok, 2} = ReadaloudAudiobook.ensure_audio_generated(book, chapters)

      tasks = ReadaloudAudiobook.list_tasks()
      assert length(tasks) == 2
      assert Enum.all?(tasks, &(&1.model == "kokoro"))
      assert Enum.all?(tasks, &(&1.voice == "af_heart"))
      assert Enum.all?(tasks, &(&1.attempt_number == 1))
    end

    test "skips chapters with existing matching audio", %{book: book, ch1: ch1, ch2: _ch2} do
      {:ok, book} = ReadaloudLibrary.update_book(book, %{audio_preferences: %{"model" => "kokoro", "voice" => "af_heart"}})

      # Insert matching audio for ch1
      %ReadaloudAudiobook.ChapterAudio{}
      |> ReadaloudAudiobook.ChapterAudio.changeset(%{
        chapter_id: ch1.id, audio_path: "/tmp/test.wav",
        duration_seconds: 60.0, model: "kokoro", voice: "af_heart"
      })
      |> ReadaloudLibrary.Repo.insert!()

      chapters = ReadaloudLibrary.list_chapters(book.id)
      assert {:ok, 1} = ReadaloudAudiobook.ensure_audio_generated(book, chapters)
    end

    test "queues chapters with stale audio (different model/voice)", %{book: book, ch1: ch1} do
      {:ok, book} = ReadaloudLibrary.update_book(book, %{audio_preferences: %{"model" => "kokoro", "voice" => "af_heart"}})

      # Insert audio with old voice
      %ReadaloudAudiobook.ChapterAudio{}
      |> ReadaloudAudiobook.ChapterAudio.changeset(%{
        chapter_id: ch1.id, audio_path: "/tmp/test.wav",
        duration_seconds: 60.0, model: "kokoro", voice: "bf_emma"
      })
      |> ReadaloudLibrary.Repo.insert!()

      chapters = ReadaloudLibrary.list_chapters(book.id)
      assert {:ok, 2} = ReadaloudAudiobook.ensure_audio_generated(book, chapters)
    end

    test "skips chapters with pending/processing tasks", %{book: book, ch1: ch1} do
      {:ok, book} = ReadaloudLibrary.update_book(book, %{audio_preferences: %{"model" => "kokoro", "voice" => "af_heart"}})

      # Create pending task for ch1
      ReadaloudAudiobook.generate_for_chapter(book.id, ch1.id, model: "kokoro", voice: "af_heart")

      chapters = ReadaloudLibrary.list_chapters(book.id)
      # ch1 already has a pending task, only ch2 should be queued
      assert {:ok, 1} = ReadaloudAudiobook.ensure_audio_generated(book, chapters)
    end

    test "skips chapters that exceeded failure threshold", %{book: book, ch1: ch1} do
      {:ok, book} = ReadaloudLibrary.update_book(book, %{audio_preferences: %{"model" => "kokoro", "voice" => "af_heart"}})

      # Insert a failed task at attempt_number 3 for ch1 with matching profile
      %ReadaloudAudiobook.AudiobookTask{}
      |> ReadaloudAudiobook.AudiobookTask.changeset(%{
        book_id: book.id, chapter_id: ch1.id, scope: "chapter",
        model: "kokoro", voice: "af_heart", status: "failed",
        attempt_number: 3, error_message: "permanent failure"
      })
      |> ReadaloudLibrary.Repo.insert!()

      chapters = ReadaloudLibrary.list_chapters(book.id)
      # ch1 is skipped (attempt_number >= 3), only ch2 queued
      assert {:ok, 1} = ReadaloudAudiobook.ensure_audio_generated(book, chapters)
    end

    test "resets failure count when profile changes", %{book: book, ch1: ch1} do
      # Failed with old voice
      %ReadaloudAudiobook.AudiobookTask{}
      |> ReadaloudAudiobook.AudiobookTask.changeset(%{
        book_id: book.id, chapter_id: ch1.id, scope: "chapter",
        model: "kokoro", voice: "bf_emma", status: "failed",
        attempt_number: 3, error_message: "permanent failure"
      })
      |> ReadaloudLibrary.Repo.insert!()

      # Switch to different voice
      {:ok, book} = ReadaloudLibrary.update_book(book, %{audio_preferences: %{"model" => "kokoro", "voice" => "af_heart"}})

      chapters = ReadaloudLibrary.list_chapters(book.id)
      # Both should be queued — old failures don't count for new profile
      assert {:ok, 2} = ReadaloudAudiobook.ensure_audio_generated(book, chapters)
    end

    test "is idempotent", %{book: book} do
      {:ok, book} = ReadaloudLibrary.update_book(book, %{audio_preferences: %{"model" => "kokoro", "voice" => "af_heart"}})
      chapters = ReadaloudLibrary.list_chapters(book.id)

      assert {:ok, 2} = ReadaloudAudiobook.ensure_audio_generated(book, chapters)
      # Second call should queue nothing (tasks already pending)
      assert {:ok, 0} = ReadaloudAudiobook.ensure_audio_generated(book, chapters)
    end

    test "increments attempt_number on retry", %{book: book, ch1: ch1} do
      {:ok, book} = ReadaloudLibrary.update_book(book, %{audio_preferences: %{"model" => "kokoro", "voice" => "af_heart"}})

      # Insert a failed task at attempt_number 1
      %ReadaloudAudiobook.AudiobookTask{}
      |> ReadaloudAudiobook.AudiobookTask.changeset(%{
        book_id: book.id, chapter_id: ch1.id, scope: "chapter",
        model: "kokoro", voice: "af_heart", status: "failed",
        attempt_number: 1, error_message: "transient error"
      })
      |> ReadaloudLibrary.Repo.insert!()

      chapters = ReadaloudLibrary.list_chapters(book.id)
      assert {:ok, 2} = ReadaloudAudiobook.ensure_audio_generated(book, chapters)

      # Find the new task for ch1
      tasks = ReadaloudAudiobook.list_tasks()
      ch1_task = Enum.find(tasks, &(&1.chapter_id == ch1.id && &1.status == "pending"))
      assert ch1_task.attempt_number == 2
    end
  end
end
