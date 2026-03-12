defmodule ReadaloudWebWeb.ReaderLive do
  use ReadaloudWebWeb, :live_view

  @impl true
  def mount(%{"id" => book_id, "chapter_id" => chapter_id}, _session, socket) do
    book_id = String.to_integer(book_id)
    chapter_id = String.to_integer(chapter_id)

    book = ReadaloudLibrary.get_book!(book_id)
    chapter = ReadaloudLibrary.get_chapter!(chapter_id)
    chapters = ReadaloudLibrary.list_chapters(book_id)

    content =
      case ReadaloudLibrary.get_chapter_content(chapter) do
        {:ok, c} -> c
        {:error, _} -> nil
      end

    progress = ReadaloudReader.get_progress(book_id)
    audio = ReadaloudAudiobook.get_chapter_audio(chapter_id)
    models = fetch_models()
    audio_state = determine_audio_state(chapter_id, audio)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(ReadaloudWeb.PubSub, "tasks:audiobook:#{book_id}")
      ReadaloudReader.upsert_progress(%{book_id: book_id, current_chapter_id: chapter_id})
    end

    {:ok,
     socket
     |> assign(
       active_nav: :reader,
       task_count: 0,
       book: book,
       chapter: chapter,
       chapters: chapters,
       content: content,
       progress: progress,
       audio: audio,
       audio_state: audio_state,
       models: models,
       selected_model: default_model(book, models),
       selected_voice: default_voice(book, models),
       player_collapsed: false,
       show_settings: false,
       generation_progress: 0,
       initial_scroll: (progress && progress.scroll_position) || 0.0,
       initial_position_ms: (progress && progress.audio_position_ms) || 0,
       page_title: "#{chapter.title || "Chapter #{chapter.number}"} — #{book.title}"
     )}
  end

  # -- Audio states: :none, :generating, :ready --

  defp determine_audio_state(chapter_id, audio) do
    cond do
      audio != nil -> :ready
      has_active_task?(chapter_id) -> :generating
      true -> :none
    end
  end

  # -- Event handlers --

  @impl true
  def handle_event("toggle_playback", _params, socket) do
    {:noreply, push_event(socket, "toggle_audio", %{})}
  end

  @impl true
  def handle_event("prev_chapter", _params, socket) do
    case prev_chapter(socket.assigns.chapter, socket.assigns.chapters) do
      nil -> {:noreply, socket}
      ch -> {:noreply, push_navigate(socket, to: ~p"/books/#{socket.assigns.book.id}/read/#{ch.id}")}
    end
  end

  @impl true
  def handle_event("next_chapter", _params, socket) do
    case next_chapter(socket.assigns.chapter, socket.assigns.chapters) do
      nil -> {:noreply, socket}
      ch -> {:noreply, push_navigate(socket, to: ~p"/books/#{socket.assigns.book.id}/read/#{ch.id}")}
    end
  end

  @impl true
  def handle_event("change_speed", %{"direction" => dir}, socket) do
    {:noreply, push_event(socket, "change_speed", %{direction: dir})}
  end

  @impl true
  def handle_event("toggle_pill", _params, socket) do
    {:noreply, push_event(socket, "toggle_pill", %{})}
  end

  @impl true
  def handle_event("toggle_mute", _params, socket) do
    {:noreply, push_event(socket, "toggle_mute", %{})}
  end

  @impl true
  def handle_event("generate_audio", _params, socket) do
    book = socket.assigns.book
    chapter = socket.assigns.chapter
    model = socket.assigns.selected_model
    voice = socket.assigns.selected_voice

    ReadaloudLibrary.update_book(book, %{audio_preferences: %{"model" => model, "voice" => voice}})
    ReadaloudAudiobook.generate_for_chapter(book.id, chapter.id, model: model, voice: voice)

    {:noreply, assign(socket, audio_state: :generating, generation_progress: 0)}
  end

  @impl true
  def handle_event("cancel_generation", _params, socket) do
    cancel_active_tasks(socket.assigns.chapter.id)
    {:noreply, assign(socket, audio_state: :none, generation_progress: 0)}
  end

  @impl true
  def handle_event("scroll", %{"position" => pos}, socket) do
    ReadaloudReader.upsert_progress(%{
      book_id: socket.assigns.book.id,
      current_chapter_id: socket.assigns.chapter.id,
      scroll_position: pos
    })

    {:noreply, socket}
  end

  @impl true
  def handle_event("audio_position", %{"position_ms" => ms}, socket) do
    ReadaloudReader.upsert_progress(%{
      book_id: socket.assigns.book.id,
      current_chapter_id: socket.assigns.chapter.id,
      audio_position_ms: ms
    })

    {:noreply, socket}
  end

  @impl true
  def handle_event("set_theme", %{"theme" => theme}, socket) do
    {:noreply, push_event(socket, "set_theme", %{theme: theme})}
  end

  @impl true
  def handle_event("update_reader_setting", params, socket) do
    # Relay setting changes to the client-side ReaderSettingsHook
    {key, value} =
      cond do
        params["key"] -> {params["key"], params["value"]}
        params["fontSize"] -> {"fontSize", params["fontSize"]}
        params["lineHeight"] -> {"lineHeight", params["lineHeight"]}
        params["maxWidth"] -> {"maxWidth", params["maxWidth"]}
        true -> {nil, nil}
      end

    if key do
      {:noreply, push_event(socket, "update_reader_setting", %{key: key, value: value})}
    else
      {:noreply, socket}
    end
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

  # -- PubSub handler: audio generation completed --

  @impl true
  def handle_info({:task_updated, task}, socket) do
    if task.chapter_id == socket.assigns.chapter.id and task.status == "completed" do
      audio = ReadaloudAudiobook.get_chapter_audio(socket.assigns.chapter.id)
      {:noreply, assign(socket, audio: audio, audio_state: :ready)}
    else
      {:noreply, socket}
    end
  end

  # -- Render --

  @impl true
  def render(assigns) do
    ~H"""
    <div id="reader-root" phx-hook="KeyboardShortcutsHook" class="min-h-screen bg-base-100">
      <%!-- 1. Floating pill (immersive nav) --%>
      <div
        id="floating-pill"
        phx-hook="FloatingPillHook"
        class="fixed top-4 left-1/2 -translate-x-1/2 z-50 flex items-center gap-3
               bg-base-200/90 backdrop-blur-xl rounded-full px-4 py-2 shadow-lg border border-base-content/6
               opacity-0 pointer-events-none transition-opacity duration-200"
      >
        <.link navigate={~p"/books/#{@book.id}"} class="btn btn-ghost btn-xs btn-circle">
          <.icon name="hero-arrow-left" class="w-4 h-4" />
        </.link>
        <.link navigate={~p"/"} class="btn btn-ghost btn-xs btn-circle">
          <.icon name="hero-book-open" class="w-4 h-4" />
        </.link>
        <span class="text-xs text-base-content/60">
          Ch <%= chapter_index(@chapter, @chapters) + 1 %> / <%= length(@chapters) %>
        </span>
        <button phx-click={JS.toggle(to: "#reader-settings")} class="btn btn-ghost btn-xs btn-circle">
          <.icon name="hero-cog-6-tooth" class="w-4 h-4" />
        </button>
      </div>

      <%!-- Reader settings popover --%>
      <div
        id="reader-settings"
        class="fixed top-16 right-4 z-50 hidden
               bg-base-200 rounded-xl shadow-xl border border-base-content/10 p-4 w-72"
      >
        <h3 class="text-sm font-semibold mb-3">Reading Settings</h3>

        <div class="space-y-3">
          <div>
            <label class="text-xs text-base-content/60 mb-1 block">Font</label>
            <div class="join w-full">
              <button
                :for={font <- [{"serif", "Serif"}, {"sans", "Sans"}, {"mono", "Mono"}]}
                phx-click={JS.push("update_reader_setting", value: %{key: "fontFamily", value: elem(font, 0)})}
                class="btn btn-xs join-item flex-1"
              >
                <%= elem(font, 1) %>
              </button>
            </div>
          </div>

          <div>
            <label class="text-xs text-base-content/60 mb-1 block">Font Size</label>
            <input
              type="range"
              min="14"
              max="28"
              value="18"
              phx-change="update_reader_setting"
              name="fontSize"
              class="range range-xs w-full"
            />
          </div>

          <div>
            <label class="text-xs text-base-content/60 mb-1 block">Line Height</label>
            <input
              type="range"
              min="1.2"
              max="2.4"
              step="0.2"
              value="1.8"
              phx-change="update_reader_setting"
              name="lineHeight"
              class="range range-xs w-full"
            />
          </div>

          <div>
            <label class="text-xs text-base-content/60 mb-1 block">Width</label>
            <input
              type="range"
              min="500"
              max="1000"
              step="50"
              value="700"
              phx-change="update_reader_setting"
              name="maxWidth"
              class="range range-xs w-full"
            />
          </div>
        </div>
      </div>

      <%!-- 2. Reading area --%>
      <div
        id="reader-content"
        phx-hook="ReaderSettingsHook"
        data-initial-scroll={@initial_scroll}
        class="max-w-[700px] mx-auto px-4 pt-16 pb-32"
      >
        <%!-- Loading skeleton --%>
        <div :if={!@content} class="space-y-4 animate-pulse">
          <div :for={_ <- 1..8} class="h-4 bg-base-300 rounded" style={"width: #{Enum.random(60..95)}%"} />
        </div>

        <%!-- Chapter title --%>
        <div :if={@content} class="text-xs uppercase tracking-widest text-base-content/40 mb-6">
          <%= @chapter.title || "Chapter #{@chapter.number}" %>
        </div>

        <%!-- Chapter content: with word spans when audio ready, plain HTML otherwise --%>
        <article
          :if={@content && @audio_state == :ready}
          id="chapter-text"
          phx-hook="ScrollTracker"
          data-initial-scroll={@initial_scroll}
          class="prose prose-lg max-w-none leading-relaxed"
        >
          <%= raw(prepare_text_with_spans(@content)) %>
        </article>
        <article
          :if={@content && @audio_state != :ready}
          id="chapter-text"
          phx-hook="ScrollTracker"
          data-initial-scroll={@initial_scroll}
          class="prose prose-lg max-w-none leading-relaxed"
        >
          <%= raw(@content) %>
        </article>
      </div>

      <%!-- Re-sync button (shown when user manually scrolls during playback) --%>
      <button id="resync-btn" class="fixed bottom-24 right-4 z-40 btn btn-sm btn-primary shadow-lg hidden">
        <.icon name="hero-arrow-down" class="w-4 h-4" /> Re-sync
      </button>

      <%!-- 3. Bottom bar: three states --%>

      <%!-- State 1: No audio --%>
      <div
        :if={@audio_state == :none}
        class="fixed bottom-0 inset-x-0 z-40 bg-base-200/95 backdrop-blur-xl border-t border-base-content/6 px-4 py-3"
      >
        <div class="max-w-4xl mx-auto flex items-center gap-4">
          <.icon name="hero-speaker-wave" class="w-6 h-6 text-base-content/40" />
          <div class="flex-1">
            <div class="text-sm font-medium">Listen to Audiobook</div>
            <div class="text-xs text-base-content/50">Generate an audiobook version of this chapter</div>
          </div>
          <div class="hidden sm:flex items-center gap-2">
            <select phx-change="select_model" name="model" class="select select-xs select-bordered">
              <option :for={m <- @models} value={m[:id]} selected={m[:id] == @selected_model}>
                <%= m[:id] %>
              </option>
            </select>
            <select phx-change="select_voice" name="voice" class="select select-xs select-bordered">
              <%= for m <- @models, m[:id] == @selected_model, v <- (m[:voices] || []) do %>
                <option value={v} selected={v == @selected_voice}><%= v %></option>
              <% end %>
            </select>
          </div>
          <button phx-click="generate_audio" class="btn btn-primary btn-sm">Generate Audio</button>
        </div>
      </div>

      <%!-- State 2: Generating --%>
      <div
        :if={@audio_state == :generating}
        class="fixed bottom-0 inset-x-0 z-40 bg-base-200/95 backdrop-blur-xl border-t border-base-content/6 px-4 py-3"
      >
        <div class="max-w-4xl mx-auto flex items-center gap-4">
          <.icon name="hero-arrow-path" class="w-6 h-6 animate-spin text-primary" />
          <div class="flex-1">
            <div class="text-sm font-medium">Generating Audio...</div>
            <div class="text-xs text-base-content/50">You can keep reading while this runs</div>
            <progress class="progress progress-primary w-full mt-1" value={@generation_progress} max="100" />
          </div>
          <button phx-click="cancel_generation" class="btn btn-ghost btn-sm">Cancel</button>
        </div>
      </div>

      <%!-- State 3: Audio ready — full player --%>
      <div
        :if={@audio_state == :ready}
        id="audio-player"
        phx-hook="AudioPlayer"
        data-audio-url={~p"/api/books/#{@book.id}/chapters/#{@chapter.id}/audio"}
        data-timings-url={~p"/api/books/#{@book.id}/chapters/#{@chapter.id}/timings"}
        data-initial-position={@initial_position_ms}
        class="fixed bottom-0 inset-x-0 z-40 bg-base-200/95 backdrop-blur-xl border-t border-base-content/6"
      >
        <div class="max-w-4xl mx-auto px-4 py-3">
          <audio id="audio-element" preload="auto"></audio>
          <div class="flex items-center gap-4">
            <button id="play-pause-btn" class="btn btn-circle btn-primary btn-sm">
              &#9654;
            </button>
            <div id="progress-bar" class="flex-1 h-2 bg-base-300 rounded cursor-pointer relative">
              <div
                id="progress-fill"
                class="h-full bg-primary rounded transition-all"
                style="width: 0%"
              >
              </div>
            </div>
            <span id="time-display" class="text-sm font-mono opacity-60">0:00 / 0:00</span>
          </div>
        </div>
      </div>

      <%!-- Chapter navigation footer (when no audio bar) --%>
      <div :if={@audio_state == :none} class="max-w-[700px] mx-auto px-4 pb-24">
        <div class="flex justify-between mt-6">
          <%= if prev = prev_chapter(@chapter, @chapters) do %>
            <.link navigate={~p"/books/#{@book.id}/read/#{prev.id}"} class="btn btn-ghost btn-sm">
              &larr; Previous
            </.link>
          <% else %>
            <div></div>
          <% end %>
          <%= if nxt = next_chapter(@chapter, @chapters) do %>
            <.link navigate={~p"/books/#{@book.id}/read/#{nxt.id}"} class="btn btn-ghost btn-sm">
              Next &rarr;
            </.link>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # -- Private helpers --

  defp prev_chapter(current, chapters) do
    idx = Enum.find_index(chapters, &(&1.id == current.id))
    if idx && idx > 0, do: Enum.at(chapters, idx - 1), else: nil
  end

  defp next_chapter(current, chapters) do
    idx = Enum.find_index(chapters, &(&1.id == current.id))
    if idx && idx < length(chapters) - 1, do: Enum.at(chapters, idx + 1), else: nil
  end

  defp chapter_index(chapter, chapters) do
    Enum.find_index(chapters, &(&1.id == chapter.id)) || 0
  end

  defp has_active_task?(chapter_id) do
    ReadaloudAudiobook.list_tasks()
    |> Enum.any?(&(&1.chapter_id == chapter_id && &1.status in ["pending", "processing"]))
  end

  defp cancel_active_tasks(chapter_id) do
    ReadaloudAudiobook.list_tasks()
    |> Enum.filter(&(&1.chapter_id == chapter_id && &1.status in ["pending", "processing"]))
    |> Enum.each(fn task ->
      import Ecto.Query

      case ReadaloudLibrary.Repo.one(
             from j in Oban.Job,
               where:
                 fragment("?->>'task_id' = ?", j.args, ^to_string(task.id)),
               where: j.state in ["available", "executing"],
               limit: 1
           ) do
        nil -> :ok
        job -> Oban.cancel_job(job.id)
      end
    end)
  end

  # Ported from PlayerLive — wraps each word in a span with data-word-index for highlighting
  defp prepare_text_with_spans(html) do
    segments = Regex.split(~r/(<[^>]+>)/, html, include_captures: true)

    {_idx, io} =
      Enum.reduce(segments, {0, []}, fn segment, {idx, acc} ->
        if String.starts_with?(segment, "<") do
          {idx, [acc, segment]}
        else
          words = String.split(segment, ~r/(\s+)/, include_captures: true)

          {new_idx, parts} =
            Enum.reduce(words, {idx, []}, fn word, {i, wacc} ->
              if String.match?(word, ~r/^\s*$/) do
                {i, [wacc, word]}
              else
                span = "<span class=\"word\" data-word-index=\"#{i}\">#{word}</span>"
                {i + 1, [wacc, span]}
              end
            end)

          {new_idx, [acc, parts]}
        end
      end)

    IO.iodata_to_binary(io)
  end
end
