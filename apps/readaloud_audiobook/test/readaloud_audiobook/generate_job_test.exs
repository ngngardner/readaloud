defmodule ReadaloudAudiobook.GenerateJobTest do
  use ExUnit.Case, async: false

  alias ReadaloudAudiobook.{AudiobookTask, GenerateJob}
  alias ReadaloudLibrary.Repo

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    {:ok, book} = ReadaloudLibrary.create_book(%{title: "Empty test", source_type: "epub"})
    %{book: book}
  end

  # Regression: chapters with no text used to land on LocalAI as an empty
  # synthesis call, which 500s and burns Oban retry attempts. Now we fail
  # fast with :empty_chapter_content and never hit the network.
  describe "perform/1 on empty chapter content" do
    test "fails the task with empty_chapter_content and does not call TTS", %{book: book} do
      empty_path =
        Path.join(System.tmp_dir!(), "empty_chapter_#{System.unique_integer([:positive])}.html")

      File.write!(empty_path, "")

      {:ok, chapter} =
        ReadaloudLibrary.create_chapter(%{book_id: book.id, number: 1, content_path: empty_path})

      task =
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

      job = %Oban.Job{id: 0, args: %{"task_id" => task.id}}

      assert {:error, :empty_chapter_content} = GenerateJob.perform(job)

      reloaded = Repo.get!(AudiobookTask, task.id)
      assert reloaded.status == :failed
      assert reloaded.error_message =~ "empty_chapter_content"
    end

    test "fails on whitespace-only HTML", %{book: book} do
      path = Path.join(System.tmp_dir!(), "ws_chapter_#{System.unique_integer([:positive])}.html")
      File.write!(path, "<p>   </p>\n<div>&nbsp;</div>")

      {:ok, chapter} =
        ReadaloudLibrary.create_chapter(%{book_id: book.id, number: 2, content_path: path})

      task =
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

      job = %Oban.Job{id: 0, args: %{"task_id" => task.id}}

      assert {:error, :empty_chapter_content} = GenerateJob.perform(job)
    end
  end
end
