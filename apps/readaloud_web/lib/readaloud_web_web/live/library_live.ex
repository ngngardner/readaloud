defmodule ReadaloudWebWeb.LibraryLive do
  use ReadaloudWebWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(ReadaloudWeb.PubSub, "tasks:import")
    end

    books = ReadaloudLibrary.list_books()

    socket =
      socket
      |> assign(:books, books)
      |> allow_upload(:book_file,
        accept: ~w(.epub .pdf),
        max_entries: 1,
        max_file_size: 100_000_000
      )

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("import", _params, socket) do
    [{file_path, file_type}] =
      consume_uploaded_entries(socket, :book_file, fn %{path: path}, entry ->
        ext = Path.extname(entry.client_name) |> String.trim_leading(".")
        dest = Path.join(upload_dir(), entry.client_name)
        File.mkdir_p!(Path.dirname(dest))
        File.cp!(path, dest)
        {:ok, {dest, ext}}
      end)

    case ReadaloudImporter.import_file(file_path, file_type) do
      {:ok, _task} ->
        {:noreply, put_flash(socket, :info, "Import started!")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Import failed")}
    end
  end

  @impl true
  def handle_info({:import_completed, _book_id}, socket) do
    {:noreply, assign(socket, :books, ReadaloudLibrary.list_books())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-6xl mx-auto p-6">
      <div class="flex justify-between items-center mb-8">
        <h1 class="text-3xl font-bold">Your Library</h1>
        <form phx-submit="import" phx-change="validate" class="flex items-center gap-2">
          <.live_file_input
            upload={@uploads.book_file}
            class="file-input file-input-bordered file-input-sm"
          />
          <button
            type="submit"
            class="btn btn-primary btn-sm"
            disabled={@uploads.book_file.entries == []}
          >
            Upload
          </button>
        </form>
      </div>

      <div :if={@books == []} class="text-center py-20 text-base-content/50">
        <p class="text-xl mb-2">No books yet</p>
        <p>Import an EPUB or PDF to get started</p>
      </div>

      <div class="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-6">
        <.link
          :for={book <- @books}
          navigate={~p"/books/#{book.id}"}
          class="card bg-base-200 hover:bg-base-300 transition shadow"
        >
          <div class="card-body p-4">
            <h2 class="card-title text-sm"><%= book.title %></h2>
            <p :if={book.author} class="text-xs opacity-60"><%= book.author %></p>
            <div class="badge badge-sm badge-outline mt-2"><%= book.total_chapters %> chapters</div>
          </div>
        </.link>
      </div>
    </div>
    """
  end

  defp upload_dir do
    dir = Path.join(System.get_env("STORAGE_PATH", "priv/static/files"), "uploads")
    File.mkdir_p!(dir)
    dir
  end
end
