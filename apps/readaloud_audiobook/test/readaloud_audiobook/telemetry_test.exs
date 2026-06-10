defmodule ReadaloudAudiobook.TelemetryTest do
  use ExUnit.Case, async: false

  alias ReadaloudAudiobook.{AudiobookTask, GenerateJob}
  alias ReadaloudLibrary.{Repo, Tasks}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    {:ok, book} = ReadaloudLibrary.create_book(%{title: "Telemetry", source_type: "epub"})
    %{book: book}
  end

  defp attach(events) do
    ref = :telemetry_test.attach_event_handlers(self(), events)
    on_exit(fn -> :telemetry.detach(ref) end)
    ref
  end

  defp insert_task(book, chapter) do
    %AudiobookTask{}
    |> AudiobookTask.changeset(%{
      book_id: book.id,
      chapter_id: chapter.id,
      model: "kokoro",
      voice: "af_heart",
      status: :pending,
      attempt_number: 1
    })
    |> Repo.insert!()
  end

  test "task transitions emit kind + target status", %{book: book} do
    {:ok, chapter} = ReadaloudLibrary.create_chapter(%{book_id: book.id, number: 1})
    task = insert_task(book, chapter)
    ref = attach([[:readaloud, :task, :transition]])

    {:ok, task} = Tasks.start(task)

    assert_received {[:readaloud, :task, :transition], ^ref, %{count: 1},
                     %{kind: "audiobook", to: "processing"}}

    {:ok, _task} = Tasks.complete(task)

    assert_received {[:readaloud, :task, :transition], ^ref, %{count: 1},
                     %{kind: "audiobook", to: "completed"}}
  end

  test "failed generation emits a chapter stop span with error status", %{book: book} do
    empty_path =
      Path.join(System.tmp_dir!(), "telemetry_chapter_#{System.unique_integer([:positive])}.html")

    File.write!(empty_path, "")

    {:ok, chapter} =
      ReadaloudLibrary.create_chapter(%{book_id: book.id, number: 1, content_path: empty_path})

    task = insert_task(book, chapter)
    ref = attach([[:readaloud, :tts, :chapter, :stop]])

    job = %Oban.Job{id: 0, args: %{"task_id" => task.id}}
    assert {:error, :empty_chapter_content} = GenerateJob.perform(job)

    assert_received {[:readaloud, :tts, :chapter, :stop], ^ref, %{duration: duration},
                     %{status: "error"}}

    assert is_integer(duration) and duration >= 0
  end
end
