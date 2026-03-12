defmodule ReadaloudLibrary.Chapter do
  use Ecto.Schema
  import Ecto.Changeset

  schema "chapters" do
    field :title, :string
    field :number, :integer
    field :volume, :integer
    field :content_path, :string
    field :word_count, :integer, default: 0
    belongs_to :book, ReadaloudLibrary.Book
    timestamps()
  end

  def changeset(chapter, attrs) do
    chapter
    |> cast(attrs, [:title, :number, :volume, :content_path, :word_count, :book_id])
    |> validate_required([:number, :book_id])
    |> unique_constraint([:book_id, :number])
    |> foreign_key_constraint(:book_id)
  end
end
