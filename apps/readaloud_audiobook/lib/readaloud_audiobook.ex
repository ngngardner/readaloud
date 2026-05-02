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
        job_opts =
          case Keyword.get(opts, :priority) do
            nil -> []
            p -> [priority: p]
          end

        %{"task_id" => task.id}
        |> GenerateJob.new(job_opts)
        |> Oban.insert()

        {:ok, task}

      error ->
        error
    end
  end

  def ensure_audio_generated(book, chapters, progress \\ nil)

  def ensure_audio_generated(%{audio_preferences: nil}, _chapters, _progress), do: {:ok, 0}

  def ensure_audio_generated(%{audio_preferences: prefs}, _chapters, _progress)
      when map_size(prefs) == 0,
      do: {:ok, 0}

  def ensure_audio_generated(book, chapters, progress) do
    model = book.audio_preferences["model"]
    voice = book.audio_preferences["voice"]
    chapter_ids = Enum.map(chapters, & &1.id)
    current_number = current_chapter_number(chapters, progress)

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

      generate_for_chapter(book.id, ch.id,
        model: model,
        voice: voice,
        attempt_number: attempt,
        priority: chapter_priority(ch.number, current_number)
      )
    end)

    # Re-prioritize already-pending jobs against the current reading position
    # so the queue picks up near-current chapters first.
    reprioritize_pending_jobs(chapters, current_number)

    {:ok, length(to_generate)}
  end

  @doc """
  Updates priority on already-queued Oban jobs based on chapter distance
  from the current reading position. Lower priority value = picked sooner.
  """
  def reprioritize_pending_jobs(_chapters, nil), do: :ok

  def reprioritize_pending_jobs(chapters, current_number) do
    chapter_ids = Enum.map(chapters, & &1.id)
    number_by_chapter_id = Map.new(chapters, &{&1.id, &1.number})

    pending_tasks =
      AudiobookTask
      |> where([t], t.chapter_id in ^chapter_ids and t.status == "pending")
      |> select([t], {t.id, t.chapter_id})
      |> Repo.all()

    pending_tasks
    |> Enum.group_by(
      fn {_task_id, chapter_id} ->
        number_by_chapter_id |> Map.get(chapter_id) |> chapter_priority(current_number)
      end,
      fn {task_id, _chapter_id} -> task_id end
    )
    |> Enum.each(fn {priority, task_ids} ->
      from(j in "oban_jobs",
        where:
          j.state in ["available", "scheduled", "retryable"] and j.queue == "tts" and
            fragment("CAST(json_extract(?, '$.task_id') AS INTEGER)", j.args) in ^task_ids and
            j.priority != ^priority
      )
      |> Repo.update_all(set: [priority: priority])
    end)

    :ok
  end

  defp current_chapter_number(_chapters, nil), do: nil
  defp current_chapter_number(_chapters, %{current_chapter_id: nil}), do: nil

  defp current_chapter_number(chapters, %{current_chapter_id: current_id}) do
    case Enum.find(chapters, &(&1.id == current_id)) do
      nil -> nil
      ch -> ch.number
    end
  end

  defp chapter_priority(_chapter_number, nil), do: 0
  defp chapter_priority(nil, _current_number), do: 5

  defp chapter_priority(chapter_number, current_number) do
    offset = chapter_number - current_number

    cond do
      offset < 0 -> 9
      offset <= 4 -> 0
      offset <= 19 -> 1
      offset <= 49 -> 2
      offset <= 99 -> 3
      true -> 5
    end
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
