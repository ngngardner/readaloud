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
      ReadaloudAudiobook.ensure_audio_generated(book, chapters_needing_audio(chapters, progress))
    end

    {:ok,
     socket
     |> assign(
       active_nav: :library,
       task_count: active_task_count(),
       book: book,
       chapters: chapters,
       chapter_statuses: ReadaloudReader.chapter_statuses(chapters, progress),
       progress: progress,
       audio_map: audio_map,
       hide_read: true,
       models: models,
       selected_model: default_model(book, models),
       selected_voice: default_voice(book, models),
       page_title: book.title
     )}
  end

  @impl true
  def handle_event("delete_book", _params, socket) do
    ReadaloudLibrary.delete_book(socket.assigns.book)
    {:noreply, push_navigate(socket, to: ~p"/")}
  end

  @impl true
  def handle_event("toggle_hide_read", _params, socket) do
    {:noreply, assign(socket, hide_read: not socket.assigns.hide_read)}
  end

  @impl true
  def handle_event("activate_audio", params, socket) do
    book = socket.assigns.book
    chapters = socket.assigns.chapters
    progress = socket.assigns.progress
    model = params["model"] || socket.assigns.selected_model
    voice = params["voice"] || socket.assigns.selected_voice

    case ReadaloudLibrary.update_book(book, %{
           audio_preferences: %{"model" => model, "voice" => voice}
         }) do
      {:ok, book} ->
        ReadaloudAudiobook.ensure_audio_generated(
          book,
          chapters_needing_audio(chapters, progress)
        )

        {:noreply,
         socket
         |> assign(
           book: book,
           selected_model: model,
           selected_voice: voice,
           audio_map: build_audio_map(chapters, book)
         )}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to activate audio")}
    end
  end

  @impl true
  def handle_event("update_audio_settings", %{"model" => model, "voice" => voice}, socket) do
    book = socket.assigns.book
    chapters = socket.assigns.chapters
    progress = socket.assigns.progress

    case ReadaloudLibrary.update_book(book, %{
           audio_preferences: %{"model" => model, "voice" => voice}
         }) do
      {:ok, book} ->
        ReadaloudAudiobook.ensure_audio_generated(
          book,
          chapters_needing_audio(chapters, progress)
        )

        {:noreply,
         socket
         |> assign(
           book: book,
           selected_model: model,
           selected_voice: voice,
           audio_map: build_audio_map(chapters, book)
         )}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update audio settings")}
    end
  end

  @impl true
  def handle_event("update_audio_form", params, socket) do
    model_id = params["model"] || socket.assigns.selected_model
    voice = params["voice"]

    voices =
      case Enum.find(socket.assigns.models, &(&1[:id] == model_id)) do
        nil -> []
        m -> m[:voices] || []
      end

    new_voice =
      cond do
        voice && voice != "" && voice in voices -> voice
        true -> List.first(voices) || socket.assigns.selected_voice
      end

    {:noreply, assign(socket, selected_model: model_id, selected_voice: new_voice)}
  end

  @impl true
  def handle_info({:task_updated, task}, socket) do
    book = socket.assigns.book
    chapters = socket.assigns.chapters
    progress = socket.assigns.progress

    if task.status == "completed" do
      ReadaloudAudiobook.ensure_audio_generated(book, chapters_needing_audio(chapters, progress))
    end

    {:noreply, assign(socket, audio_map: build_audio_map(chapters, book))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto">
      <%!-- Back link --%>
      <.link
        navigate={~p"/"}
        class="flex items-center gap-1 text-sm text-base-content/60 hover:text-base-content mb-6"
      >
        <.icon name="hero-arrow-left-mini" class="w-4 h-4" /> Back to Library
      </.link>

      <%!-- Book header --%>
      <div class="flex flex-col sm:flex-row gap-6 mb-8">
        <img
          :if={cover_url(@book)}
          src={"/api/books/#{@book.id}/cover"}
          class="w-24 rounded-lg shadow"
        />
        <div
          :if={!cover_url(@book)}
          class="w-24 h-32 rounded-lg"
          style={gradient_style(@book)}
        />
        <div class="flex-1">
          <div class="flex items-center gap-2">
            <h1 class="text-2xl font-bold tracking-tight">{@book.title}</h1>
            <%= if @book.audio_preferences do %>
              <div class="dropdown dropdown-end">
                <div tabindex="0" role="button" class="btn btn-ghost btn-sm btn-square">
                  <.icon name="hero-cog-6-tooth" class="w-4 h-4" />
                </div>
                <div
                  tabindex="0"
                  class="dropdown-content z-10 card card-compact bg-base-200 shadow-xl w-64 p-4"
                >
                  <form phx-submit="update_audio_settings">
                    <div class="form-control mb-3">
                      <label class="label label-text text-xs uppercase">Model</label>
                      <select name="model" class="select select-sm select-bordered w-full">
                        <option
                          :for={m <- @models}
                          value={m[:id]}
                          selected={m[:id] == @selected_model}
                        >
                          {m[:id]}
                        </option>
                      </select>
                    </div>
                    <div class="form-control mb-3">
                      <label class="label label-text text-xs uppercase">Voice</label>
                      <select name="voice" class="select select-sm select-bordered w-full">
                        <% current_model = Enum.find(@models, &(&1[:id] == @selected_model)) %>
                        <option
                          :for={v <- (current_model && current_model[:voices]) || []}
                          value={v}
                          selected={v == @selected_voice}
                        >
                          {v}
                        </option>
                      </select>
                    </div>
                    <p class="text-xs text-base-content/50 text-center mb-2">
                      {audio_pending_ready(@audio_map, @chapter_statuses)}/{audio_pending_total(
                        @chapter_statuses
                      )} chapters ready
                    </p>
                    <button type="submit" class="btn btn-primary btn-sm w-full">Save</button>
                  </form>
                </div>
              </div>
            <% end %>
          </div>
          <p :if={@book.author} class="text-base-content/60 mt-1">{@book.author}</p>
          <div class="flex flex-wrap gap-2 mt-3 items-center">
            <span class="badge badge-outline">{length(@chapters)} chapters</span>
            <span class="badge badge-outline">
              {read_count(@chapter_statuses)}/{length(@chapters)} read
            </span>
            <%= if @book.audio_preferences do %>
              <span class="badge badge-outline">
                {audio_pending_ready(@audio_map, @chapter_statuses)}/{audio_pending_total(
                  @chapter_statuses
                )} audio
              </span>
            <% end %>
            <button
              phx-click="toggle_hide_read"
              class="btn btn-ghost btn-xs gap-1"
              title={if @hide_read, do: "Show read chapters", else: "Hide read chapters"}
            >
              <.icon
                name={if @hide_read, do: "hero-eye-slash-mini", else: "hero-eye-mini"}
                class="size-3"
              />
              {if @hide_read, do: "Read hidden", else: "All shown"}
            </button>
          </div>
          <%= if @book.audio_preferences do %>
            <p class="text-xs text-base-content/50 mt-2">
              {audio_pending_ready(@audio_map, @chapter_statuses)}/{audio_pending_total(
                @chapter_statuses
              )} chapters ready · {@book.audio_preferences["model"]} / {@book.audio_preferences[
                "voice"
              ]}
            </p>
          <% end %>
          <div class="flex flex-wrap gap-2 mt-4">
            <.link navigate={resume_path(@book, @progress, @chapters)} class="btn btn-primary btn-sm">
              Continue Reading
            </.link>
            <%= if !@book.audio_preferences do %>
              <div class="dropdown dropdown-end">
                <div tabindex="0" role="button" class="btn btn-sm btn-outline">
                  Set up audio
                </div>
                <div
                  tabindex="0"
                  class="dropdown-content z-10 card card-compact bg-base-200 shadow-xl w-64 p-4"
                >
                  <form phx-change="update_audio_form" phx-submit="activate_audio">
                    <div class="form-control mb-3">
                      <label class="label label-text text-xs uppercase">Model</label>
                      <select name="model" class="select select-sm select-bordered w-full">
                        <option
                          :for={m <- @models}
                          value={m[:id]}
                          selected={m[:id] == @selected_model}
                        >
                          {m[:id]}
                        </option>
                      </select>
                    </div>
                    <div class="form-control mb-3">
                      <label class="label label-text text-xs uppercase">Voice</label>
                      <select name="voice" class="select select-sm select-bordered w-full">
                        <% current_model = Enum.find(@models, &(&1[:id] == @selected_model)) %>
                        <option
                          :for={v <- (current_model && current_model[:voices]) || []}
                          value={v}
                          selected={v == @selected_voice}
                        >
                          {v}
                        </option>
                      </select>
                    </div>
                    <button type="submit" class="btn btn-primary btn-sm w-full">
                      Activate
                    </button>
                  </form>
                </div>
              </div>
            <% end %>
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

      <%!-- Chapter list --%>
      <div class="space-y-1">
        <div
          :for={ch <- @chapters}
          :if={Map.get(@chapter_statuses, ch.id) != :read or not @hide_read}
          class={[
            "flex items-center gap-3 p-3 rounded-lg",
            Map.get(@chapter_statuses, ch.id) == :current && "bg-primary/10",
            Map.get(@chapter_statuses, ch.id) == :read && "opacity-60"
          ]}
        >
          <span class="text-sm font-mono text-base-content/40 w-8">{ch.number}</span>
          <.link
            navigate={~p"/books/#{@book.id}/read/#{ch.id}"}
            class="flex-1 text-sm hover:text-primary"
          >
            {ch.title || "Chapter #{ch.number}"}
          </.link>
          <%= case Map.get(@audio_map, ch.id) do %>
            <% {:ready, _} -> %>
              <span class="text-xs text-base-content/40">{audio_duration(@audio_map, ch.id)}</span>
            <% {:stale, _} -> %>
              <span class="text-xs text-base-content/40">{audio_duration(@audio_map, ch.id)}</span>
            <% {:generating, _} -> %>
              <span class="text-xs text-base-content/40 animate-pulse">
                {audio_duration(@audio_map, ch.id)}
              </span>
            <% {:queued, _} -> %>
              <span class="text-xs text-base-content/40">{audio_duration(@audio_map, ch.id)}</span>
            <% :processing -> %>
              <span class="text-xs text-base-content/40 animate-pulse">generating...</span>
            <% :queued -> %>
              <span class="text-xs text-base-content/40">queued</span>
            <% :failed -> %>
              <span class="text-xs text-error">failed</span>
            <% :skipped -> %>
              <span class="text-xs text-error">skipped</span>
            <% _ -> %>
          <% end %>
          <%= case Map.get(@chapter_statuses, ch.id) do %>
            <% :current -> %>
              <span class="badge badge-primary badge-xs">CURRENT</span>
            <% :read -> %>
              <.icon name="hero-check-mini" class="size-4 text-success" />
            <% _ -> %>
          <% end %>
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

    failed_by_chapter = ReadaloudAudiobook.failed_tasks_by_chapter(tasks, model, voice)

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

  defp chapters_needing_audio(chapters, progress) do
    statuses = ReadaloudReader.chapter_statuses(chapters, progress)
    Enum.reject(chapters, fn ch -> Map.get(statuses, ch.id) == :read end)
  end

  defp resume_path(book, nil, chapters) do
    case chapters do
      [first | _] -> ~p"/books/#{book.id}/read/#{first.id}"
      [] -> ~p"/books/#{book.id}"
    end
  end

  defp resume_path(book, %{current_chapter_id: nil}, _chapters), do: ~p"/books/#{book.id}"

  defp resume_path(book, progress, _chapters),
    do: ~p"/books/#{book.id}/read/#{progress.current_chapter_id}"

  defp read_count(statuses), do: Enum.count(statuses, fn {_, s} -> s == :read end)

  defp audio_pending_total(statuses),
    do: Enum.count(statuses, fn {_id, s} -> s != :read end)

  defp audio_pending_ready(audio_map, statuses) do
    Enum.count(statuses, fn {id, s} ->
      s != :read and match?({:ready, _}, Map.get(audio_map, id))
    end)
  end

  defp audio_duration(audio_map, chapter_id) do
    case Map.get(audio_map, chapter_id) do
      {state, seconds}
      when state in [:ready, :stale, :generating, :queued] and is_number(seconds) and seconds > 0 ->
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
