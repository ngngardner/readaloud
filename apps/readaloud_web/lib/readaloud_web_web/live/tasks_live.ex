defmodule ReadaloudWebWeb.TasksLive do
  use ReadaloudWebWeb, :live_view

  import Ecto.Query

  alias ReadaloudLibrary.Tasks

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(ReadaloudWeb.PubSub, "tasks:import")
      Phoenix.PubSub.subscribe(ReadaloudWeb.PubSub, "tasks:audiobook")
    end

    {active, completed} = load_split_rows()

    {:ok,
     socket
     |> assign(
       page_title: "Tasks",
       active_nav: :tasks,
       task_count: length(active),
       active_rows: active,
       completed_rows: completed
     )}
  end

  @impl true
  def handle_event("cancel_task", %{"task-id" => task_id_str}, socket) do
    task_id = String.to_integer(task_id_str)

    query =
      from(j in Oban.Job,
        where:
          j.state in ["available", "scheduled", "executing", "retryable"] and
            fragment("?->>'task_id' = ?", j.args, ^to_string(task_id))
      )

    Enum.each(ReadaloudLibrary.Repo.all(query), fn job ->
      Oban.cancel_job(job.id)
    end)

    if task = lookup_task(task_id), do: Tasks.fail(task, "Cancelled by user")

    {:noreply, reload_rows(socket)}
  end

  @impl true
  def handle_event("retry_task", %{"task-id" => task_id_str}, socket) do
    task_id = String.to_integer(task_id_str)

    case lookup_task(task_id) do
      %ReadaloudAudiobook.AudiobookTask{} = task ->
        ReadaloudAudiobook.generate_for_chapter(task.book_id, task.chapter_id,
          model: task.model,
          voice: task.voice
        )

      %ReadaloudImporter.ImportTask{} = task ->
        ReadaloudImporter.import_file(task.file_path, task.file_type)

      nil ->
        :ok
    end

    {:noreply, reload_rows(socket)}
  end

  @impl true
  def handle_event("clear_completed", _params, socket) do
    ReadaloudAudiobook.clear_completed_tasks()
    ReadaloudImporter.clear_completed_tasks()
    {:noreply, reload_rows(socket)}
  end

  @impl true
  def handle_info(_, socket) do
    {:noreply, reload_rows(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto p-6">
      <h1 class="text-3xl font-bold mb-8">Tasks</h1>

      <%!-- Active Tasks Section --%>
      <div class="mb-8">
        <div class="flex items-center gap-3 mb-4">
          <h2 class="text-xl font-semibold">Active</h2>
          <span :if={@active_rows != []} class="badge badge-warning badge-sm">
            {length(@active_rows)}
          </span>
        </div>

        <div :if={@active_rows == []} class="text-base-content/50 py-6 text-center">
          No active tasks
        </div>

        <div class="space-y-3">
          <div
            :for={row <- @active_rows}
            class="card bg-base-200 p-4"
          >
            <div class="flex items-center gap-3">
              <.icon name="hero-arrow-path" class="size-5 text-warning animate-spin shrink-0" />
              <div class="flex-1 min-w-0">
                <div class="flex items-center gap-2 mb-1">
                  <span class="font-medium truncate">{row.description}</span>
                  <span class="badge badge-xs badge-ghost shrink-0">{row.kind}</span>
                </div>
                <div :if={row.subtitle} class="text-xs text-base-content/50 truncate">
                  {row.subtitle}
                </div>
              </div>
              <button
                phx-click="cancel_task"
                phx-value-task-id={row.task_id}
                class="btn btn-xs btn-ghost text-error shrink-0"
                title="Cancel"
              >
                <.icon name="hero-x-mark" class="size-4" />
              </button>
            </div>
          </div>
        </div>
      </div>

      <%!-- Completed/Failed Section --%>
      <div>
        <div class="flex items-center justify-between mb-4">
          <div class="flex items-center gap-3">
            <h2 class="text-xl font-semibold">Completed</h2>
            <span :if={@completed_rows != []} class="badge badge-ghost badge-sm">
              {length(@completed_rows)}
            </span>
          </div>
          <button
            :if={@completed_rows != []}
            phx-click="clear_completed"
            class="btn btn-xs btn-ghost text-base-content/60"
          >
            Clear Completed
          </button>
        </div>

        <div :if={@completed_rows == []} class="text-base-content/50 py-6 text-center">
          No completed tasks
        </div>

        <div class="space-y-1">
          <div
            :for={row <- @completed_rows}
            class="flex items-center gap-3 p-3 rounded-lg hover:bg-base-200 transition-colors"
          >
            <.icon
              :if={row.success?}
              name="hero-check-circle"
              class="size-5 text-success shrink-0"
            />
            <.icon
              :if={not row.success?}
              name="hero-exclamation-circle"
              class="size-5 text-error shrink-0"
            />
            <div class="flex-1 min-w-0">
              <div class="flex items-center gap-2">
                <span class="text-sm truncate">{row.description}</span>
                <span class="badge badge-xs badge-ghost shrink-0">{row.kind}</span>
              </div>
              <div :if={row.subtitle} class="text-xs text-base-content/50 truncate">
                {row.subtitle}
              </div>
              <div :if={row.error_message} class="text-xs text-error truncate">
                {row.error_message}
              </div>
            </div>
            <span class="text-xs text-base-content/40 shrink-0">{row.relative_time}</span>
            <button
              :if={row.failed?}
              phx-click="retry_task"
              phx-value-task-id={row.task_id}
              class="text-xs text-primary hover:underline shrink-0"
            >
              Retry
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # --- Private helpers ---

  defp reload_rows(socket) do
    {active, completed} = load_split_rows()

    socket
    |> assign(
      task_count: length(active),
      active_rows: active,
      completed_rows: completed
    )
  end

  defp load_split_rows do
    tasks = ReadaloudAudiobook.list_tasks() ++ ReadaloudImporter.list_tasks()

    chapter_ids =
      for %ReadaloudAudiobook.AudiobookTask{chapter_id: id} <- tasks, is_integer(id), do: id

    book_ids = for t <- tasks, is_integer(t.book_id), do: t.book_id

    ctx = %{
      chapter_numbers: ReadaloudLibrary.chapter_numbers_by_ids(chapter_ids),
      book_titles: ReadaloudLibrary.book_titles_by_ids(book_ids),
      now: NaiveDateTime.utc_now()
    }

    rows = Enum.map(tasks, &present_row(&1, ctx))
    split_rows(rows)
  end

  defp split_rows(rows) do
    {active_rows, terminal_rows} = Enum.split_with(rows, &(&1.state == :active))

    {
      Enum.sort_by(active_rows, & &1.inserted_at, {:asc, NaiveDateTime}),
      Enum.sort_by(terminal_rows, & &1.updated_at, {:desc, NaiveDateTime})
    }
  end

  defp lookup_task(task_id) do
    ReadaloudAudiobook.get_task(task_id) || ReadaloudImporter.get_task(task_id)
  end

  defp present_row(%ReadaloudAudiobook.AudiobookTask{} = task, ctx) do
    description =
      case Map.get(ctx.chapter_numbers, task.chapter_id) do
        nil -> "Generating audio"
        n -> "Generating audio — Ch #{n}"
      end

    base_row(task, "audio", description, ctx)
  end

  defp present_row(%ReadaloudImporter.ImportTask{} = task, ctx) do
    base_row(task, "import", "Importing #{Path.basename(task.file_path)}", ctx)
  end

  defp base_row(task, kind, description, ctx) do
    %{
      task_id: task.id,
      kind: kind,
      description: description,
      subtitle: Map.get(ctx.book_titles, task.book_id),
      error_message: task.error_message,
      success?: Tasks.completed?(task),
      failed?: Tasks.failed?(task),
      state: row_state(task),
      inserted_at: task.inserted_at,
      updated_at: task.updated_at,
      relative_time: relative_time(task.updated_at, ctx.now)
    }
  end

  defp row_state(task) do
    cond do
      Tasks.active?(task) -> :active
      Tasks.terminal?(task) -> :terminal
    end
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
