defmodule ReadaloudAudiobook.PlanJobTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias ReadaloudAudiobook.{PlanJob, VoicePlan}
  alias ReadaloudLibrary.Repo

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    storage = Path.join(System.tmp_dir!(), "plan_job_#{System.unique_integer([:positive])}")
    File.mkdir_p!(storage)
    previous = System.get_env("STORAGE_PATH")
    System.put_env("STORAGE_PATH", storage)

    Application.put_env(:readaloud_audiobook, :planner_opts,
      chat: ReadaloudAudiobook.PlannerTest.model()
    )

    on_exit(fn ->
      Application.delete_env(:readaloud_audiobook, :planner_opts)

      if previous,
        do: System.put_env("STORAGE_PATH", previous),
        else: System.delete_env("STORAGE_PATH")

      File.rm_rf!(storage)
    end)

    html = Path.join(storage, "ch.html")
    File.write!(html, "<p>Feng Jiu Ge smiled.</p><p>“Leave,” she said.</p>")
    {:ok, book} = ReadaloudLibrary.create_book(%{title: "RI", source_type: "epub"})

    {:ok, chapter} =
      ReadaloudLibrary.create_chapter(%{book_id: book.id, number: 5, content_path: html})

    %{book: book, chapter: chapter}
  end

  defp plan_jobs, do: Repo.all(from(j in Oban.Job, where: j.queue == "plan"))

  test "plans a chapter ahead of its generation job", %{chapter: chapter} do
    args = %{"chapter_id" => chapter.id, "model" => "breeze-tts-2", "voice" => "heath-miller"}
    assert :ok = PlanJob.perform(%Oban.Job{args: args})
    assert {:ok, _} = VoicePlan.load(chapter)
  end

  test "a chapter already planned is left alone", %{chapter: chapter} do
    args = %{"chapter_id" => chapter.id, "model" => "breeze-tts-2", "voice" => "heath-miller"}
    :ok = PlanJob.perform(%Oban.Job{args: args})

    Application.put_env(:readaloud_audiobook, :planner_opts,
      chat: fn _, _, _ -> flunk("asked the model again") end
    )

    assert :ok = PlanJob.perform(%Oban.Job{args: args})
  end

  test "queueing generation for a voice with a library also queues its planning", %{
    book: book,
    chapter: chapter
  } do
    {:ok, _} =
      ReadaloudAudiobook.generate_for_chapter(book.id, chapter.id,
        model: "breeze-tts-2",
        voice: "heath-miller",
        priority: 1
      )

    assert [%{args: %{"chapter_id" => id}, priority: 1}] = plan_jobs()
    assert id == chapter.id
  end

  test "voices without a library queue no planning", %{book: book, chapter: chapter} do
    {:ok, _} =
      ReadaloudAudiobook.generate_for_chapter(book.id, chapter.id,
        model: "kokoro",
        voice: "af_heart"
      )

    assert plan_jobs() == []
  end
end
