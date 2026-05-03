defmodule ReadaloudImporter.ImportTask do
  use Ecto.Schema
  import Ecto.Changeset

  alias ReadaloudLibrary.{SourceFormat, Tasks.Status}

  schema "import_tasks" do
    field(:file_path, :string)
    field(:file_type, Ecto.Enum, values: SourceFormat.values())
    field(:file_size, :integer)
    field(:status, Ecto.Enum, values: Status.values(), default: :pending)
    field(:error_message, :string)
    field(:book_id, :integer)
    timestamps()
  end

  def changeset(task, attrs) do
    task
    |> cast(attrs, [
      :file_path,
      :file_type,
      :file_size,
      :status,
      :error_message,
      :book_id
    ])
    |> validate_required([:file_path, :file_type])
  end
end
