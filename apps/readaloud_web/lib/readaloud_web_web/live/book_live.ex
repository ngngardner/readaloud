defmodule ReadaloudWebWeb.BookLive do
  use ReadaloudWebWeb, :live_view

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    book = ReadaloudLibrary.get_book!(String.to_integer(id))
    chapters = ReadaloudLibrary.list_chapters(book.id)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(ReadaloudWeb.PubSub, "tasks:audiobook:#{book.id}")
    end

    socket =
      socket
      |> assign(:book, book)
      |> assign(:chapters, chapters)
      |> assign(:audiobook_tasks, ReadaloudAudiobook.list_tasks())

    {:ok, socket}
  end

  @impl true
  def handle_event("generate_audiobook", _params, socket) do
    book = socket.assigns.book
    {:ok, _tasks} = ReadaloudAudiobook.generate_for_book(book.id)
    {:noreply, put_flash(socket, :info, "Audiobook generation started!")}
  end

  @impl true
  def handle_event("delete_book", _params, socket) do
    {:ok, _} = ReadaloudLibrary.delete_book(socket.assigns.book)
    {:noreply, push_navigate(socket, to: ~p"/")}
  end

  @impl true
  def handle_info({:task_updated, _task_id}, socket) do
    {:noreply, assign(socket, :audiobook_tasks, ReadaloudAudiobook.list_tasks())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto p-6">
      <.link navigate={~p"/"} class="text-sm opacity-60 hover:opacity-100">
        &larr; Library
      </.link>

      <div class="flex justify-between items-start mt-4 mb-8">
        <div>
          <h1 class="text-3xl font-bold"><%= @book.title %></h1>
          <p :if={@book.author} class="text-lg opacity-60 mt-1"><%= @book.author %></p>
        </div>
        <div class="flex gap-2">
          <button phx-click="generate_audiobook" class="btn btn-primary btn-sm">
            Generate Audiobook
          </button>
          <button
            phx-click="delete_book"
            data-confirm="Delete this book?"
            class="btn btn-error btn-sm btn-outline"
          >
            Delete
          </button>
        </div>
      </div>

      <div class="space-y-2">
        <div
          :for={chapter <- @chapters}
          class="flex items-center justify-between p-3 bg-base-200 rounded-lg"
        >
          <div>
            <span class="font-mono text-sm opacity-40 mr-3"><%= chapter.number %></span>
            <span><%= chapter.title || "Chapter #{chapter.number}" %></span>
          </div>
          <div class="flex gap-2">
            <.link
              navigate={~p"/books/#{@book.id}/read/#{chapter.id}"}
              class="btn btn-ghost btn-xs"
            >
              Read
            </.link>
            <.link
              navigate={~p"/books/#{@book.id}/listen/#{chapter.id}"}
              class="btn btn-ghost btn-xs"
            >
              Listen
            </.link>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
