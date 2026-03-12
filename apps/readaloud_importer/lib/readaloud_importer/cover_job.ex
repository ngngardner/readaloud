defmodule ReadaloudImporter.CoverJob do
  use Oban.Worker, queue: :import, max_attempts: 1

  alias ReadaloudImporter.CoverResolver
  alias ReadaloudLibrary.{Repo, Book}

  @impl true
  def perform(%Oban.Job{args: %{"book_id" => book_id, "title" => title, "author" => author}}) do
    case CoverResolver.fetch_from_open_library(title, author) do
      {:ok, image_bytes} ->
        {:ok, path} = CoverResolver.save_cover(book_id, image_bytes)

        Repo.get!(Book, book_id)
        |> Ecto.Changeset.change(%{cover_path: path})
        |> Repo.update!()

        :ok

      {:error, _reason} ->
        # No cover found -- not a failure, just no result. Book keeps gradient placeholder.
        :ok
    end
  end
end
