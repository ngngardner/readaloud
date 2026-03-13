defmodule ReadaloudAudiobook.AudiobookTask do
  use Ecto.Schema
  import Ecto.Changeset

  schema "audiobook_tasks" do
    field(:book_id, :integer)
    field(:chapter_id, :integer)
    field(:scope, :string, default: "chapter")
    field(:voice, :string)
    field(:speed, :float, default: 1.0)
    field(:model, :string)
    field(:status, :string, default: "pending")
    field(:progress, :float, default: 0.0)
    field(:error_message, :string)
    field(:attempt_number, :integer, default: 1)
    timestamps()
  end

  def changeset(task, attrs) do
    task
    |> cast(attrs, [
      :book_id,
      :chapter_id,
      :scope,
      :voice,
      :speed,
      :model,
      :status,
      :progress,
      :error_message,
      :attempt_number
    ])
    |> validate_required([:book_id, :scope])
    |> validate_inclusion(:scope, ["chapter", "book"])
    |> validate_inclusion(:status, ["pending", "processing", "completed", "failed"])
  end
end
