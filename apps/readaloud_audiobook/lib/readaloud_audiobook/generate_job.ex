defmodule ReadaloudAudiobook.GenerateJob do
  use Oban.Worker, queue: :tts, max_attempts: 3

  alias ReadaloudLibrary.Repo
  alias ReadaloudAudiobook.{AudiobookTask, ChapterAudio}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"task_id" => task_id}}) do
    task = Repo.get!(AudiobookTask, task_id)
    update_task(task, %{status: "processing"})

    chapter = ReadaloudLibrary.get_chapter!(task.chapter_id)

    with {:ok, text} <- ReadaloudLibrary.get_chapter_content(chapter),
         clean_text = strip_html(text),
         {:ok, %{audio: audio}} <- ReadaloudTTS.synthesize(clean_text, voice: task.voice, speed: task.speed),
         {:ok, timings} <- ReadaloudTTS.transcribe(audio) do
      audio_path = audio_storage_path(chapter)
      File.mkdir_p!(Path.dirname(audio_path))
      File.write!(audio_path, audio)

      %ChapterAudio{}
      |> ChapterAudio.changeset(%{
        chapter_id: chapter.id,
        audio_path: audio_path,
        duration_seconds: calculate_duration(audio),
        word_timings: Jason.encode!(timings)
      })
      |> Repo.insert!(on_conflict: :replace_all, conflict_target: :chapter_id)

      update_task(task, %{status: "completed", progress: 1.0})
      :ok
    else
      {:error, reason} ->
        update_task(task, %{status: "failed", error_message: "#{inspect(reason)}"})
        {:error, reason}
    end
  end

  defp strip_html(html) do
    html
    |> String.replace(~r/<[^>]+>/, " ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp update_task(task, attrs) do
    task |> AudiobookTask.changeset(attrs) |> Repo.update!()
  end

  defp audio_storage_path(chapter) do
    base = System.get_env("STORAGE_PATH", "priv/static/files")
    padded = String.pad_leading("#{chapter.number}", 3, "0")
    Path.join([base, "books", "#{chapter.book_id}", "chapters", "#{padded}.wav"])
  end

  defp calculate_duration(wav_bytes) do
    byte_size(wav_bytes) / (22050 * 2)
  end
end
