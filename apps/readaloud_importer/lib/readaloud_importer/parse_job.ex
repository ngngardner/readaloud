defmodule ReadaloudImporter.ParseJob do
  use Oban.Worker, queue: :import, max_attempts: 3

  alias ReadaloudImporter.{CoverJob, CoverResolver, EpubParser, ImportTask, PdfParser}
  alias ReadaloudLibrary.{Repo, Tasks}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"task_id" => task_id}}) do
    task = Repo.get!(ImportTask, task_id)
    {:ok, task} = Tasks.start(task)

    storage_dir = storage_path(task)
    File.mkdir_p!(storage_dir)

    result =
      case task.file_type do
        :epub -> EpubParser.parse(task.file_path, storage_dir)
        :pdf -> PdfParser.parse(task.file_path, storage_dir)
      end

    case result do
      {:ok, %{chapters: chapters, metadata: metadata} = result} ->
        {:ok, book} =
          ReadaloudLibrary.create_book(%{
            title: metadata.title,
            author: metadata.author,
            source_type: task.file_type,
            total_chapters: length(chapters)
          })

        for chapter_data <- chapters do
          content_path =
            Path.join(storage_dir, "#{String.pad_leading("#{chapter_data.number}", 3, "0")}.html")

          File.write!(content_path, chapter_data.content)

          ReadaloudLibrary.create_chapter(%{
            book_id: book.id,
            title: chapter_data.title,
            number: chapter_data.number,
            content_path: content_path,
            word_count: chapter_data.word_count
          })
        end

        # Handle cover image: save embedded cover or enqueue Open Library lookup
        case Map.get(result, :cover_image) do
          bytes when is_binary(bytes) ->
            case CoverResolver.save_cover(book.id, bytes) do
              {:ok, _path} ->
                Ecto.Changeset.change(book, %{cover_path: CoverResolver.cover_path(book.id)})
                |> Repo.update!()

              {:error, _reason} ->
                %{"book_id" => book.id, "title" => book.title, "author" => book.author}
                |> CoverJob.new()
                |> Oban.insert()
            end

          _ ->
            %{"book_id" => book.id, "title" => book.title, "author" => book.author}
            |> CoverJob.new()
            |> Oban.insert()
        end

        {:ok, _task} = Tasks.complete(task, %{book_id: book.id})
        :ok

      {:error, reason} ->
        Tasks.fail(task, "#{reason}")
        {:error, reason}
    end
  end

  defp storage_path(task) do
    base = System.get_env("STORAGE_PATH", "priv/static/files")
    Path.join([base, "books", "import_#{task.id}"])
  end
end
