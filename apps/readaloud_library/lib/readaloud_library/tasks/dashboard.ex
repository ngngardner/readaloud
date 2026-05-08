defmodule ReadaloudLibrary.Tasks.Dashboard do
  @moduledoc """
  The `/tasks` page in one struct. `load/0` reads every task table the
  framework knows about, partitions tasks by lifecycle status, sorts each
  partition, and presents each task as a `Row` with the contextual fields the
  UI needs (book title, chapter number, relative time). All DB work happens
  here so the LiveView's only job is to assign the result and re-render.
  """

  alias ReadaloudLibrary.{Repo, Tasks}

  defmodule Row do
    @moduledoc """
    A single row in the tasks UI. Every field is computed at load time —
    rendering touches the DB only via the assigns it was given.
    """

    @enforce_keys [:task_id, :kind, :description]
    defstruct [
      :task_id,
      :kind,
      :description,
      :subtitle,
      :error_message,
      :relative_time,
      success?: false,
      failed?: false
    ]

    @type kind :: :audio | :import
    @type t :: %__MODULE__{
            task_id: integer,
            kind: kind,
            description: String.t(),
            subtitle: String.t() | nil,
            error_message: String.t() | nil,
            relative_time: String.t(),
            success?: boolean,
            failed?: boolean
          }
  end

  defstruct active: [], completed: []

  @type t :: %__MODULE__{
          active: [Row.t()],
          completed: [Row.t()]
        }

  @doc """
  Load and present every task in the system. `now` is latched once so every
  row's `relative_time` is computed against the same instant.
  """
  def load(now \\ NaiveDateTime.utc_now()) do
    tasks = Enum.flat_map(Tasks.schemas(), &Repo.all/1)
    {active, terminal} = Enum.split_with(tasks, &Tasks.active?/1)

    active = Enum.sort_by(active, & &1.inserted_at, {:asc, NaiveDateTime})
    terminal = Enum.sort_by(terminal, & &1.updated_at, {:desc, NaiveDateTime})

    ctx = build_ctx(tasks, now)

    %__MODULE__{
      active: Enum.map(active, &present(&1, ctx)),
      completed: Enum.map(terminal, &present(&1, ctx))
    }
  end

  # --- private ---

  defp build_ctx(tasks, now) do
    chapter_ids =
      for %{__struct__: ReadaloudAudiobook.AudiobookTask, chapter_id: id} <- tasks,
          is_integer(id),
          do: id

    book_ids = for t <- tasks, is_integer(t.book_id), do: t.book_id

    %{
      chapter_numbers: ReadaloudLibrary.chapter_numbers_by_ids(chapter_ids),
      book_titles: ReadaloudLibrary.book_titles_by_ids(book_ids),
      now: now
    }
  end

  defp present(%{__struct__: ReadaloudAudiobook.AudiobookTask} = task, ctx) do
    description =
      case Map.get(ctx.chapter_numbers, task.chapter_id) do
        nil -> "Generating audio"
        n -> "Generating audio — Ch #{n}"
      end

    row(task, :audio, description, ctx)
  end

  defp present(%{__struct__: ReadaloudImporter.ImportTask} = task, ctx) do
    row(task, :import, "Importing #{Path.basename(task.file_path)}", ctx)
  end

  defp row(task, kind, description, ctx) do
    %Row{
      task_id: task.id,
      kind: kind,
      description: description,
      subtitle: Map.get(ctx.book_titles, task.book_id),
      error_message: task.error_message,
      success?: Tasks.completed?(task),
      failed?: Tasks.failed?(task),
      relative_time: relative_time(task.updated_at, ctx.now)
    }
  end

  defp relative_time(nil, _now), do: ""

  defp relative_time(dt, now) do
    diff = NaiveDateTime.diff(now, dt, :second)

    cond do
      diff < 60 -> "#{diff}s ago"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86_400 -> "#{div(diff, 3600)}h ago"
      true -> "#{div(diff, 86_400)}d ago"
    end
  end
end
