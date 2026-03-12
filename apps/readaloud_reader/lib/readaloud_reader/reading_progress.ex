defmodule ReadaloudReader.ReadingProgress do
  use Ecto.Schema
  import Ecto.Changeset

  schema "reading_progress" do
    field :book_id, :integer
    field :current_chapter_id, :integer
    field :scroll_position, :float, default: 0.0
    field :audio_position_ms, :integer, default: 0
    field :last_read_at, :utc_datetime
    timestamps()
  end

  def changeset(progress, attrs) do
    progress
    |> cast(attrs, [:book_id, :current_chapter_id, :scroll_position, :audio_position_ms, :last_read_at])
    |> validate_required([:book_id])
    |> unique_constraint(:book_id)
    |> put_change(:last_read_at, DateTime.utc_now() |> DateTime.truncate(:second))
  end
end
