defmodule ReadaloudAudiobook do
  alias ReadaloudLibrary.Repo
  alias ReadaloudAudiobook.{AudiobookTask, ChapterAudio, GenerateJob}
  import Ecto.Query

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

  def generate_for_book(book_id, opts \\ []) do
    chapters = ReadaloudLibrary.list_chapters(book_id)

    tasks =
      Enum.map(chapters, fn chapter ->
        {:ok, task} = generate_for_chapter(book_id, chapter.id, opts)
        task
      end)

    {:ok, tasks}
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
    |> where([t], t.chapter_id in ^chapter_ids and t.status in ["pending", "processing", "failed"])
    |> Repo.all()
  end

  def task_stats do
    AudiobookTask
    |> group_by(:status)
    |> select([t], {t.status, count(t.id)})
    |> Repo.all()
    |> Map.new()
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
