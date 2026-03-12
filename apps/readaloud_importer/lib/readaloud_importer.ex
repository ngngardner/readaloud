defmodule ReadaloudImporter do
  alias ReadaloudLibrary.Repo
  alias ReadaloudImporter.{ImportTask, ParseJob}
  import Ecto.Query

  def import_file(file_path, file_type) do
    file_size =
      case File.stat(file_path) do
        {:ok, %{size: size}} -> size
        _ -> nil
      end

    attrs = %{file_path: file_path, file_type: file_type, file_size: file_size}

    case %ImportTask{} |> ImportTask.changeset(attrs) |> Repo.insert() do
      {:ok, task} ->
        %{task_id: task.id} |> ParseJob.new() |> Oban.insert()
        {:ok, task}

      error ->
        error
    end
  end

  def list_tasks do
    ImportTask |> order_by(desc: :inserted_at) |> Repo.all()
  end

  def get_task(id), do: Repo.get(ImportTask, id)

  def clear_completed_tasks do
    from(t in ImportTask, where: t.status in ["completed", "failed"])
    |> Repo.delete_all()
  end
end
