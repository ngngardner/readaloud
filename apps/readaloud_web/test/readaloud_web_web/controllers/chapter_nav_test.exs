defmodule ReadaloudWebWeb.ChapterNavTest do
  use ReadaloudWebWeb.ConnCase, async: true

  alias ReadaloudAudiobook.ChapterAudio
  alias ReadaloudLibrary.Repo

  # The /nav endpoint exists so the audio-player hook can learn a chapter's
  # neighbors over plain HTTP at prefetch time — the LV dataset is the
  # primary source but only advances over the WS, and the 2026-06-11
  # incident showed the autoplay chain consuming a dataset frozen one
  # chapter behind after a WS death. The endpoint MUST mirror the LV's
  # next/prev-with-audio semantics exactly: a neighbor without audio is
  # null, not skipped over.

  setup do
    {:ok, book} = ReadaloudLibrary.create_book(%{title: "Nav Test", source_type: "epub"})
    {:ok, other_book} = ReadaloudLibrary.create_book(%{title: "Other", source_type: "epub"})

    {:ok, ch1} =
      ReadaloudLibrary.create_chapter(%{book_id: book.id, number: 1, title: "One"})

    {:ok, ch2} = ReadaloudLibrary.create_chapter(%{book_id: book.id, number: 2})
    {:ok, ch3} = ReadaloudLibrary.create_chapter(%{book_id: book.id, number: 3, title: "Three"})
    {:ok, other_ch} = ReadaloudLibrary.create_chapter(%{book_id: other_book.id, number: 1})

    for ch <- [ch1, ch2] do
      %ChapterAudio{}
      |> ChapterAudio.changeset(%{
        chapter_id: ch.id,
        audio_path: "/tmp/nav-test-#{ch.id}.wav",
        duration_seconds: 1.0
      })
      |> Repo.insert!()
    end

    %{book: book, ch1: ch1, ch2: ch2, ch3: ch3, other_book: other_book, other_ch: other_ch}
  end

  describe "GET /api/books/:book_id/chapters/:chapter_id/nav" do
    test "returns both neighbors with audio urls and titles", %{
      conn: conn,
      book: book,
      ch1: ch1,
      ch2: ch2
    } do
      conn = get(conn, ~p"/api/books/#{book.id}/chapters/#{ch2.id}/nav")
      body = json_response(conn, 200)

      assert body["chapter_id"] == ch2.id

      assert body["prev"] == %{
               "chapter_id" => ch1.id,
               "title" => "One",
               "audio_url" => "/api/books/#{book.id}/chapters/#{ch1.id}/audio",
               "timings_url" => "/api/books/#{book.id}/chapters/#{ch1.id}/timings"
             }

      # ch3 is adjacent but has no audio: null, NOT skipped to a farther
      # chapter — same rule as the LV's next_audio_chapter assign.
      assert body["next"] == nil
    end

    test "first chapter has null prev and an audio next", %{
      conn: conn,
      book: book,
      ch1: ch1,
      ch2: ch2
    } do
      conn = get(conn, ~p"/api/books/#{book.id}/chapters/#{ch1.id}/nav")
      body = json_response(conn, 200)

      assert body["prev"] == nil
      assert body["next"]["chapter_id"] == ch2.id
      # No title row → same fallback the LV template renders.
      assert body["next"]["title"] == "Chapter 2"
    end

    test "404 for a chapter that is not in the book", %{
      conn: conn,
      book: book,
      other_ch: other_ch
    } do
      conn = get(conn, ~p"/api/books/#{book.id}/chapters/#{other_ch.id}/nav")
      assert response(conn, 404)
    end

    test "404 for an unknown chapter id", %{conn: conn, book: book} do
      conn = get(conn, ~p"/api/books/#{book.id}/chapters/999999/nav")
      assert response(conn, 404)
    end
  end
end
