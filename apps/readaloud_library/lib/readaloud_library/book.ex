defmodule ReadaloudLibrary.Book do
  use Ecto.Schema
  import Ecto.Changeset

  alias ReadaloudLibrary.{SourceFormat, TtsProfile}

  schema "books" do
    field(:title, :string)
    field(:author, :string)
    field(:cover_path, :string)
    field(:source_type, Ecto.Enum, values: SourceFormat.values())
    field(:total_chapters, :integer, default: 0)
    field(:audio_preferences, TtsProfile)
    has_many(:chapters, ReadaloudLibrary.Chapter)
    timestamps()
  end

  def changeset(book, attrs) do
    book
    |> cast(attrs, [
      :title,
      :author,
      :cover_path,
      :source_type,
      :total_chapters,
      :audio_preferences
    ])
    |> validate_required([:title, :source_type])
  end
end
