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

    # Level-triggered convergence: when the client navigated chapters but
    # the nav event was lost in a wedged socket, the pivot observation
    # (which always eventually arrives — WS or buffered replay after
    # reconnect) must pull the rendered chapter along.
    test "reconciles assigns on a pivot observation for another chapter", %{
      conn: conn,
      book: book,
      ch1: ch1,
      ch2: ch2
    } do
      ref = attach([[:readaloud, :reader, :chapter_advance]])
      {:ok, view, html} = live(conn, ~p"/books/#{book.id}/read/#{ch1.id}")
      assert html =~ "Chapter 1 text"

      html =
        render_hook(view, "progress_observations", %{
          "observations" => [
            %{
              "chapter_id" => ch2.id,
              "audio_position_ms" => 0,
              "observed_at" => "2026-06-10T01:00:00Z",
              "pivot" => true
            }
          ]
        })

      assert html =~ "Chapter 2 text"

      assert_received {[:readaloud, :reader, :chapter_advance], ^ref, %{count: 1},
                       %{direction: "next", mode: "reconcile"}}
    end

    # A position tick (no pivot flag) for another chapter must NOT
    # reconcile: ticks for the old chapter are legitimately in flight
    # during a server-owned jump, and reconciling on them drags the
    # rendered chapter back.
    test "position ticks never reconcile, even cross-chapter", %{
      conn: conn,
      book: book,
      ch1: ch1,
      ch2: ch2
    } do
      ref = attach([[:readaloud, :reader, :chapter_advance]])
      {:ok, view, _html} = live(conn, ~p"/books/#{book.id}/read/#{ch1.id}")

      html =
        render_hook(view, "progress_observations", %{
          "observations" => [
            %{
              "chapter_id" => ch2.id,
              "audio_position_ms" => 5000,
              "observed_at" => "2026-06-10T01:00:00Z"
            }
          ]
        })

      assert html =~ "Chapter 1 text"
      refute_received {[:readaloud, :reader, :chapter_advance], ^ref, _, _}
    end

    test "does not reconcile to a chapter outside the book", %{
      conn: conn,
      book: book,
      ch1: ch1
    } do
      {:ok, other_book} = ReadaloudLibrary.create_book(%{title: "Other", source_type: "epub"})
      {:ok, foreign_ch} = ReadaloudLibrary.create_chapter(chapter_attrs(other_book, 1))

      ref = attach([[:readaloud, :reader, :chapter_advance]])
      {:ok, view, _html} = live(conn, ~p"/books/#{book.id}/read/#{ch1.id}")

      html =
        render_hook(view, "progress_observations", %{
          "observations" => [
            %{
              "chapter_id" => foreign_ch.id,
              "audio_position_ms" => 0,
              "observed_at" => "2026-06-10T01:00:00Z",
              "pivot" => true
            }
          ]
        })

      assert html =~ "Chapter 1 text"
      refute_received {[:readaloud, :reader, :chapter_advance], ^ref, _, _}
    end

    # The double-advance race: pivot observation arrives first (reconciler
    # moves assigns to ch2), then the nav event lands. With an absolute
    # chapter_id the event is idempotent; a relative "next from current"
    # would double-step to ch3 (or past the end).
    test "client-owned nav after reconcile is idempotent, not relative", %{
      conn: conn,
      book: book,
      ch1: ch1,
      ch2: ch2
    } do
      ref = attach([[:readaloud, :reader, :chapter_advance]])
      {:ok, view, _html} = live(conn, ~p"/books/#{book.id}/read/#{ch1.id}")

      render_hook(view, "progress_observations", %{
        "observations" => [
          %{
            "chapter_id" => ch2.id,
            "audio_position_ms" => 0,
            "observed_at" => "2026-06-10T01:00:00Z",
            "pivot" => true
          }
        ]
      })

      assert_received {[:readaloud, :reader, :chapter_advance], ^ref, %{count: 1},
                       %{direction: "next", mode: "reconcile"}}

      html =
        render_hook(view, "next_chapter", %{
          "client_owned" => true,
          "chapter_id" => to_string(ch2.id)
        })

      # Still chapter 2 — the event was already applied via the pivot.
      assert html =~ "Chapter 2 text"
      refute_received {[:readaloud, :reader, :chapter_advance], ^ref, _, _}
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
