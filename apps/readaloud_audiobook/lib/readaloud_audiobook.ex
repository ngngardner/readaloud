defmodule ReadaloudAudiobook do
  alias ReadaloudAudiobook.{AudiobookTask, ChapterAudio, GenerateJob}
  alias ReadaloudLibrary.Repo
  import Ecto.Query

  @max_attempts 3

  def generate_for_chapter(book_id, chapter_id, opts \\ []) do
    attrs =
      %{book_id: book_id, chapter_id: chapter_id, scope: "chapter"}
      |> maybe_put(:voice, Keyword.get(opts, :voice))
      |> maybe_put(:speed, Keyword.get(opts, :speed))
      |> maybe_put(:model, Keyword.get(opts, :model))
      |> maybe_put(:attempt_number, Keyword.get(opts, :attempt_number))

    case %AudiobookTask{} |> AudiobookTask.changeset(attrs) |> Repo.insert() do
      {:ok, task} ->
        %{"task_id" => task.id}
        |> GenerateJob.new()
        |> Oban.insert()

        {:ok, task}

      error ->
        error
    end
  end

  def ensure_audio_generated(%{audio_preferences: nil}, _chapters), do: {:ok, 0}

  def ensure_audio_generated(%{audio_preferences: prefs}, _chapters) when map_size(prefs) == 0,
    do: {:ok, 0}

  def ensure_audio_generated(book, chapters) do
    model = book.audio_preferences["model"]
    voice = book.audio_preferences["voice"]
    chapter_ids = Enum.map(chapters, & &1.id)

    # Load existing state
    audios = list_chapter_audio_for_chapters(chapter_ids)
    tasks = list_tasks_for_chapters(chapter_ids)

    # Index by chapter_id for fast lookup
    audio_by_chapter = Map.new(audios, &{&1.chapter_id, &1})

    pending_chapter_ids =
      tasks
      |> Enum.filter(&(&1.status in ["pending", "processing"]))
      |> Enum.map(& &1.chapter_id)
      |> MapSet.new()

    failed_by_chapter = failed_tasks_by_chapter(tasks, model, voice)

    # Determine which chapters need generation
    to_generate =
      Enum.filter(chapters, fn ch ->
        audio = Map.get(audio_by_chapter, ch.id)
        has_pending = MapSet.member?(pending_chapter_ids, ch.id)
        failed_task = Map.get(failed_by_chapter, ch.id)

        needs_audio = audio == nil || audio.model != model || audio.voice != voice
        not_in_flight = !has_pending
        not_exhausted = failed_task == nil || failed_task.attempt_number < @max_attempts

        needs_audio && not_in_flight && not_exhausted
      end)

    # Queue generation for each (fire-and-forget)
    Enum.each(to_generate, fn ch ->
      failed_task = Map.get(failed_by_chapter, ch.id)
      attempt = if failed_task, do: failed_task.attempt_number + 1, else: 1
      generate_for_chapter(book.id, ch.id, model: model, voice: voice, attempt_number: attempt)
    end)

    {:ok, length(to_generate)}
  end

  def list_tasks do
    AudiobookTask |> order_by(desc: :inserted_at) |> Repo.all()
  end

  def get_task(id), do: Repo.get(AudiobookTask, id)

  def clear_completed_tasks do
    from(t in AudiobookTask, where: t.status in ["completed", "failed"])
    |> Repo.delete_all()
  end

  def get_chapter_audio(chapter_id) do
    ChapterAudio |> where(chapter_id: ^chapter_id) |> Repo.one()
  end

  def list_chapter_audio_for_chapters(chapter_ids) when is_list(chapter_ids) do
    ChapterAudio |> where([a], a.chapter_id in ^chapter_ids) |> Repo.all()
  end

  def list_tasks_for_chapters(chapter_ids) when is_list(chapter_ids) do
    AudiobookTask
    |> where(
      [t],
      t.chapter_id in ^chapter_ids and t.status in ["pending", "processing", "failed"]
    )
    |> Repo.all()
  end

  def task_stats do
    AudiobookTask
    |> group_by(:status)
    |> select([t], {t.status, count(t.id)})
    |> Repo.all()
    |> Map.new()
  end

  def failed_tasks_by_chapter(tasks, model, voice) do
    tasks
    |> Enum.filter(&(&1.status == "failed" && &1.model == model && &1.voice == voice))
    |> Enum.group_by(& &1.chapter_id)
    |> Map.new(fn {ch_id, ch_tasks} ->
      {ch_id, Enum.max_by(ch_tasks, & &1.updated_at)}
    end)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
