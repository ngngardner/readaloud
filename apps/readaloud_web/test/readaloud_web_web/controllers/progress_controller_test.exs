defmodule ReadaloudWebWeb.ProgressControllerTest do
  use ReadaloudWebWeb.ConnCase, async: true

  setup do
    {:ok, book} = ReadaloudLibrary.create_book(%{title: "Beacon Test", source_type: "epub"})
    {:ok, ch1} = ReadaloudLibrary.create_chapter(%{book_id: book.id, number: 1})
    {:ok, ch2} = ReadaloudLibrary.create_chapter(%{book_id: book.id, number: 2})
    %{book: book, ch1: ch1, ch2: ch2}
  end

  describe "POST /api/books/:book_id/progress" do
    test "applies a single observation", %{conn: conn, book: book, ch1: ch1} do
      payload = %{
        "observations" => [
          %{
            "chapter_id" => ch1.id,
            "audio_position_ms" => 12_400,
            "observed_at" => "2026-05-08T10:00:00Z"
          }
        ]
      }

      conn = post(conn, ~p"/api/books/#{book.id}/progress", payload)
      assert response(conn, 204)

      progress = ReadaloudReader.get_progress(book.id)
      assert progress.current_chapter_id == ch1.id
      assert progress.audio_position_ms == 12_400
    end

    test "applies a batch ordered by observed_at, latest wins for same chapter",
         %{conn: conn, book: book, ch1: ch1} do
      payload = %{
        "observations" => [
          # Out-of-order on purpose: server must sort.
          %{
            "chapter_id" => ch1.id,
            "audio_position_ms" => 9_000,
            "observed_at" => "2026-05-08T10:00:10Z"
          },
          %{
            "chapter_id" => ch1.id,
            "audio_position_ms" => 3_000,
            "observed_at" => "2026-05-08T10:00:00Z"
          },
          %{
            "chapter_id" => ch1.id,
            "audio_position_ms" => 6_000,
            "observed_at" => "2026-05-08T10:00:05Z"
          }
        ]
      }

      conn = post(conn, ~p"/api/books/#{book.id}/progress", payload)
      assert response(conn, 204)

      progress = ReadaloudReader.get_progress(book.id)
      assert progress.audio_position_ms == 9_000
    end

    test "drops malformed observations and applies the rest",
         %{conn: conn, book: book, ch1: ch1} do
      payload = %{
        "observations" => [
          %{"chapter_id" => "not-an-int", "observed_at" => "2026-05-08T10:00:00Z"},
          %{
            "chapter_id" => ch1.id,
            "audio_position_ms" => 4_200,
            "observed_at" => "2026-05-08T10:00:01Z"
          }
        ]
      }

      conn = post(conn, ~p"/api/books/#{book.id}/progress", payload)
      assert response(conn, 204)

      progress = ReadaloudReader.get_progress(book.id)
      assert progress.audio_position_ms == 4_200
    end

    test "rejects payloads above the per-request observation cap", %{conn: conn, book: book} do
      observations =
        for n <- 1..201 do
          %{"chapter_id" => 1, "observed_at" => "2026-05-08T10:00:00Z", "audio_position_ms" => n}
        end

      conn = post(conn, ~p"/api/books/#{book.id}/progress", %{"observations" => observations})
      assert json_response(conn, 413) == %{"error" => "too_many_observations"}
    end
  end
end
