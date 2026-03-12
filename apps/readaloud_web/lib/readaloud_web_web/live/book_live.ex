defmodule ReadaloudWebWeb.BookLive do
  use ReadaloudWebWeb, :live_view

  alias ReadaloudImporter.CoverResolver

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    book = ReadaloudLibrary.get_book!(String.to_integer(id))
    chapters = ReadaloudLibrary.list_chapters(book.id)
    progress = ReadaloudReader.get_progress(book.id)
    audio_map = build_audio_map(chapters, book)
    models = fetch_models()

    if connected?(socket) do
      Phoenix.PubSub.subscribe(ReadaloudWeb.PubSub, "tasks:audiobook:#{book.id}")
    end

    {:ok,
     socket
     |> assign(
       active_nav: :library,
       task_count: active_task_count(),
       book: book,
       chapters: chapters,
       progress: progress,
       audio_map: audio_map,
       models: models,
       selected_model: default_model(book, models),
       selected_voice: default_voice(book, models),
       selected_chapters: MapSet.new(),
       show_generate_panel: false,
       page_title: book.title
     )}
  end

  @impl true
  def handle_event("generate_batch", _params, socket) do
    selected = socket.assigns.selected_chapters
    book = socket.assigns.book
    model = socket.assigns.selected_model
    voice = socket.assigns.selected_voice

    ReadaloudLibrary.update_book(book, %{audio_preferences: %{"model" => model, "voice" => voice}})

    for chapter_id <- selected do
      ReadaloudAudiobook.generate_for_chapter(book.id, chapter_id, model: model, voice: voice)
    end

    chapters = ReadaloudLibrary.list_chapters(book.id)

    {:noreply,
     socket
     |> assign(
       show_generate_panel: false,
       selected_chapters: MapSet.new(),
       audio_map: build_audio_map(chapters, book)
     )}
  end

  @impl true
  def handle_event("select_all_chapters", _params, socket) do
    all_ids = socket.assigns.chapters |> Enum.map(& &1.id) |> MapSet.new()
    {:noreply, assign(socket, selected_chapters: all_ids)}
  end

  @impl true
  def handle_event("select_from_current", _params, socket) do
    current_num = current_chapter_number(socket.assigns.progress, socket.assigns.chapters)

    ids =
      socket.assigns.chapters
      |> Enum.filter(&(&1.number >= current_num))
      |> Enum.map(& &1.id)
      |> MapSet.new()

    {:noreply, assign(socket, selected_chapters: ids)}
  end

  @impl true
  def handle_event("toggle_chapter", %{"chapter-id" => ch_id}, socket) do
    ch_id = String.to_integer(ch_id)
    selected = socket.assigns.selected_chapters

    updated =
      if MapSet.member?(selected, ch_id),
        do: MapSet.delete(selected, ch_id),
        else: MapSet.put(selected, ch_id)

    {:noreply, assign(socket, selected_chapters: updated)}
  end

  @impl true
  def handle_event("delete_book", _params, socket) do
    ReadaloudLibrary.delete_book(socket.assigns.book)
    {:noreply, push_navigate(socket, to: ~p"/")}
  end

  @impl true
  def handle_event("retry_chapter_audio", %{"chapter-id" => ch_id}, socket) do
    book = socket.assigns.book
    model = socket.assigns.selected_model
    voice = socket.assigns.selected_voice
    ReadaloudAudiobook.generate_for_chapter(book.id, String.to_integer(ch_id), model: model, voice: voice)
    {:noreply, socket}
  end

  @impl true
  def handle_event("set_theme", %{"theme" => theme}, socket) do
    {:noreply, push_event(socket, "set_theme", %{theme: theme})}
  end

  @impl true
  def handle_event("toggle_generate_panel", _params, socket) do
    {:noreply, assign(socket, show_generate_panel: !socket.assigns.show_generate_panel)}
  end

  @impl true
  def handle_event("select_model", %{"model" => model_id}, socket) do
    model = Enum.find(socket.assigns.models, &(&1[:id] == model_id))
    voice = if model, do: List.first(model[:voices] || []), else: socket.assigns.selected_voice
    {:noreply, assign(socket, selected_model: model_id, selected_voice: voice)}
  end

  @impl true
  def handle_event("select_voice", %{"voice" => voice}, socket) do
    {:noreply, assign(socket, selected_voice: voice)}
  end

  @impl true
  def handle_info({:task_updated, _task}, socket) do
    chapters = ReadaloudLibrary.list_chapters(socket.assigns.book.id)
    {:noreply, assign(socket, audio_map: build_audio_map(chapters, socket.assigns.book))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto">
      <%!-- Back link --%>
      <.link navigate={~p"/"} class="flex items-center gap-1 text-sm text-base-content/60 hover:text-base-content mb-6">
        <.icon name="hero-arrow-left-mini" class="w-4 h-4" /> Back to Library
      </.link>

      <%!-- Book header --%>
      <div class="flex flex-col sm:flex-row gap-6 mb-8">
        <img :if={cover_url(@book)} src={"/api/books/#{@book.id}/cover"} class="w-24 rounded-lg shadow" />
        <div
          :if={!cover_url(@book)}
          class="w-24 h-32 rounded-lg"
          style={gradient_style(@book)}
        />
        <div class="flex-1">
          <h1 class="text-2xl font-bold tracking-tight"><%= @book.title %></h1>
          <p :if={@book.author} class="text-base-content/60 mt-1"><%= @book.author %></p>
          <div class="flex flex-wrap gap-2 mt-3">
            <span class="badge badge-outline"><%= length(@chapters) %> chapters</span>
            <span class="badge badge-outline">
              <%= progress_count(@progress, @book) %>/<%= length(@chapters) %> read
            </span>
            <span class="badge badge-outline">
              <%= audio_count(@audio_map) %>/<%= length(@chapters) %> audio
            </span>
          </div>
          <div class="flex flex-wrap gap-2 mt-4">
            <.link navigate={resume_path(@book, @progress)} class="btn btn-primary btn-sm">
              Continue Reading
            </.link>
            <button phx-click="toggle_generate_panel" class="btn btn-sm btn-outline">
              Generate Audio
            </button>
            <button
              phx-click="delete_book"
              data-confirm="This will remove the book and all generated audio. Continue?"
              class="btn btn-sm btn-ghost text-error"
            >
              Delete Book
            </button>
          </div>
        </div>
      </div>

      <%!-- Batch generation panel --%>
      <div :if={@show_generate_panel} class="card bg-base-200 p-4 mb-6">
        <div class="flex flex-wrap gap-2 mb-3">
          <button phx-click="select_all_chapters" class="btn btn-xs">All chapters</button>
          <button phx-click="select_from_current" class="btn btn-xs">From current onward</button>
        </div>
        <div class="flex flex-wrap gap-3 mb-3">
          <select phx-change="select_model" name="model" class="select select-sm select-bordered">
            <option
              :for={m <- @models}
              value={m[:id]}
              selected={m[:id] == @selected_model}
            >
              <%= m[:id] %>
            </option>
          </select>
          <select phx-change="select_voice" name="voice" class="select select-sm select-bordered">
            <% current_model = Enum.find(@models, &(&1[:id] == @selected_model)) %>
            <option
              :for={v <- (current_model && current_model[:voices]) || []}
              value={v}
              selected={v == @selected_voice}
            >
              <%= v %>
            </option>
          </select>
        </div>
        <button
          phx-click="generate_batch"
          class="btn btn-primary btn-sm"
          disabled={MapSet.size(@selected_chapters) == 0}
        >
          Generate Selected (<%= MapSet.size(@selected_chapters) %>)
        </button>
      </div>

      <%!-- Chapter list --%>
      <div class="space-y-1">
        <div
          :for={ch <- @chapters}
          class={[
            "flex items-center gap-3 p-3 rounded-lg",
            is_current?(ch, @progress) && "bg-primary/10"
          ]}
        >
          <span class="text-sm font-mono text-base-content/40 w-8"><%= ch.number %></span>
          <.link
            navigate={~p"/books/#{@book.id}/read/#{ch.id}"}
            class="flex-1 text-sm hover:text-primary"
          >
            <%= ch.title || "Chapter #{ch.number}" %>
          </.link>
          <span :if={audio_duration(@audio_map, ch.id)} class="text-xs text-base-content/40">
            <%= audio_duration(@audio_map, ch.id) %>
          </span>
          <.icon
            :if={match?({:ready, _}, Map.get(@audio_map, ch.id))}
            name="hero-speaker-wave"
            class="w-4 h-4 text-success"
          />
          <.icon
            :if={Map.get(@audio_map, ch.id) == :generating}
            name="hero-arrow-path"
            class="w-4 h-4 text-warning animate-spin"
          />
          <.icon
            :if={Map.get(@audio_map, ch.id) == :failed}
            name="hero-exclamation-triangle"
            class="w-4 h-4 text-error"
          />
          <button
            :if={Map.get(@audio_map, ch.id) == :failed}
            phx-click="retry_chapter_audio"
            phx-value-chapter-id={ch.id}
            class="text-xs text-primary hover:underline"
          >
            Retry
          </button>
          <span :if={is_current?(ch, @progress)} class="badge badge-primary badge-xs">
            CURRENT
          </span>
          <input
            :if={@show_generate_panel && !match?({:ready, _}, Map.get(@audio_map, ch.id))}
            type="checkbox"
            checked={MapSet.member?(@selected_chapters, ch.id)}
            phx-click="toggle_chapter"
            phx-value-chapter-id={ch.id}
            class="checkbox checkbox-xs checkbox-primary"
          />
        </div>
      </div>
    </div>
    """
  end

  # --- Private helpers ---

  defp build_audio_map(chapters, book) do
    chapter_ids = Enum.map(chapters, & &1.id)
    audios = ReadaloudAudiobook.list_chapter_audio_for_chapters(chapter_ids)
    tasks = ReadaloudAudiobook.list_tasks_for_chapters(chapter_ids)

    model = get_in(book.audio_preferences || %{}, ["model"])
    voice = get_in(book.audio_preferences || %{}, ["voice"])

    audio_by_chapter = Map.new(audios, &{&1.chapter_id, &1})

    # Active tasks indexed by chapter
    active_by_chapter =
      tasks
      |> Enum.filter(&(&1.status in ["pending", "processing"]))
      |> Map.new(&{&1.chapter_id, &1})

    # Most recent failed task per chapter matching current profile
    failed_by_chapter =
      tasks
      |> Enum.filter(&(&1.status == "failed" && &1.model == model && &1.voice == voice))
      |> Enum.group_by(& &1.chapter_id)
      |> Enum.map(fn {ch_id, ch_tasks} ->
        {ch_id, Enum.max_by(ch_tasks, & &1.updated_at, NaiveDateTime)}
      end)
      |> Map.new()

    Map.new(chapter_ids, fn id ->
      audio = Map.get(audio_by_chapter, id)
      active_task = Map.get(active_by_chapter, id)
      failed_task = Map.get(failed_by_chapter, id)
      audio_matches = audio != nil && audio.model == model && audio.voice == voice

      cond do
        # Priority 1: Active task exists
        active_task != nil && active_task.status == "processing" && audio != nil && !audio_matches ->
          {id, {:generating, audio.duration_seconds}}

        active_task != nil && active_task.status == "pending" && audio != nil && !audio_matches ->
          {id, {:queued, audio.duration_seconds}}

        active_task != nil && active_task.status == "processing" ->
          {id, :processing}

        active_task != nil && active_task.status == "pending" ->
          {id, :queued}

        # Priority 2: Audio matches profile
        audio_matches ->
          {id, {:ready, audio.duration_seconds}}

        # Priority 3: Stale audio, no active task
        audio != nil && !audio_matches ->
          {id, {:stale, audio.duration_seconds}}

        # Priority 4-5: Failed tasks (matching profile only)
        failed_task != nil && failed_task.attempt_number >= 3 ->
          {id, :skipped}

        failed_task != nil ->
          {id, :failed}

        # Priority 6: Nothing
        true ->
          {id, nil}
      end
    end)
  end

  defp current_chapter_number(nil, _chapters), do: 1

  defp current_chapter_number(progress, chapters) do
    case Enum.find(chapters, &(&1.id == progress.current_chapter_id)) do
      nil -> 1
      ch -> ch.number
    end
  end

  defp is_current?(_chapter, nil), do: false
  defp is_current?(chapter, progress), do: chapter.id == progress.current_chapter_id

  defp resume_path(book, nil) do
    chapters = ReadaloudLibrary.list_chapters(book.id)

    case chapters do
      [first | _] -> ~p"/books/#{book.id}/read/#{first.id}"
      [] -> ~p"/books/#{book.id}"
    end
  end

  defp resume_path(book, %{current_chapter_id: nil}), do: ~p"/books/#{book.id}"
  defp resume_path(book, progress), do: ~p"/books/#{book.id}/read/#{progress.current_chapter_id}"

  defp progress_count(nil, _book), do: 0

  defp progress_count(progress, book) do
    current_chapter_number(progress, ReadaloudLibrary.list_chapters(book.id))
  end

  defp audio_count(audio_map), do: Enum.count(audio_map, fn {_, v} -> match?({:ready, _}, v) end)

  defp audio_duration(audio_map, chapter_id) do
    case Map.get(audio_map, chapter_id) do
      {:ready, seconds} when is_number(seconds) and seconds > 0 ->
        mins = trunc(seconds / 60)
        secs = trunc(rem(trunc(seconds), 60))
        "#{mins}:#{String.pad_leading("#{secs}", 2, "0")}"

      _ ->
        nil
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
end
