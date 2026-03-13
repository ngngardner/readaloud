defmodule ReadaloudLibrary.BookTest do
  use ExUnit.Case, async: true

  alias ReadaloudLibrary.Book

  describe "changeset/2" do
    test "accepts audio_preferences as a map" do
      attrs = %{
        title: "Test Book",
        source_type: "epub",
        audio_preferences: %{"model" => "kokoro", "voice" => "af_heart"}
      }

      changeset = Book.changeset(%Book{}, attrs)
      assert changeset.valid?

      assert Ecto.Changeset.get_change(changeset, :audio_preferences) == %{
               "model" => "kokoro",
               "voice" => "af_heart"
             }
    end

    test "audio_preferences defaults to nil" do
      attrs = %{title: "Test Book", source_type: "epub"}
      changeset = Book.changeset(%Book{}, attrs)
      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :audio_preferences) == nil
    end
  end
end
