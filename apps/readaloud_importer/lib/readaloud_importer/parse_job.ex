defmodule ReadaloudImporter.ParseJob do
  use Oban.Worker, queue: :import, max_attempts: 3

  alias ReadaloudLibrary.Repo
  alias ReadaloudImporter.{ImportTask, EpubParser, PdfParser}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"task_id" => task_id}}) do
    task = Repo.get!(ImportTask, task_id)
    update_status(task, "processing")

    storage_dir = storage_path(task)
    File.mkdir_p!(storage_dir)

    result =
      case task.file_type do
        "epub" -> EpubParser.parse(task.file_path, storage_dir)
        "pdf" -> PdfParser.parse(task.file_path, storage_dir)
      end

    case result do
      {:ok, %{chapters: chapters, metadata: metadata}} ->
        {:ok, book} =
          ReadaloudLibrary.create_book(%{
            title: metadata.title,
            author: metadata.author,
            source_type: task.file_type,
            total_chapters: length(chapters)
          })

        for chapter_data <- chapters do
          content_path = Path.join(storage_dir, "#{String.pad_leading("#{chapter_data.number}", 3, "0")}.html")
          File.write!(content_path, chapter_data.content)

          ReadaloudLibrary.create_chapter(%{
            book_id: book.id,
            title: chapter_data.title,
            number: chapter_data.number,
            content_path: content_path,
            word_count: chapter_data.word_count
          })
        end

        update_status(task, "completed", book.id)
        :ok

      {:error, reason} ->
        update_status(task, "failed", nil, "#{reason}")
        {:error, reason}
    end
  end

  defp update_status(task, status, book_id \\ nil, error \\ nil) do
    task
    |> ImportTask.changeset(%{
      status: status,
      book_id: book_id,
      error_message: error,
      progress: if(status == "completed", do: 1.0, else: task.progress)
    })
    |> Repo.update!()
  end

  defp storage_path(task) do
    base = System.get_env("STORAGE_PATH", "priv/static/files")
    Path.join([base, "books", "import_#{task.id}"])
  end
end
