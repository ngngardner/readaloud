defmodule ReadaloudWebWeb.TasksLive do
  use ReadaloudWebWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(ReadaloudWeb.PubSub, "tasks:import")
      Phoenix.PubSub.subscribe(ReadaloudWeb.PubSub, "tasks:audiobook")
    end

    socket =
      socket
      |> assign(:import_tasks, ReadaloudImporter.list_tasks())
      |> assign(:audiobook_tasks, ReadaloudAudiobook.list_tasks())

    {:ok, socket}
  end

  @impl true
  def handle_info(_, socket) do
    socket =
      socket
      |> assign(:import_tasks, ReadaloudImporter.list_tasks())
      |> assign(:audiobook_tasks, ReadaloudAudiobook.list_tasks())

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto p-6">
      <h1 class="text-3xl font-bold mb-8">Tasks</h1>

      <h2 class="text-xl font-semibold mb-4">Import Tasks</h2>
      <div :if={@import_tasks == []} class="text-base-content/50 mb-8">No import tasks</div>
      <div class="space-y-2 mb-8">
        <div
          :for={task <- @import_tasks}
          class="flex items-center gap-4 p-3 bg-base-200 rounded-lg"
        >
          <.status_badge status={task.status} />
          <span class="flex-1 truncate"><%= Path.basename(task.file_path) %></span>
          <span class="text-sm opacity-60"><%= task.file_type %></span>
          <div :if={task.status == "processing"} class="w-24">
            <progress class="progress progress-primary" value={task.progress * 100} max="100" />
          </div>
        </div>
      </div>

      <h2 class="text-xl font-semibold mb-4">Audiobook Tasks</h2>
      <div :if={@audiobook_tasks == []} class="text-base-content/50">No audiobook tasks</div>
      <div class="space-y-2">
        <div
          :for={task <- @audiobook_tasks}
          class="flex items-center gap-4 p-3 bg-base-200 rounded-lg"
        >
          <.status_badge status={task.status} />
          <span class="flex-1">Chapter <%= task.chapter_id %></span>
          <div :if={task.status == "processing"} class="w-24">
            <progress class="progress progress-primary" value={task.progress * 100} max="100" />
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp status_badge(assigns) do
    color =
      case assigns.status do
        "completed" -> "badge-success"
        "failed" -> "badge-error"
        "processing" -> "badge-warning"
        _ -> "badge-ghost"
      end

    assigns = assign(assigns, :color, color)

    ~H"""
    <span class={"badge badge-sm #{@color}"}><%= @status %></span>
    """
  end
end
