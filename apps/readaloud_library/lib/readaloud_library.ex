defmodule ReadaloudLibrary do
  alias ReadaloudLibrary.{Book, Chapter, Repo}
  import Ecto.Query

  # Books
  def list_books, do: Repo.all(Book)
  def get_book(id), do: Repo.get(Book, id)
  def get_book!(id), do: Repo.get!(Book, id)

  def create_book(attrs) do
    %Book{} |> Book.changeset(attrs) |> Repo.insert()
  end

  def update_book(%Book{} = book, attrs) do
    book
    |> Book.changeset(attrs)
    |> Repo.update()
  end

  def delete_book(%Book{} = book), do: Repo.delete(book)

  def search_books(query_string) when is_binary(query_string) do
    escaped = query_string |> String.replace("%", "\\%") |> String.replace("_", "\\_")
    pattern = "%#{escaped}%"

    from(b in Book,
      where: ilike(b.title, ^pattern) or ilike(b.author, ^pattern),
      order_by: [desc: b.inserted_at]
    )
    |> Repo.all()
  end

  def list_books_sorted(sort_by) do
    base = from(b in Book)

    query =
      case sort_by do
        "title" ->
          from(b in base, order_by: [asc: b.title])

        "author" ->
          from(b in base, order_by: [asc: b.author, asc: b.title])

        "added" ->
          from(b in base, order_by: [desc: b.inserted_at])

        _ ->
          # "recent" default: sort by last reading activity
          from(b in base,
            left_join: rp in ReadaloudReader.ReadingProgress,
            on: rp.book_id == b.id,
            order_by: [desc_nulls_last: rp.last_read_at, desc: b.inserted_at]
          )
      end

    Repo.all(query)
  end

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
