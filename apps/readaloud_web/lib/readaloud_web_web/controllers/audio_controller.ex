defmodule ReadaloudWebWeb.AudioController do
  use ReadaloudWebWeb, :controller

  def stream(conn, %{"chapter_id" => chapter_id}) do
    case ReadaloudAudiobook.get_chapter_audio(String.to_integer(chapter_id)) do
      nil ->
        send_resp(conn, 404, "No audio")

      audio ->
        conn
        |> put_resp_content_type("audio/wav")
        |> send_file(200, audio.audio_path)
    end
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
