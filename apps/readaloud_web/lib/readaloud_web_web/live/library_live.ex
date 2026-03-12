defmodule ReadaloudWebWeb.LibraryLive do
  use ReadaloudWebWeb, :live_view

  alias ReadaloudImporter.CoverResolver

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(ReadaloudWeb.PubSub, "tasks:import")
    end

    books = ReadaloudLibrary.list_books_sorted("recent")
    progress_map = build_progress_map(books)

    {:ok,
     socket
     |> assign(
       active_nav: :library,
       task_count: active_task_count(),
       books: books,
       progress_map: progress_map,
       search: "",
       sort: "recent",
       page_title: "Library"
     )
     |> allow_upload(:book_file, accept: ~w(.epub .pdf), max_entries: 1, max_file_size: 100_000_000)}
  end

  @impl true
  def handle_event("search", %{"search" => query}, socket) do
    books =
      if query == "" do
        ReadaloudLibrary.list_books_sorted(socket.assigns.sort)
      else
        ReadaloudLibrary.search_books(query)
      end

    {:noreply, assign(socket, books: books, search: query, progress_map: build_progress_map(books))}
  end

  @impl true
  def handle_event("sort", %{"sort" => sort_by}, socket) do
    books = ReadaloudLibrary.list_books_sorted(sort_by)

    {:noreply,
     socket
     |> assign(books: books, sort: sort_by, progress_map: build_progress_map(books))
     |> push_event("persist_sort", %{sort: sort_by})}
  end

  @impl true
  def handle_event("set_theme", %{"theme" => theme}, socket) do
    {:noreply, push_event(socket, "set_theme", %{theme: theme})}
  end

  # Existing upload handlers preserved from original implementation
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
    books = ReadaloudLibrary.list_books_sorted(socket.assigns.sort)
    {:noreply, assign(socket, books: books, progress_map: build_progress_map(books))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto">
      <%!-- Header with search and controls --%>
      <div class="flex flex-col sm:flex-row gap-4 items-start sm:items-center justify-between mb-6">
        <h1 class="text-2xl font-bold">Library</h1>

        <div class="flex flex-wrap items-center gap-3 w-full sm:w-auto">
          <%!-- Search --%>
          <form phx-change="search" class="flex-1 sm:flex-initial">
            <label class="input input-sm input-bordered flex items-center gap-2">
              <.icon name="hero-magnifying-glass" class="size-4 opacity-50" />
              <input
                type="text"
                name="search"
                value={@search}
                placeholder="Search books..."
                phx-debounce="300"
                class="grow bg-transparent border-none focus:outline-none text-sm"
              />
            </label>
          </form>

          <%!-- Sort --%>
          <form phx-change="sort">
            <select name="sort" class="select select-sm select-bordered">
              <option value="recent" selected={@sort == "recent"}>Recently Read</option>
              <option value="title" selected={@sort == "title"}>Title</option>
              <option value="author" selected={@sort == "author"}>Author</option>
              <option value="added" selected={@sort == "added"}>Date Added</option>
            </select>
          </form>
        </div>
      </div>

      <%!-- Upload drop zone --%>
      <div id="drop-zone" phx-hook="DragDropHook" class="relative mb-6">
        <form phx-submit="import" phx-change="validate">
          <div class="border-2 border-dashed border-base-content/20 rounded-xl p-6 text-center hover:border-primary/40 transition-colors">
            <.live_file_input
              upload={@uploads.book_file}
              class="file-input file-input-bordered file-input-sm"
            />
            <p class="text-xs text-base-content/50 mt-2">
              Drop an EPUB or PDF here, or click to browse
            </p>

            <button
              :if={@uploads.book_file.entries != []}
              type="submit"
              class="btn btn-primary btn-sm mt-3"
            >
              Import
            </button>

            <%!-- Upload progress --%>
            <div :for={entry <- @uploads.book_file.entries} class="mt-2">
              <div class="flex items-center gap-2 justify-center text-sm">
                <span class="truncate max-w-xs"><%= entry.client_name %></span>
                <progress class="progress progress-primary w-24" value={entry.progress} max="100" />
              </div>
              <p :for={err <- upload_errors(@uploads.book_file, entry)} class="text-error text-xs mt-1">
                <%= humanize_upload_error(err) %>
              </p>
            </div>
          </div>

          <%!-- Drop overlay --%>
          <div
            data-drop-overlay
            class="hidden absolute inset-0 bg-primary/10 border-2 border-primary border-dashed rounded-xl flex items-center justify-center"
          >
            <span class="text-primary font-semibold">Drop file to upload</span>
          </div>
        </form>
      </div>

      <%!-- Empty state --%>
      <div :if={@books == []} class="text-center py-20 text-base-content/50">
        <.icon name="hero-book-open" class="size-12 mx-auto mb-3 opacity-30" />
        <p class="text-xl mb-2">No books yet</p>
        <p>Import an EPUB or PDF to get started</p>
      </div>

      <%!-- Book grid --%>
      <div class="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6 gap-4">
        <div :for={book <- @books} class="group relative">
          <.link
            navigate={resume_path(book, @progress_map)}
            class="block aspect-[3/4] rounded-lg overflow-hidden relative shadow-md hover:shadow-xl transition-shadow"
          >
            <%!-- Cover image or gradient --%>
            <img
              :if={cover_url(book)}
              src={cover_url(book)}
              alt={book.title}
              class="absolute inset-0 w-full h-full object-cover"
            />
            <div
              :if={!cover_url(book)}
              class="absolute inset-0"
              style={gradient_style(book)}
            />

            <%!-- Bottom gradient overlay for text --%>
            <div class="absolute inset-x-0 bottom-0 h-2/3 bg-gradient-to-t from-black/80 via-black/40 to-transparent" />

            <%!-- Status badge --%>
            <%= case status_badge(book, Map.get(@progress_map, book.id)) do %>
              <% :done -> %>
                <span class="badge badge-xs badge-success absolute top-2 right-2">Done</span>
              <% :new -> %>
                <span class="badge badge-xs badge-info absolute top-2 right-2">New</span>
              <% {:progress, read, total} -> %>
                <span class="badge badge-xs badge-warning absolute top-2 right-2">
                  <%= read %>/<%= total %>
                </span>
              <% _ -> %>
            <% end %>

            <%!-- Title and author --%>
            <div class="absolute bottom-0 inset-x-0 p-3">
              <h3 class="text-white text-sm font-semibold leading-tight line-clamp-2">
                <%= book.title %>
              </h3>
              <p :if={book.author} class="text-white/70 text-xs mt-0.5 line-clamp-1">
                <%= book.author %>
              </p>
            </div>
          </.link>

          <%!-- Info button --%>
          <.link
            navigate={~p"/books/#{book.id}"}
            class="absolute top-2 left-2 btn btn-circle btn-xs btn-ghost bg-black/30 text-white opacity-0 group-hover:opacity-100 transition-opacity"
            title="Book details"
          >
            <.icon name="hero-information-circle-mini" class="size-4" />
          </.link>
        </div>
      </div>
    </div>
    """
  end

  defp build_progress_map(books) do
    book_ids = Enum.map(books, & &1.id)

    ReadaloudReader.list_progress_for_books(book_ids)
    |> Enum.map(fn p -> {p.book_id, p} end)
    |> Map.new()
  end

  defp resume_path(book, progress_map) do
    case Map.get(progress_map, book.id) do
      %{current_chapter_id: ch_id} when not is_nil(ch_id) ->
        ~p"/books/#{book.id}/read/#{ch_id}"

      _ ->
        chapters = ReadaloudLibrary.list_chapters(book.id)

        case chapters do
          [first | _] -> ~p"/books/#{book.id}/read/#{first.id}"
          [] -> ~p"/books/#{book.id}"
        end
    end
  end

  defp cover_url(book) do
    if book.cover_path && book.cover_path != "" && File.exists?(book.cover_path) do
      "/api/books/#{book.id}/cover"
    else
      nil
    end
  end

  defp gradient_style(book) do
    CoverResolver.gradient_placeholder(book.title)
  end

  defp status_badge(book, progress) do
    total = book.total_chapters || 0
    read = progress_chapter_count(progress, book)
    new_cutoff = DateTime.add(DateTime.utc_now(), -7, :day)

    cond do
      read > 0 and read >= total -> :done
      read == 0 and DateTime.compare(book.inserted_at, new_cutoff) == :gt -> :new
      read > 0 -> {:progress, read, total}
      true -> nil
    end
  end

  defp progress_chapter_count(nil, _book), do: 0

  defp progress_chapter_count(progress, book) do
    case progress.current_chapter_id do
      nil ->
        0

      ch_id ->
        chapters = ReadaloudLibrary.list_chapters(book.id)
        current = Enum.find(chapters, &(&1.id == ch_id))
        if current, do: current.number, else: 0
    end
  end

  defp upload_dir do
    dir = Path.join(System.get_env("STORAGE_PATH", "priv/static/files"), "uploads")
    File.mkdir_p!(dir)
    dir
  end

  defp humanize_upload_error(:too_large), do: "File is too large (max 100MB)"
  defp humanize_upload_error(:not_accepted), do: "Only EPUB and PDF files are accepted"
  defp humanize_upload_error(:too_many_files), do: "Only one file at a time"
  defp humanize_upload_error(err), do: "Upload error: #{inspect(err)}"
end
