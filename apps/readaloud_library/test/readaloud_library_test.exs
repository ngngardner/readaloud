defmodule ReadaloudLibraryTest do
  use ExUnit.Case, async: false

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(ReadaloudLibrary.Repo)
  end

  describe "create_book/1" do
    test "creates a book with valid attrs" do
      attrs = %{title: "Dune", author: "Frank Herbert", source_type: "epub"}
      assert {:ok, book} = ReadaloudLibrary.create_book(attrs)
      assert book.title == "Dune"
      assert book.author == "Frank Herbert"
      assert book.source_type == "epub"
      assert book.total_chapters == 0
    end

    test "fails without title" do
      assert {:error, changeset} = ReadaloudLibrary.create_book(%{author: "X"})
      assert %{title: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "list_books/0" do
    test "returns all books" do
      {:ok, _} = ReadaloudLibrary.create_book(%{title: "A", source_type: "epub"})
      {:ok, _} = ReadaloudLibrary.create_book(%{title: "B", source_type: "pdf"})
      assert length(ReadaloudLibrary.list_books()) == 2
    end
  end

  describe "get_book/1" do
    test "returns book by id" do
      {:ok, book} = ReadaloudLibrary.create_book(%{title: "A", source_type: "epub"})
      assert ReadaloudLibrary.get_book(book.id).title == "A"
    end

    test "returns nil for missing id" do
      assert ReadaloudLibrary.get_book(-1) == nil
    end
  end

  describe "delete_book/1" do
    test "deletes the book" do
      {:ok, book} = ReadaloudLibrary.create_book(%{title: "A", source_type: "epub"})
      assert {:ok, _} = ReadaloudLibrary.delete_book(book)
      assert ReadaloudLibrary.get_book(book.id) == nil
    end
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
  end
end
