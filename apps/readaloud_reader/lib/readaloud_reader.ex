defmodule ReadaloudReader do
  alias ReadaloudLibrary.Repo
  alias ReadaloudReader.ReadingProgress
  import Ecto.Query

  def get_progress(book_id) do
    ReadingProgress |> where(book_id: ^book_id) |> Repo.one()
  end

  def list_progress_for_books(book_ids) when is_list(book_ids) do
    ReadingProgress |> where([p], p.book_id in ^book_ids) |> Repo.all()
  end

  def upsert_progress(attrs) do
    case get_progress(attrs.book_id) do
      nil -> %ReadingProgress{}
      existing -> existing
    end
    |> ReadingProgress.changeset(attrs)
    |> Repo.insert_or_update()
  end
end
