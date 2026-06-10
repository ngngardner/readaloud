defmodule ReadaloudWebWeb.ReaderLiveTest do
  # async: false — the LV process needs shared-sandbox DB access.
  use ReadaloudWebWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  defp attach(events) do
    ref = :telemetry_test.attach_event_handlers(self(), events)
    on_exit(fn -> :telemetry.detach(ref) end)
    ref
  end

  setup %{conn: conn} do
    {:ok, book} = ReadaloudLibrary.create_book(%{title: "Reader", source_type: "epub"})
    {:ok, ch1} = ReadaloudLibrary.create_chapter(chapter_attrs(book, 1))
    {:ok, ch2} = ReadaloudLibrary.create_chapter(chapter_attrs(book, 2))
    %{conn: conn, book: book, ch1: ch1, ch2: ch2}
  end

  defp chapter_attrs(book, number) do
    path =
      Path.join(
        System.tmp_dir!(),
        "reader_live_ch#{number}_#{System.unique_integer([:positive])}.html"
      )

    File.write!(path, "<p>Chapter #{number} text</p>")
    %{book_id: book.id, number: number, content_path: path}
  end

  describe "player_events" do
    test "hook events are ingested with ws transport", %{conn: conn, book: book, ch1: ch1} do
      ref = attach([[:readaloud, :player, :event]])
      {:ok, view, _html} = live(conn, ~p"/books/#{book.id}/read/#{ch1.id}")

      render_hook(view, "player_events", %{
        "events" => [%{"event" => "visibility-hidden", "at" => "2026-06-10T01:00:00Z"}]
      })

      assert_received {[:readaloud, :player, :event], ^ref, %{count: 1},
                       %{event: "visibility-hidden", transport: "ws"}}
    end
  end

  describe "progress_observations" do
    test "flush telemetry carries received/dropped counts", %{
      conn: conn,
      book: book,
      ch1: ch1
    } do
      ref = attach([[:readaloud, :progress, :flush]])
      {:ok, view, _html} = live(conn, ~p"/books/#{book.id}/read/#{ch1.id}")

      render_hook(view, "progress_observations", %{
        "observations" => [
          %{
            "chapter_id" => ch1.id,
            "audio_position_ms" => 5000,
            "observed_at" => "2026-06-10T01:00:00Z"
          },
          %{"chapter_id" => "bogus", "observed_at" => "2026-06-10T01:00:01Z"}
        ]
      })

      assert_received {[:readaloud, :progress, :flush], ^ref, %{count: 2, dropped: 1},
                       %{transport: "ws"}}
    end
  end

  describe "chapter_advance telemetry" do
    test "client-owned advance counts as client_owned", %{conn: conn, book: book, ch1: ch1} do
      ref = attach([[:readaloud, :reader, :chapter_advance]])
      {:ok, view, _html} = live(conn, ~p"/books/#{book.id}/read/#{ch1.id}")

      render_hook(view, "next_chapter", %{"client_owned" => true})

      assert_received {[:readaloud, :reader, :chapter_advance], ^ref, %{count: 1},
                       %{direction: "next", mode: "client_owned"}}
    end

    test "server-driven advance counts as server_patch", %{conn: conn, book: book, ch1: ch1} do
      ref = attach([[:readaloud, :reader, :chapter_advance]])
      {:ok, view, _html} = live(conn, ~p"/books/#{book.id}/read/#{ch1.id}")

      render_hook(view, "next_chapter", %{})

      assert_received {[:readaloud, :reader, :chapter_advance], ^ref, %{count: 1},
                       %{direction: "next", mode: "server_patch"}}
    end

    test "advance past the last chapter counts as noop", %{conn: conn, book: book, ch2: ch2} do
      ref = attach([[:readaloud, :reader, :chapter_advance]])
      {:ok, view, _html} = live(conn, ~p"/books/#{book.id}/read/#{ch2.id}")

      render_hook(view, "next_chapter", %{})

      assert_received {[:readaloud, :reader, :chapter_advance], ^ref, %{count: 1},
                       %{direction: "next", mode: "noop"}}
    end

    test "prev from the first chapter counts as noop", %{conn: conn, book: book, ch1: ch1} do
      ref = attach([[:readaloud, :reader, :chapter_advance]])
      {:ok, view, _html} = live(conn, ~p"/books/#{book.id}/read/#{ch1.id}")

      render_hook(view, "prev_chapter", %{})

      assert_received {[:readaloud, :reader, :chapter_advance], ^ref, %{count: 1},
                       %{direction: "prev", mode: "noop"}}
    end
  end
end
