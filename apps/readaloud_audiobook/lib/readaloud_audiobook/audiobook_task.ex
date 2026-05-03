defmodule ReadaloudAudiobook.AudiobookTask do
  use Ecto.Schema
  import Ecto.Changeset

  alias ReadaloudLibrary.Tasks.Status

  schema "audiobook_tasks" do
    field(:book_id, :integer)
    field(:chapter_id, :integer)
    field(:voice, :string)
    field(:speed, :float, default: 1.0)
    field(:model, :string)
    field(:status, Ecto.Enum, values: Status.values(), default: :pending)
    field(:error_message, :string)
    field(:attempt_number, :integer, default: 1)
    timestamps()
  end

  def changeset(task, attrs) do
    task
    |> cast(attrs, [
      :book_id,
      :chapter_id,
      :voice,
      :speed,
      :model,
      :status,
      :error_message,
      :attempt_number
    ])
    |> validate_required([:book_id])
  end
end
