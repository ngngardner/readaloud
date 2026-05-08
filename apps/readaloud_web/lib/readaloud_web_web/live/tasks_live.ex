defmodule ReadaloudWebWeb.TasksLive do
  use ReadaloudWebWeb, :live_view

  alias ReadaloudLibrary.Tasks
  alias ReadaloudLibrary.Tasks.Dashboard

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Tasks.subscribe()

    {:ok,
     socket
     |> assign(page_title: "Tasks", active_nav: :tasks)
     |> assign_dashboard()}
  end

  @impl true
  def handle_event("cancel_task", %{"task-id" => id}, socket) do
    Tasks.cancel(String.to_integer(id))
    {:noreply, assign_dashboard(socket)}
  end

  @impl true
  def handle_event("retry_task", %{"task-id" => id}, socket) do
    retry(Tasks.get(String.to_integer(id)))
    {:noreply, assign_dashboard(socket)}
  end

  @impl true
  def handle_event("clear_completed", _params, socket) do
    Tasks.clear_completed()
    {:noreply, assign_dashboard(socket)}
  end

  @impl true
  def handle_info({:task_updated, _task}, socket) do
    {:noreply, assign_dashboard(socket)}
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
          <span :if={@dashboard.active != []} class="badge badge-warning badge-sm">
            {length(@dashboard.active)}
          </span>
        </div>

        <div :if={@dashboard.active == []} class="text-base-content/50 py-6 text-center">
          No active tasks
        </div>

        <div class="space-y-3">
          <div
            :for={row <- @dashboard.active}
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
            <span :if={@dashboard.completed != []} class="badge badge-ghost badge-sm">
              {length(@dashboard.completed)}
            </span>
          </div>
          <button
            :if={@dashboard.completed != []}
            phx-click="clear_completed"
            class="btn btn-xs btn-ghost text-base-content/60"
          >
            Clear Completed
          </button>
        </div>

        <div :if={@dashboard.completed == []} class="text-base-content/50 py-6 text-center">
          No completed tasks
        </div>

        <div class="space-y-1">
          <div
            :for={row <- @dashboard.completed}
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

  defp assign_dashboard(socket), do: assign(socket, dashboard: Dashboard.load())

  # Retry dispatch is the one verb that calls back into a consumer app's
  # public API (`generate_for_chapter/3`, `import_file/2`). Putting it in
  # `ReadaloudLibrary.Tasks` would create a compile-time cycle. The dispatch
  # lives here, where the web app already depends on both.
  defp retry(%ReadaloudAudiobook.AudiobookTask{} = task) do
    ReadaloudAudiobook.generate_for_chapter(task.book_id, task.chapter_id,
      model: task.model,
      voice: task.voice
    )
  end

  defp retry(%ReadaloudImporter.ImportTask{} = task) do
    ReadaloudImporter.import_file(task.file_path, task.file_type)
  end

  defp retry(nil), do: :ok
end
