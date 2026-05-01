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

  def chapter_statuses(chapters, nil), do: Map.new(chapters, &{&1.id, :unread})

  def chapter_statuses(chapters, %{current_chapter_id: nil}),
    do: Map.new(chapters, &{&1.id, :unread})

  def chapter_statuses(chapters, %{current_chapter_id: current_id}) do
    current_number =
      case Enum.find(chapters, &(&1.id == current_id)) do
        nil -> nil
        ch -> ch.number
      end

    Map.new(chapters, fn ch ->
      status =
        cond do
          ch.id == current_id -> :current
          current_number && ch.number < current_number -> :read
          true -> :unread
        end

      {ch.id, status}
    end)
  end
end
