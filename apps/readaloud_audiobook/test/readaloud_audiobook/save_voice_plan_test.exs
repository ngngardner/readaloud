defmodule ReadaloudAudiobook.SaveVoicePlanTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias ReadaloudAudiobook.{AudiobookTask, VoicePlan}
  alias ReadaloudLibrary.Repo

  @plan %{
    "model" => "breeze-tts-2",
    "voice" => "heath-miller",
    "temperature" => 0.6,
    "chunks" => [
      %{
        "text" => "Feng Jiu Ge smiled.",
        "spoken" => "Fung Jyo Guhh smiled.",
        "voice" => "/models/voices/hwfwm-narration-0.wav",
        "reference_text" => "The walls were black."
      }
    ]
  }

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    storage = Path.join(System.tmp_dir!(), "save_plan_#{System.unique_integer([:positive])}")
    previous = System.get_env("STORAGE_PATH")
    System.put_env("STORAGE_PATH", storage)

    on_exit(fn ->
      if previous,
        do: System.put_env("STORAGE_PATH", previous),
        else: System.delete_env("STORAGE_PATH")

      File.rm_rf!(storage)
    end)

    {:ok, book} =
      ReadaloudLibrary.create_book(%{
        title: "Reverend Insanity",
        source_type: "epub",
        audio_preferences: %{model: "breeze-tts-2", voice: "heath-miller"}
      })

    {:ok, chapter} =
      ReadaloudLibrary.create_chapter(%{book_id: book.id, number: 212, content_path: "/dev/null"})

    %{book: book, chapter: chapter}
  end

  defp tasks(chapter), do: Repo.all(from(t in AudiobookTask, where: t.chapter_id == ^chapter.id))

  test "saves the plan and queues the chapter to be read with it", %{book: book, chapter: chapter} do
    assert {:ok, %VoicePlan{}, :queued} =
             ReadaloudAudiobook.save_voice_plan(book, chapter, @plan, 210)

    assert {:ok, _} = VoicePlan.load(chapter)
    assert [%{model: "breeze-tts-2", voice: "heath-miller", status: :pending}] = tasks(chapter)

    # Two chapters past the reader: picked up first.
    assert [0] = Repo.all(from(j in Oban.Job, where: j.queue == "tts", select: j.priority))
  end

  # A job that has not started yet reads the plan when it runs.
  test "does not queue twice when a job is already waiting", %{book: book, chapter: chapter} do
    {:ok, _} =
      ReadaloudAudiobook.generate_for_chapter(book.id, chapter.id,
        model: "breeze-tts-2",
        voice: "heath-miller"
      )

    assert {:ok, _, :already_queued} =
             ReadaloudAudiobook.save_voice_plan(book, chapter, @plan, 210)

    assert length(tasks(chapter)) == 1
  end

  test "saves but does not queue when the book reads with another voice", %{
    book: book,
    chapter: chapter
  } do
    {:ok, book} =
      ReadaloudLibrary.update_book(book, %{
        audio_preferences: %{model: "kokoro", voice: "af_heart"}
      })

    assert {:ok, _, :voice_differs} =
             ReadaloudAudiobook.save_voice_plan(book, chapter, @plan, 210)

    assert {:ok, _} = VoicePlan.load(chapter)
    assert tasks(chapter) == []
  end

  test "an invalid plan is refused and nothing is queued", %{book: book, chapter: chapter} do
    assert {:error, _} =
             ReadaloudAudiobook.save_voice_plan(book, chapter, %{@plan | "chunks" => []}, 210)

    assert tasks(chapter) == []
  end
end
