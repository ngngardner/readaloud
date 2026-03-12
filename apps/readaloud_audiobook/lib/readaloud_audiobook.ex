defmodule ReadaloudAudiobook do
  alias ReadaloudLibrary.Repo
  alias ReadaloudAudiobook.{AudiobookTask, ChapterAudio, GenerateJob}
  import Ecto.Query

  def generate_for_chapter(book_id, chapter_id, opts \\ []) do
    voice = Keyword.get(opts, :voice)
    speed = Keyword.get(opts, :speed)
    model = Keyword.get(opts, :model)

    attrs = %{book_id: book_id, chapter_id: chapter_id, scope: "chapter", voice: voice, speed: speed, model: model}

    {:ok, task} =
      %AudiobookTask{}
      |> AudiobookTask.changeset(attrs)
      |> Repo.insert()

    %{"task_id" => task.id}
    |> GenerateJob.new()
    |> Oban.insert()

    {:ok, task}
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

  def get_chapter_audio(chapter_id) do
    ChapterAudio |> where(chapter_id: ^chapter_id) |> Repo.one()
  end

  def task_stats do
    AudiobookTask
    |> group_by(:status)
    |> select([t], {t.status, count(t.id)})
    |> Repo.all()
    |> Map.new()
  end
end
