defmodule ReadaloudReaderTest do
  use ExUnit.Case, async: false

  alias ReadaloudReader.Progress.Observation

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(ReadaloudLibrary.Repo)
    {:ok, book} = ReadaloudLibrary.create_book(%{title: "Test", source_type: "epub"})
    {:ok, chapter1} = ReadaloudLibrary.create_chapter(%{book_id: book.id, number: 1})
    {:ok, chapter2} = ReadaloudLibrary.create_chapter(%{book_id: book.id, number: 2})
    %{book: book, chapter1: chapter1, chapter2: chapter2}
  end

  describe "observe!/1 — first observation" do
    test "creates a new row with the observation's fields", %{book: book, chapter1: ch} do
      now = DateTime.utc_now()

      progress =
        ReadaloudReader.observe!(%Observation{
          book_id: book.id,
          chapter_id: ch.id,
          audio_position_ms: 12_400,
          scroll_position: 0.42,
          observed_at: now
        })

      assert progress.book_id == book.id
      assert progress.current_chapter_id == ch.id
      assert progress.audio_position_ms == 12_400
      assert progress.scroll_position == 0.42
      assert DateTime.compare(progress.last_observed_at, DateTime.truncate(now, :second)) == :eq
    end

    test "nil dimensions persist as defaults", %{book: book, chapter1: ch} do
      progress =
        ReadaloudReader.observe!(%Observation{
          book_id: book.id,
          chapter_id: ch.id,
          observed_at: DateTime.utc_now()
        })

      assert progress.audio_position_ms == 0
      assert progress.scroll_position == 0.0
    end
  end

  describe "observe!/1 — same chapter, advancing observed_at" do
    test "updates audio_position_ms when newer", %{book: book, chapter1: ch} do
      t0 = ~U[2026-05-08T10:00:00Z]
      t1 = ~U[2026-05-08T10:00:05Z]

      ReadaloudReader.observe!(%Observation{
        book_id: book.id,
        chapter_id: ch.id,
        audio_position_ms: 1000,
        observed_at: t0
      })

      progress =
        ReadaloudReader.observe!(%Observation{
          book_id: book.id,
          chapter_id: ch.id,
          audio_position_ms: 6000,
          observed_at: t1
        })

      assert progress.audio_position_ms == 6000
    end

    test "preserves stored audio_position_ms when observation has nil for it", %{
      book: book,
      chapter1: ch
    } do
      t0 = ~U[2026-05-08T10:00:00Z]
      t1 = ~U[2026-05-08T10:00:01Z]

      ReadaloudReader.observe!(%Observation{
        book_id: book.id,
        chapter_id: ch.id,
        audio_position_ms: 5000,
        observed_at: t0
      })

      progress =
        ReadaloudReader.observe!(%Observation{
          book_id: book.id,
          chapter_id: ch.id,
          scroll_position: 0.7,
          observed_at: t1
        })

      assert progress.audio_position_ms == 5000
      assert progress.scroll_position == 0.7
    end
  end

  describe "observe!/1 — stale-drop" do
    test "drops same-chapter observation with older observed_at", %{book: book, chapter1: ch} do
      newer = ~U[2026-05-08T10:00:10Z]
      older = ~U[2026-05-08T10:00:05Z]

      ReadaloudReader.observe!(%Observation{
        book_id: book.id,
        chapter_id: ch.id,
        audio_position_ms: 12_000,
        observed_at: newer
      })

      progress =
        ReadaloudReader.observe!(%Observation{
          book_id: book.id,
          chapter_id: ch.id,
          audio_position_ms: 7_000,
          observed_at: older
        })

      assert progress.audio_position_ms == 12_000,
             "stale observation must not roll position backwards"
    end

    test "drops same-chapter observation with equal observed_at (idempotent replay)",
         %{book: book, chapter1: ch} do
      t = ~U[2026-05-08T10:00:00Z]

      ReadaloudReader.observe!(%Observation{
        book_id: book.id,
        chapter_id: ch.id,
        audio_position_ms: 5_000,
        observed_at: t
      })

      # Replay of the same observation (e.g. WS push + beacon flush)
      progress =
        ReadaloudReader.observe!(%Observation{
          book_id: book.id,
          chapter_id: ch.id,
          audio_position_ms: 5_000,
          observed_at: t
        })

      assert progress.audio_position_ms == 5_000
    end
  end

  describe "observe!/1 — cross-chapter" do
    test "always pivots, even with older observed_at", %{
      book: book,
      chapter1: ch1,
      chapter2: ch2
    } do
      newer = ~U[2026-05-08T10:00:10Z]
      older = ~U[2026-05-08T10:00:05Z]

      ReadaloudReader.observe!(%Observation{
        book_id: book.id,
        chapter_id: ch1.id,
        audio_position_ms: 12_000,
        observed_at: newer
      })

      progress =
        ReadaloudReader.observe!(%Observation{
          book_id: book.id,
          chapter_id: ch2.id,
          observed_at: older
        })

      assert progress.current_chapter_id == ch2.id
    end

    test "resets audio_position_ms to 0 on cross-chapter when observation omits it", %{
      book: book,
      chapter1: ch1,
      chapter2: ch2
    } do
      ReadaloudReader.observe!(%Observation{
        book_id: book.id,
        chapter_id: ch1.id,
        audio_position_ms: 12_000,
        observed_at: ~U[2026-05-08T10:00:00Z]
      })

      progress =
        ReadaloudReader.observe!(%Observation{
          book_id: book.id,
          chapter_id: ch2.id,
          observed_at: ~U[2026-05-08T10:00:01Z]
        })

      assert progress.audio_position_ms == 0
    end
  end

  describe "Observation.from_map/2" do
    test "accepts string-keyed map with integer book_id and string chapter_id" do
      now = ~U[2026-05-08T10:00:00Z]

      assert {:ok, obs} =
               Observation.from_map(
                 %{
                   "book_id" => 3,
                   "chapter_id" => "29",
                   "audio_position_ms" => 12_400,
                   "observed_at" => "2026-05-08T09:59:55Z"
                 },
                 now
               )

      assert obs.book_id == 3
      assert obs.chapter_id == 29
      assert obs.audio_position_ms == 12_400
    end

    test "clamps observed_at outside the [-7d, +5min] window" do
      now = ~U[2026-05-08T10:00:00Z]

      # 6 minutes in the future → clamped to now
      assert {:ok, obs} =
               Observation.from_map(
                 %{
                   "book_id" => 1,
                   "chapter_id" => 1,
                   "observed_at" => "2026-05-08T10:06:00Z"
                 },
                 now
               )

      assert obs.observed_at == DateTime.truncate(now, :second)
    end
  end

  describe "get_progress/1" do
    test "returns nil when no progress", %{book: book} do
      assert ReadaloudReader.get_progress(book.id) == nil
    end

    test "returns saved progress", %{book: book, chapter1: ch} do
      ReadaloudReader.observe!(%Observation{
        book_id: book.id,
        chapter_id: ch.id,
        audio_position_ms: 5000,
        observed_at: DateTime.utc_now()
      })

      progress = ReadaloudReader.get_progress(book.id)
      assert progress.audio_position_ms == 5000
    end
  end
end
