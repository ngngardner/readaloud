defmodule ReadaloudWebWeb.TasksLive do
  use ReadaloudWebWeb, :live_view

  import Ecto.Query

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(ReadaloudWeb.PubSub, "tasks:import")
      Phoenix.PubSub.subscribe(ReadaloudWeb.PubSub, "tasks:audiobook")
    end

    all_tasks = load_all_tasks()
    {active, completed} = split_tasks(all_tasks)

    {:ok,
     socket
     |> assign(
       page_title: "Tasks",
       active_nav: :tasks,
       task_count: length(active),
       active_tasks: active,
       completed_tasks: completed
     )}
  end

  @impl true
  def handle_event("cancel_task", %{"task-id" => task_id_str, "type" => type}, socket) do
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

    case type do
      "audiobook" ->
        if task = ReadaloudAudiobook.get_task(task_id) do
          task
          |> Ecto.Changeset.change(%{status: "failed", error_message: "Cancelled by user"})
          |> ReadaloudLibrary.Repo.update()
        end

      "import" ->
        if task = ReadaloudImporter.get_task(task_id) do
          task
          |> Ecto.Changeset.change(%{status: "failed", error_message: "Cancelled by user"})
          |> ReadaloudLibrary.Repo.update()
        end

      _ ->
        :ok
    end

    {:noreply, reload_tasks(socket)}
  end

  @impl true
  def handle_event("retry_task", %{"task-id" => task_id_str, "type" => type}, socket) do
    task_id = String.to_integer(task_id_str)

    case type do
      "audiobook" ->
        if task = ReadaloudAudiobook.get_task(task_id) do
          ReadaloudAudiobook.generate_for_chapter(task.book_id, task.chapter_id,
            model: task.model,
            voice: task.voice
          )
        end

      "import" ->
        if task = ReadaloudImporter.get_task(task_id) do
          ReadaloudImporter.import_file(task.file_path, task.file_type)
        end

      _ ->
        :ok
    end

    {:noreply, reload_tasks(socket)}
  end

  @impl true
  def handle_event("clear_completed", _params, socket) do
    ReadaloudAudiobook.clear_completed_tasks()
    ReadaloudImporter.clear_completed_tasks()
    {:noreply, reload_tasks(socket)}
  end

  @impl true
  def handle_info(_, socket) do
    {:noreply, reload_tasks(socket)}
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
          <span :if={@active_tasks != []} class="badge badge-warning badge-sm">
            {length(@active_tasks)}
          </span>
        </div>

        <div :if={@active_tasks == []} class="text-base-content/50 py-6 text-center">
          No active tasks
        </div>

        <div class="space-y-3">
          <div
            :for={task <- @active_tasks}
            class="card bg-base-200 p-4"
          >
            <div class="flex items-center gap-3">
              <.icon name="hero-arrow-path" class="size-5 text-warning animate-spin shrink-0" />
              <div class="flex-1 min-w-0">
                <div class="flex items-center gap-2 mb-1">
                  <span class="font-medium truncate">{task_description(task)}</span>
                  <span class="badge badge-xs badge-ghost shrink-0">
                    {task_type_label(task)}
                  </span>
                </div>
                <div :if={book_name(task) != nil} class="text-xs text-base-content/50 truncate">
                  {book_name(task)}
                </div>
              </div>
              <button
                phx-click="cancel_task"
                phx-value-task-id={task.id}
                phx-value-type={task_type(task)}
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
            <span :if={@completed_tasks != []} class="badge badge-ghost badge-sm">
              {length(@completed_tasks)}
            </span>
          </div>
          <button
            :if={@completed_tasks != []}
            phx-click="clear_completed"
            class="btn btn-xs btn-ghost text-base-content/60"
          >
            Clear Completed
          </button>
        </div>

        <div :if={@completed_tasks == []} class="text-base-content/50 py-6 text-center">
          No completed tasks
        </div>

        <div class="space-y-1">
          <div
            :for={task <- @completed_tasks}
            class="flex items-center gap-3 p-3 rounded-lg hover:bg-base-200 transition-colors"
          >
            <.icon
              :if={task.status == "completed"}
              name="hero-check-circle"
              class="size-5 text-success shrink-0"
            />
            <.icon
              :if={task.status != "completed"}
              name="hero-exclamation-circle"
              class="size-5 text-error shrink-0"
            />
            <div class="flex-1 min-w-0">
              <div class="flex items-center gap-2">
                <span class="text-sm truncate">{task_description(task)}</span>
                <span class="badge badge-xs badge-ghost shrink-0">
                  {task_type_label(task)}
                </span>
              </div>
              <div :if={book_name(task) != nil} class="text-xs text-base-content/50 truncate">
                {book_name(task)}
              </div>
              <div
                :if={task.status != "completed" && task.error_message}
                class="text-xs text-error truncate"
              >
                {task.error_message}
              </div>
            </div>
            <span class="text-xs text-base-content/40 shrink-0">
              {relative_time(task.updated_at)}
            </span>
            <button
              :if={task.status == "failed"}
              phx-click="retry_task"
              phx-value-task-id={task.id}
              phx-value-type={task_type(task)}
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

  defp load_all_tasks do
    audiobook = ReadaloudAudiobook.list_tasks()
    import = ReadaloudImporter.list_tasks()
    audiobook ++ import
  end

  defp split_tasks(tasks) do
    active =
      tasks
      |> Enum.filter(&(&1.status in ["pending", "processing"]))
      |> Enum.sort_by(& &1.inserted_at, {:asc, NaiveDateTime})

    completed =
      tasks
      |> Enum.filter(&(&1.status in ["completed", "failed"]))
      |> Enum.sort_by(& &1.updated_at, {:desc, NaiveDateTime})

    {active, completed}
  end

  defp reload_tasks(socket) do
    all_tasks = load_all_tasks()
    {active, completed} = split_tasks(all_tasks)

    socket
    |> assign(
      task_count: length(active),
      active_tasks: active,
      completed_tasks: completed
    )
  end

  defp task_type(%ReadaloudAudiobook.AudiobookTask{}), do: "audiobook"
  defp task_type(_), do: "import"

  defp task_type_label(%ReadaloudAudiobook.AudiobookTask{}), do: "audio"
  defp task_type_label(_), do: "import"

  defp task_description(%ReadaloudAudiobook.AudiobookTask{} = task) do
    "Generating audio — Ch #{task.chapter_id}"
  end

  defp task_description(task) do
    "Importing #{Path.basename(task.file_path)}"
  end

  defp book_name(task) do
    case ReadaloudLibrary.get_book(task.book_id) do
      nil -> nil
      book -> book.title
    end
  end

  defp relative_time(nil), do: ""

  defp relative_time(dt) do
    now = NaiveDateTime.utc_now()
    diff = NaiveDateTime.diff(now, dt, :second)

    cond do
      diff < 60 -> "#{diff}s ago"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86_400 -> "#{div(diff, 3600)}h ago"
      true -> "#{div(diff, 86_400)}d ago"
    end
  end
end
