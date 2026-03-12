defmodule ReadaloudReaderTest do
  use ExUnit.Case, async: false

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(ReadaloudLibrary.Repo)
    {:ok, book} = ReadaloudLibrary.create_book(%{title: "Test", source_type: "epub"})
    {:ok, chapter} = ReadaloudLibrary.create_chapter(%{book_id: book.id, number: 1})
    %{book: book, chapter: chapter}
  end

  describe "upsert_progress/1" do
    test "creates progress for new book", %{book: book, chapter: chapter} do
      attrs = %{book_id: book.id, current_chapter_id: chapter.id, scroll_position: 0.5}
      assert {:ok, progress} = ReadaloudReader.upsert_progress(attrs)
      assert progress.scroll_position == 0.5
    end

    test "updates existing progress", %{book: book, chapter: chapter} do
      attrs = %{book_id: book.id, current_chapter_id: chapter.id, scroll_position: 0.2}
      {:ok, _} = ReadaloudReader.upsert_progress(attrs)
      updated = %{book_id: book.id, current_chapter_id: chapter.id, scroll_position: 0.8}
      {:ok, progress} = ReadaloudReader.upsert_progress(updated)
      assert progress.scroll_position == 0.8
    end
  end

  describe "get_progress/1" do
    test "returns nil when no progress", %{book: book} do
      assert ReadaloudReader.get_progress(book.id) == nil
    end

    test "returns saved progress", %{book: book, chapter: chapter} do
      attrs = %{book_id: book.id, current_chapter_id: chapter.id, audio_position_ms: 5000}
      {:ok, _} = ReadaloudReader.upsert_progress(attrs)
      progress = ReadaloudReader.get_progress(book.id)
      assert progress.audio_position_ms == 5000
    end
  end
end
