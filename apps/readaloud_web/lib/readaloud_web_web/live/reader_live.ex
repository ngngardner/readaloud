defmodule ReadaloudWebWeb.ReaderLive do
  use ReadaloudWebWeb, :live_view

  alias ReadaloudWebWeb.ThemeSelector

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
    audio_state = determine_audio_state(chapter_id, audio)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(ReadaloudWeb.PubSub, "tasks:audiobook:#{book_id}")
      send(self(), :fetch_models)
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
       models: [],
       selected_model: default_model(book, []),
       selected_voice: default_voice(book, []),
       show_conflict_modal: false,
       conflict_chapter: nil,
       generation_progress: 0,
       initial_scroll: (progress && progress.scroll_position) || 0.0,
       initial_position_ms: (progress && progress.audio_position_ms) || 0,
       page_title: "#{chapter.title || "Chapter #{chapter.number}"} — #{book.title}"
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    if connected?(socket) do
      progress = socket.assigns.progress
      is_internal = params["nav"] == "internal"

      if !is_internal && progress && progress.current_chapter_id &&
           progress.current_chapter_id != socket.assigns.chapter.id do
        conflict_chapter =
          Enum.find(socket.assigns.chapters, &(&1.id == progress.current_chapter_id))

        if conflict_chapter do
          {:noreply,
           assign(socket, show_conflict_modal: true, conflict_chapter: conflict_chapter)}
        else
          ReadaloudReader.upsert_progress(%{
            book_id: socket.assigns.book.id,
            current_chapter_id: socket.assigns.chapter.id
          })

          ReadaloudAudiobook.reprioritize_pending_jobs(
            socket.assigns.chapters,
            socket.assigns.chapter.number
          )

          {:noreply, socket}
        end
      else
        ReadaloudReader.upsert_progress(%{
          book_id: socket.assigns.book.id,
          current_chapter_id: socket.assigns.chapter.id
        })

        ReadaloudAudiobook.reprioritize_pending_jobs(
          socket.assigns.chapters,
          socket.assigns.chapter.number
        )

        {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
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
  def handle_event("prev_chapter", _params, socket) do
    case prev_chapter(socket.assigns.chapter, socket.assigns.chapters) do
      nil ->
        {:noreply, socket}

      ch ->
        reset_progress_for_chapter(socket.assigns.book.id, ch.id)

        {:noreply,
         push_navigate(socket,
           to: ~p"/books/#{socket.assigns.book.id}/read/#{ch.id}?nav=internal"
         )}
    end
  end

  @impl true
  def handle_event("next_chapter", _params, socket) do
    case next_chapter(socket.assigns.chapter, socket.assigns.chapters) do
      nil ->
        {:noreply, socket}

      ch ->
        reset_progress_for_chapter(socket.assigns.book.id, ch.id)

        {:noreply,
         push_navigate(socket,
           to: ~p"/books/#{socket.assigns.book.id}/read/#{ch.id}?nav=internal"
         )}
    end
  end

  @impl true
  def handle_event("generate_audio", params, socket) do
    book = socket.assigns.book
    chapter = socket.assigns.chapter
    model = params["model"] || socket.assigns.selected_model
    voice = params["voice"] || socket.assigns.selected_voice

    ReadaloudLibrary.update_book(book, %{audio_preferences: %{"model" => model, "voice" => voice}})

    ReadaloudAudiobook.generate_for_chapter(book.id, chapter.id, model: model, voice: voice)

    {:noreply,
     assign(socket,
       audio_state: :generating,
       generation_progress: 0,
       selected_model: model,
       selected_voice: voice
     )}
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
  def handle_event("dismiss_conflict", _params, socket) do
    ReadaloudReader.upsert_progress(%{
      book_id: socket.assigns.book.id,
      current_chapter_id: socket.assigns.chapter.id
    })

    {:noreply, assign(socket, show_conflict_modal: false, conflict_chapter: nil)}
  end

  @impl true
  def handle_event("go_to_conflict_chapter", _params, socket) do
    chapter = socket.assigns.conflict_chapter

    {:noreply,
     socket
     |> assign(show_conflict_modal: false, conflict_chapter: nil)
     |> push_navigate(to: ~p"/books/#{socket.assigns.book.id}/read/#{chapter.id}?nav=internal")}
  end

  @impl true
  def handle_event("jump_to_chapter", %{"chapter_id" => chapter_id}, socket) do
    reset_progress_for_chapter(socket.assigns.book.id, chapter_id)

    {:noreply,
     push_navigate(socket,
       to: ~p"/books/#{socket.assigns.book.id}/read/#{chapter_id}?nav=internal"
     )}
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

  # -- Async model fetch --

  @impl true
  def handle_info(:fetch_models, socket) do
    models = fetch_models()

    {:noreply,
     assign(socket,
       models: models,
       selected_model: default_model(socket.assigns.book, models),
       selected_voice: default_voice(socket.assigns.book, models)
     )}
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
        class="fixed top-4 left-1/2 -translate-x-1/2 z-50 flex items-center gap-1.5
               bg-base-200/90 backdrop-blur-xl rounded-full px-3 py-2 shadow-lg border border-base-content/6
               opacity-0 pointer-events-none transition-opacity duration-200"
      >
        <.link navigate={~p"/"} class="btn btn-ghost btn-xs btn-circle" title="Library">
          <.icon name="hero-home" class="w-4 h-4" />
        </.link>
        <span class="text-xs text-base-content/30 select-none">/</span>
        <.link
          navigate={~p"/books/#{@book.id}"}
          class="btn btn-ghost btn-xs px-2 max-w-[14ch]"
          title={@book.title}
        >
          <span class="truncate">{@book.title}</span>
        </.link>
        <span class="text-xs text-base-content/30 select-none">/</span>
        <button
          phx-click="prev_chapter"
          class="btn btn-ghost btn-xs btn-circle"
          title="Previous chapter"
          disabled={prev_chapter(@chapter, @chapters) == nil}
        >
          <.icon name="hero-chevron-left" class="w-4 h-4" />
        </button>
        <button
          id="chapter-indicator"
          class="btn btn-ghost btn-xs text-xs text-base-content/60 tabular-nums"
          title="Show chapters"
        >
          Ch {chapter_index(@chapter, @chapters) + 1} / {length(@chapters)}
        </button>
        <button
          phx-click="next_chapter"
          class="btn btn-ghost btn-xs btn-circle"
          title="Next chapter"
          disabled={next_chapter(@chapter, @chapters) == nil}
        >
          <.icon name="hero-chevron-right" class="w-4 h-4" />
        </button>
        <button phx-click={JS.toggle(to: "#reader-settings")} class="btn btn-ghost btn-xs btn-circle">
          <.icon name="hero-cog-6-tooth" class="w-4 h-4" />
        </button>
      </div>

      <%!-- Chapter bar (slide-down from pill) --%>
      <div
        id="chapter-bar"
        phx-hook="ChapterBarHook"
        data-pill-popover="chapters"
        data-current-index={chapter_index(@chapter, @chapters)}
        data-total-chapters={length(@chapters)}
        data-chapters={
          Jason.encode!(
            Enum.map(@chapters, fn c -> %{id: c.id, number: c.number, title: c.title} end)
          )
        }
        data-book-id={@book.id}
        class="fixed top-14 left-1/2 -translate-x-1/2 z-49
               w-[90vw] max-w-xl bg-base-200/90 backdrop-blur-xl rounded-2xl
               shadow-lg border border-base-content/6 p-3 origin-top
               transition-all duration-200 scale-y-0 opacity-0 pointer-events-none"
      >
        <%!-- Scrubber row --%>
        <div class="relative mb-2">
          <div
            data-chapter-scrubber
            class="w-full h-2 bg-base-300 rounded-full cursor-pointer relative"
          >
            <div
              data-scrubber-fill
              class="h-full bg-primary rounded-full pointer-events-none"
              style="width: 0%"
            />
            <div
              data-scrubber-thumb
              class="absolute top-1/2 -translate-y-1/2 -translate-x-1/2 w-4 h-4 bg-primary rounded-full shadow"
              style="left: 0%"
            />
          </div>
          <div
            data-scrubber-tooltip
            class="hidden absolute -top-8 -translate-x-1/2 bg-base-300 text-xs px-2 py-1 rounded whitespace-nowrap"
          />
        </div>
        <%!-- Chapter strip --%>
        <div data-chapter-strip class="flex gap-1 overflow-x-auto scrollbar-hide pb-1">
          <button
            :for={{ch, idx} <- Enum.with_index(@chapters)}
            data-chapter-pill={idx}
            class={[
              "btn btn-xs shrink-0",
              if(ch.id == @chapter.id, do: "btn-primary", else: "btn-ghost")
            ]}
          >
            {idx + 1}
          </button>
        </div>
      </div>

      <%!-- Reader settings popover --%>
      <div
        id="reader-settings"
        data-pill-popover="settings"
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
                data-font-family={elem(font, 0)}
                class="btn btn-xs join-item flex-1"
              >
                {elem(font, 1)}
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
              name="maxWidth"
              class="range range-xs w-full"
            />
          </div>

          <div class="divider my-1"></div>

          <%!-- Auto-next chapter toggle --%>
          <label class="flex items-center justify-between cursor-pointer">
            <span class="text-xs text-base-content/60">Auto next chapter</span>
            <input
              id="auto-next-chapter-toggle"
              type="checkbox"
              class="toggle toggle-sm toggle-primary"
            />
          </label>

          <div class="divider my-1"></div>

          <%!-- Theme selector --%>
          <div>
            <div class="text-xs text-base-content/60 mb-2">Theme</div>
            <ThemeSelector.theme_swatches themes={ThemeSelector.dark_themes()} label="Dark" />
            <ThemeSelector.theme_swatches themes={ThemeSelector.light_themes()} label="Light" />
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
          <div
            :for={_ <- 1..8}
            class="h-4 bg-base-300 rounded"
            style={"width: #{Enum.random(60..95)}%"}
          />
        </div>

        <%!-- Chapter title --%>
        <div :if={@content} class="text-xs uppercase tracking-widest text-base-content/40 mb-6">
          {@chapter.title || "Chapter #{@chapter.number}"}
        </div>

        <%!-- Chapter content: with word spans when audio ready, plain HTML otherwise --%>
        <article
          :if={@content && @audio_state == :ready}
          id="chapter-text"
          phx-hook="ScrollTrackerHook"
          data-initial-scroll={@initial_scroll}
          class="prose prose-lg max-w-none leading-relaxed"
        >
          {raw(prepare_text_with_spans(@content))}
        </article>
        <article
          :if={@content && @audio_state != :ready}
          id="chapter-text"
          phx-hook="ScrollTrackerHook"
          data-initial-scroll={@initial_scroll}
          class="prose prose-lg max-w-none leading-relaxed"
        >
          {raw(@content)}
        </article>
      </div>

      <%!-- Re-sync button (shown when user manually scrolls during playback) --%>
      <button
        id="resync-btn"
        class="fixed bottom-24 right-4 z-40 btn btn-sm btn-primary shadow-lg hidden"
      >
        <.icon name="hero-arrow-down" class="w-4 h-4" /> Re-sync
      </button>

      <%!-- 3. Bottom bar: three states --%>

      <%!-- State 1: No audio --%>
      <form
        :if={@audio_state == :none}
        phx-change="update_audio_form"
        phx-submit="generate_audio"
        class="fixed bottom-0 inset-x-0 z-40 bg-base-200/95 backdrop-blur-xl border-t border-base-content/6 px-4 py-3"
      >
        <div class="max-w-2xl mx-auto flex items-center gap-4">
          <.icon name="hero-speaker-wave" class="w-6 h-6 text-base-content/40" />
          <div class="flex-1">
            <div class="text-sm font-medium">Listen to Audiobook</div>
            <div class="text-xs text-base-content/50">
              Generate an audiobook version of this chapter
            </div>
          </div>
          <div class="hidden sm:flex items-center gap-2">
            <select name="model" class="select select-xs select-bordered">
              <option :for={m <- @models} value={m[:id]} selected={m[:id] == @selected_model}>
                {m[:id]}
              </option>
            </select>
            <select name="voice" class="select select-xs select-bordered">
              <%= for m <- @models, m[:id] == @selected_model, v <- (m[:voices] || []) do %>
                <option value={v} selected={v == @selected_voice}>{v}</option>
              <% end %>
            </select>
          </div>
          <button type="submit" class="btn btn-primary btn-sm">Generate Audio</button>
        </div>
      </form>

      <%!-- State 2: Generating --%>
      <div
        :if={@audio_state == :generating}
        class="fixed bottom-0 inset-x-0 z-40 bg-base-200/95 backdrop-blur-xl border-t border-base-content/6 px-4 py-3"
      >
        <div class="max-w-2xl mx-auto flex items-center gap-4">
          <.icon name="hero-arrow-path" class="w-6 h-6 animate-spin text-primary" />
          <div class="flex-1">
            <div class="text-sm font-medium">Generating Audio...</div>
            <div class="text-xs text-base-content/50">You can keep reading while this runs</div>
          </div>
          <button phx-click="cancel_generation" class="btn btn-ghost btn-sm">Cancel</button>
        </div>
      </div>

      <%!-- State 3: Audio ready — full player --%>
      <div
        :if={@audio_state == :ready}
        id="audio-player"
        phx-hook="AudioPlayerHook"
        data-audio-url={~p"/api/books/#{@book.id}/chapters/#{@chapter.id}/audio"}
        data-timings-url={~p"/api/books/#{@book.id}/chapters/#{@chapter.id}/timings"}
        data-initial-position={@initial_position_ms}
        class="fixed bottom-0 inset-x-0 z-40 bg-base-200/95 backdrop-blur-xl border-t border-base-content/6 transition-all duration-300"
      >
        <audio id="audio-element" phx-update="ignore" preload="auto"></audio>
        <div class="max-w-2xl mx-auto px-4 py-3 space-y-3">
          <%!-- Scrubber (hidden when collapsed) --%>
          <div
            data-scrubber
            class="w-full h-2 bg-base-300 rounded cursor-pointer relative select-none [.collapsed_&]:hidden"
          >
            <div
              data-progress-fill
              class="h-full bg-primary rounded pointer-events-none"
              style="width: 0%"
            >
            </div>
          </div>

          <%!-- Controls row --%>
          <div class="flex items-center gap-2">
            <%!-- Skip back (hidden when collapsed) --%>
            <button
              data-skip-back
              class="btn btn-ghost btn-circle btn-sm [.collapsed_&]:hidden"
              title="Skip back 10s"
            >
              <.icon name="hero-arrow-uturn-left" class="w-4 h-4" />
            </button>

            <%!-- Play/pause --%>
            <button id="play-pause-btn" class="btn btn-circle btn-primary btn-sm shrink-0">
              &#9654;
            </button>

            <%!-- Skip forward (hidden when collapsed) --%>
            <button
              data-skip-forward
              class="btn btn-ghost btn-circle btn-sm [.collapsed_&]:hidden"
              title="Skip forward 10s"
            >
              <.icon name="hero-arrow-uturn-right" class="w-4 h-4" />
            </button>

            <%!-- Collapsed-only mini scrubber --%>
            <div
              data-scrubber-mini
              class="hidden [.collapsed_&]:flex flex-1 h-1.5 bg-base-300 rounded cursor-pointer relative select-none"
            >
              <div
                data-progress-fill-mini
                class="h-full bg-primary rounded pointer-events-none"
                style="width: 0%"
              >
              </div>
            </div>

            <%!-- Time display --%>
            <span
              id="time-display"
              class="text-sm font-mono opacity-60 shrink-0 [.collapsed_&]:text-xs"
            >
              0:00 / 0:00
            </span>

            <div class="flex-1 [.collapsed_&]:hidden"></div>

            <%!-- Speed badge (click to cycle). phx-update="ignore" so the
                  hook's textContent updates aren't reverted by morphdom. --%>
            <button
              id="speed-badge"
              phx-update="ignore"
              class="btn btn-ghost btn-xs font-mono tabular-nums [.collapsed_&]:hidden"
              title="Click to change speed"
            >
              1x
            </button>

            <%!-- Volume slider (hidden when collapsed, hidden on mobile) --%>
            <div class="hidden sm:flex items-center gap-1 [.collapsed_&]:!hidden">
              <.icon name="hero-speaker-wave" class="w-4 h-4 opacity-50 shrink-0" />
              <input
                type="range"
                data-volume-slider
                min="0"
                max="1"
                step="0.05"
                value="1"
                class="range range-xs w-20"
              />
            </div>

            <%!-- Regenerate audio --%>
            <button
              phx-click="generate_audio"
              class="btn btn-ghost btn-xs btn-circle [.collapsed_&]:hidden"
              title="Regenerate audio"
            >
              <.icon name="hero-arrow-path" class="w-4 h-4" />
            </button>

            <%!-- Collapse toggle --%>
            <button data-collapse-toggle class="btn btn-ghost btn-xs btn-circle" title="Toggle player">
              <.icon
                name="hero-chevron-down"
                class="w-4 h-4 [.collapsed_&]:rotate-180 transition-transform"
              />
            </button>
          </div>
        </div>
      </div>

      <%!-- Chapter navigation footer (when no audio bar) --%>
      <div :if={@audio_state == :none} class="max-w-[700px] mx-auto px-4 pb-24">
        <div class="flex justify-between mt-6">
          <%= if prev = prev_chapter(@chapter, @chapters) do %>
            <.link
              navigate={~p"/books/#{@book.id}/read/#{prev.id}?nav=internal"}
              class="btn btn-ghost btn-sm"
            >
              &larr; Previous
            </.link>
          <% else %>
            <div></div>
          <% end %>
          <%= if nxt = next_chapter(@chapter, @chapters) do %>
            <.link
              navigate={~p"/books/#{@book.id}/read/#{nxt.id}?nav=internal"}
              class="btn btn-ghost btn-sm"
            >
              Next &rarr;
            </.link>
          <% end %>
        </div>
      </div>

      <%!-- Accidental navigation conflict modal --%>
      <div :if={@show_conflict_modal} class="modal modal-open">
        <div class="modal-box">
          <h3 class="font-bold text-lg">Continue reading?</h3>
          <p class="py-4">
            Your last position was on <strong>
              {if @conflict_chapter,
                do: @conflict_chapter.title || "Chapter #{@conflict_chapter.number}",
                else: "another chapter"}
            </strong>.
            Would you like to go back there or stay here?
          </p>
          <div class="modal-action">
            <button phx-click="dismiss_conflict" class="btn btn-ghost">Stay here</button>
            <button phx-click="go_to_conflict_chapter" class="btn btn-primary">
              Go to {if @conflict_chapter,
                do:
                  "Ch #{Enum.find_index(@chapters, &(&1.id == @conflict_chapter.id)) |> then(&((&1 || 0) + 1))}",
                else: "last position"}
            </button>
          </div>
        </div>
        <div class="modal-backdrop" phx-click="dismiss_conflict"></div>
      </div>
    </div>
    """
  end

  # -- Private helpers --

  defp reset_progress_for_chapter(book_id, chapter_id) do
    ReadaloudReader.upsert_progress(%{
      book_id: book_id,
      current_chapter_id: chapter_id,
      audio_position_ms: 0,
      scroll_position: 0.0
    })
  end

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
             from(j in Oban.Job,
               where: fragment("?->>'task_id' = ?", j.args, ^to_string(task.id)),
               where: j.state in ["available", "executing"],
               limit: 1
             )
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
          # Split em/en-dashes into spaces to match aligner tokenization
          normalized =
            segment
            |> String.replace("\u2014", " ")
            |> String.replace("\u2013", " ")

          words = String.split(normalized, ~r/(\s+)/, include_captures: true)

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
