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
end
