defmodule ReadaloudWebWeb.AudioController do
  use ReadaloudWebWeb, :controller

  alias ReadaloudWebWeb.ChapterNeighbors

  def stream(conn, %{"chapter_id" => chapter_id}) do
    case ReadaloudAudiobook.get_chapter_audio(String.to_integer(chapter_id)) do
      nil ->
        send_resp(conn, 404, "No audio")

      audio ->
        file_size = File.stat!(audio.audio_path).size

        conn =
          conn
          |> put_resp_content_type("audio/wav")
          |> put_resp_header("accept-ranges", "bytes")

        case get_req_header(conn, "range") do
          ["bytes=" <> range_spec] ->
            case parse_range(range_spec, file_size) do
              {range_start, range_end} ->
                length = range_end - range_start + 1

                conn
                |> put_resp_header(
                  "content-range",
                  "bytes #{range_start}-#{range_end}/#{file_size}"
                )
                |> send_file(206, audio.audio_path, range_start, length)

              :invalid ->
                conn
                |> put_resp_header("content-range", "bytes */#{file_size}")
                |> send_resp(416, "Range Not Satisfiable")
            end

          _ ->
            send_file(conn, 200, audio.audio_path)
        end
    end
  end

  defp parse_range(range_spec, file_size) do
    case String.split(range_spec, "-", parts: 2) do
      [start_str, ""] ->
        start = String.to_integer(start_str)
        if start < file_size, do: {start, file_size - 1}, else: :invalid

      ["", suffix_str] ->
        suffix = String.to_integer(suffix_str)
        start = max(0, file_size - suffix)
        {start, file_size - 1}

      [start_str, end_str] ->
        start = String.to_integer(start_str)
        end_pos = min(String.to_integer(end_str), file_size - 1)
        if start <= end_pos, do: {start, end_pos}, else: :invalid

      _ ->
        :invalid
    end
  end

  # Neighbor metadata for the audio-player hook's chapter window. The LV
  # dataset carries the same data but only advances over the WebSocket;
  # this HTTP copy is fetched alongside the next-chapter audio prefetch so
  # an offline/wedged-WS autoplay swap still knows its own neighbors.
  # Must stay in lockstep with ReaderLive's next/prev assigns — both go
  # through ChapterNeighbors.
  def nav(conn, %{"book_id" => book_id, "chapter_id" => chapter_id}) do
    book_id = String.to_integer(book_id)
    chapter_id = String.to_integer(chapter_id)
    chapters = ReadaloudLibrary.list_chapters(book_id)

    if Enum.any?(chapters, &(&1.id == chapter_id)) do
      json(conn, %{
        chapter_id: chapter_id,
        prev: neighbor_json(book_id, ChapterNeighbors.prev_with_audio(chapters, chapter_id)),
        next: neighbor_json(book_id, ChapterNeighbors.next_with_audio(chapters, chapter_id))
      })
    else
      send_resp(conn, 404, "No chapter")
    end
  end

  defp neighbor_json(_book_id, nil), do: nil

  defp neighbor_json(book_id, chapter) do
    %{
      chapter_id: chapter.id,
      title: ChapterNeighbors.display_title(chapter),
      audio_url: ~p"/api/books/#{book_id}/chapters/#{chapter.id}/audio",
      timings_url: ~p"/api/books/#{book_id}/chapters/#{chapter.id}/timings"
    }
  end

  def timings(conn, %{"chapter_id" => chapter_id}) do
    case ReadaloudAudiobook.get_chapter_audio(String.to_integer(chapter_id)) do
      nil ->
        json(conn, %{timings: []})

      audio ->
        json(conn, %{timings: ReadaloudAudiobook.ChapterAudio.decoded_timings(audio)})
    end
  end

  def listen_redirect(conn, %{"id" => id, "chapter_id" => chapter_id}) do
    conn
    |> put_status(301)
    |> redirect(to: ~p"/books/#{id}/read/#{chapter_id}")
  end

  def cover(conn, %{"book_id" => book_id}) do
    book = ReadaloudLibrary.get_book!(book_id)

    case book.cover_path do
      path when is_binary(path) and path != "" ->
        if File.exists?(path) do
          conn
          |> put_resp_content_type("image/jpeg")
          |> send_file(200, path)
        else
          send_resp(conn, 404, "Cover not found")
        end

      _ ->
        send_resp(conn, 404, "No cover")
    end
  end
end
