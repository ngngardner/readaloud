defmodule ReadaloudImporter.ImportTask do
  use Ecto.Schema
  import Ecto.Changeset

  schema "import_tasks" do
    field :file_path, :string
    field :file_type, :string
    field :file_size, :integer
    field :status, :string, default: "pending"
    field :progress, :float, default: 0.0
    field :error_message, :string
    field :book_id, :integer
    timestamps()
  end

  def changeset(task, attrs) do
    task
    |> cast(attrs, [:file_path, :file_type, :file_size, :status, :progress, :error_message, :book_id])
    |> validate_required([:file_path, :file_type])
    |> validate_inclusion(:file_type, ["epub", "pdf"])
    |> validate_inclusion(:status, ["pending", "processing", "completed", "failed"])
  end
end
