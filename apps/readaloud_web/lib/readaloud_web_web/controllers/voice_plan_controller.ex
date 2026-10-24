defmodule ReadaloudWebWeb.VoicePlanController do
  @moduledoc """
  JSON API for the voice-refs planner (`tools/voice-refs`), which runs on the
  GPU host and plans how each chapter is read: it lists a book's chapters,
  fetches each chapter's text, and uploads the plan it made, which queues the
  chapter to be read again with it. See `ReadaloudAudiobook.VoicePlan`.
  """

  use ReadaloudWebWeb, :controller

  alias ReadaloudAudiobook.VoicePlan

  @plan_keys ["model", "voice", "temperature", "chunks"]

  def index(conn, %{"book_id" => book_id}) do
    chapters =
      book_id
      |> String.to_integer()
      |> ReadaloudLibrary.list_chapters()
      |> Enum.map(fn ch ->
        %{
          id: ch.id,
          number: ch.number,
          title: ch.title,
          voice_plan: File.exists?(VoicePlan.path(ch))
        }
      end)

    json(conn, %{chapters: chapters})
  end

  def text(conn, params) do
    with {:ok, _book, chapter} <- fetch(params),
         {:ok, html} <- ReadaloudLibrary.get_chapter_content(chapter) do
      json(conn, %{id: chapter.id, number: chapter.number, title: chapter.title, html: html})
    else
      :not_found -> not_found(conn)
      {:error, reason} -> conn |> put_status(500) |> json(%{error: inspect(reason)})
    end
  end

  def update(conn, params) do
    with {:ok, book, chapter} <- fetch(params),
         {:ok, plan, queue} <-
           ReadaloudAudiobook.save_voice_plan(
             book,
             chapter,
             Map.take(params, @plan_keys),
             current_number(book.id)
           ) do
      json(conn, %{chunks: length(plan.chunks), queue: queue})
    else
      :not_found -> not_found(conn)
      {:error, reason} -> conn |> put_status(422) |> json(%{error: reason})
    end
  end

  defp fetch(%{"book_id" => book_id, "chapter_id" => chapter_id}) do
    book_id = String.to_integer(book_id)

    with %{} = book <- ReadaloudLibrary.get_book(book_id),
         %{book_id: ^book_id} = chapter <-
           ReadaloudLibrary.get_chapter(String.to_integer(chapter_id)) do
      {:ok, book, chapter}
    else
      _ -> :not_found
    end
  end

  defp current_number(book_id) do
    with %{current_chapter_id: id} when not is_nil(id) <- ReadaloudReader.get_progress(book_id),
         %{number: number} <- ReadaloudLibrary.get_chapter(id) do
      number
    else
      _ -> nil
    end
  end

  defp not_found(conn), do: conn |> put_status(404) |> json(%{error: "not_found"})
end
