defmodule ReadaloudLibrary do
  alias ReadaloudLibrary.{Repo, Book, Chapter}
  import Ecto.Query

  # Books
  def list_books, do: Repo.all(Book)
  def get_book(id), do: Repo.get(Book, id)
  def get_book!(id), do: Repo.get!(Book, id)

  def create_book(attrs) do
    %Book{} |> Book.changeset(attrs) |> Repo.insert()
  end

  def delete_book(%Book{} = book), do: Repo.delete(book)

  # Chapters
  def list_chapters(book_id) do
    Chapter |> where(book_id: ^book_id) |> order_by(:number) |> Repo.all()
  end

  def get_chapter(id), do: Repo.get(Chapter, id)
  def get_chapter!(id), do: Repo.get!(Chapter, id)

  def create_chapter(attrs) do
    %Chapter{} |> Chapter.changeset(attrs) |> Repo.insert()
  end

  def get_chapter_content(chapter) do
    case File.read(chapter.content_path) do
      {:ok, content} -> {:ok, content}
      {:error, reason} -> {:error, reason}
    end
  end
end
