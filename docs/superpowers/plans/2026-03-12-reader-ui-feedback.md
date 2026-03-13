# Reader UI Feedback Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix reader UI feedback — floating pill chapter navigation, speed badge, theme in settings, auto-next toggle, accidental navigation popup.

**Architecture:** All changes target `ReaderLive` (server), its JS hooks (client), and CSS. No schema migrations. The accidental navigation popup restructures mount to defer progress updates. The chapter bar adds a new JS-managed slide-down panel driven by data attributes from the server template.

**Tech Stack:** Elixir/Phoenix LiveView, DaisyUI 5, Tailwind CSS 4, Heroicons, vanilla JS hooks

**Spec:** `docs/superpowers/specs/2026-03-12-reader-ui-feedback-design.md`

---

## Chunk 1: Quick Wins (Tasks 1-3)

### Task 1: Auto Next Chapter Toggle (Bug Fix)

The JS wiring exists but there's no UI toggle. Add one.

**Files:**
- Modify: `apps/readaloud_web/lib/readaloud_web_web/live/reader_live.ex:267-280`
- Modify: `apps/readaloud_web/assets/js/hooks/reader_settings.js:23-33`

- [ ] **Step 1: Add toggle markup to settings popover**

In `reader_live.ex`, after the Width slider div (line 279), before the closing `</div>` on line 280, add:

```heex
          <%!-- Toggles --%>
          <div class="divider my-1"></div>

          <label class="flex items-center justify-between cursor-pointer">
            <span class="text-xs text-base-content/60">Auto next chapter</span>
            <input
              type="checkbox"
              id="auto-next-chapter-toggle"
              class="toggle toggle-sm toggle-primary"
            />
          </label>
```

No `phx-click` — the toggle is handled purely client-side in step 2.

- [ ] **Step 2: Initialize toggle and bind change handler in mounted()**

In `reader_settings.js`, add to the end of `mounted()` (after the `handleEvent` block, before the closing `}`):

```javascript
    // Auto-next-chapter toggle: bind once in mounted (not applySettings)
    const autoNextToggle = document.getElementById("auto-next-chapter-toggle");
    if (autoNextToggle) {
      autoNextToggle.checked = !!this.settings.autoNextChapter;
      autoNextToggle.addEventListener("change", () => {
        this.settings.autoNextChapter = autoNextToggle.checked;
        localStorage.setItem(SETTINGS_KEY, JSON.stringify(this.settings));
      });
    }
```

- [ ] **Step 3: Verify manually**

Run: `cd /home/noah/projects/readaloud && mix phx.server`

1. Open a book chapter in the reader
2. Open settings gear → verify "Auto next chapter" toggle appears
3. Toggle it on → refresh page → verify it stays on
4. Play audio to end → verify it navigates to the next chapter

- [ ] **Step 5: Commit**

```bash
cd /home/noah/projects/readaloud
git add apps/readaloud_web/lib/readaloud_web_web/live/reader_live.ex apps/readaloud_web/assets/js/hooks/reader_settings.js
git commit -m "fix: add auto-next-chapter toggle to reader settings"
```

---

### Task 2: Speed Display Badge

Replace the hidden speed dropdown with a persistent speed badge.

**Files:**
- Modify: `apps/readaloud_web/lib/readaloud_web_web/live/reader_live.ex:442-454`
- Modify: `apps/readaloud_web/assets/js/hooks/audio_player.js:68-74,308-318`

- [ ] **Step 1: Replace speed dropdown markup with badge**

In `reader_live.ex`, replace lines 442-454 (the speed dropdown div) with:

```heex
            <%!-- Speed badge (hidden when collapsed) --%>
            <button
              id="speed-badge"
              class="btn btn-ghost btn-xs [.collapsed_&]:hidden font-mono"
              style="font-variant-numeric: tabular-nums;"
              title="Playback speed (click to cycle)"
            >
              1x
            </button>
```

- [ ] **Step 2: Add cycle-on-click and initialization to AudioPlayer**

In `audio_player.js`, replace the speed buttons block (lines 68-74) with:

```javascript
    // Speed badge: click to cycle forward
    this.speedBadge = document.getElementById("speed-badge")
    if (this.speedBadge) {
      this.speedBadge.textContent = this.formatSpeed(savedSpeed)
      this.speedBadge.addEventListener("click", () => {
        const speeds = [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2]
        const cur = this.audio.playbackRate
        const idx = speeds.findIndex(s => Math.abs(s - cur) < 0.01)
        const next = speeds[(idx + 1) % speeds.length]
        this.setSpeed(next)
      })
    }
```

- [ ] **Step 3: Update setSpeed and add formatSpeed helper**

Replace `updateSpeedButtons` (lines 314-318) with:

```javascript
  updateSpeedBadge(speed) {
    if (this.speedBadge) {
      this.speedBadge.textContent = this.formatSpeed(speed)
    }
  },

  formatSpeed(speed) {
    return speed + "x"
  },
```

Update `setSpeed` (line 311) to call `updateSpeedBadge` instead of `updateSpeedButtons`:

```javascript
  setSpeed(speed) {
    this.audio.playbackRate = speed
    localStorage.setItem("readaloud-playback-speed", speed)
    this.updateSpeedBadge(speed)
  },
```

Also update the initial call on line 28 from `this.updateSpeedButtons(savedSpeed)` to `// Speed badge initialized in badge setup above` (remove the line — the badge init is in step 2).

- [ ] **Step 4: Verify manually**

1. Open reader with audio → verify speed shows "1x" by default
2. Click the badge → cycles to "1.25x", "1.5x", etc.
3. After "2x" it wraps to "0.5x"
4. Use +/- keys → verify they still increment/decrement (not cycle)
5. Refresh → verify persisted speed shows correctly

- [ ] **Step 5: Commit**

```bash
cd /home/noah/projects/readaloud
git add apps/readaloud_web/lib/readaloud_web_web/live/reader_live.ex apps/readaloud_web/assets/js/hooks/audio_player.js
git commit -m "fix: show persistent speed badge instead of hidden dropdown"
```

---

### Task 3: Theme Selector in Reader Settings

Add theme grid to the reader settings popover using direct JS theme switching.

**Files:**
- Modify: `apps/readaloud_web/lib/readaloud_web_web/live/reader_live.ex:219-281`
- Modify: `apps/readaloud_web/assets/js/hooks/reader_settings.js`
- Modify: `apps/readaloud_web/assets/css/app.css`

- [ ] **Step 1: Add theme grid markup to settings popover**

In `reader_live.ex`, import the theme lists from `ThemeSelector` at the top of the module (after line 2). The `ThemeSelector` module at `components/theme_selector.ex` defines `@dark_themes` and `@light_themes` as module attributes. To reuse them without duplication, make them accessible via public functions. First, add to `theme_selector.ex`:

```elixir
  def dark_themes, do: @dark_themes
  def light_themes, do: @light_themes
```

Then in `reader_live.ex` (after line 2), reference them:

```elixir
  @dark_themes ReadaloudWebWeb.ThemeSelector.dark_themes()
  @light_themes ReadaloudWebWeb.ThemeSelector.light_themes()
```

Then add `max-h` and `overflow-y-auto` to the settings popover container (line 221-222), changing:

```heex
        class="fixed top-16 right-4 z-50 hidden
               bg-base-200 rounded-xl shadow-xl border border-base-content/10 p-4 w-72"
```

to:

```heex
        class="fixed top-16 right-4 z-50 hidden
               bg-base-200 rounded-xl shadow-xl border border-base-content/10 p-4 w-72
               max-h-[calc(100vh-5rem)] overflow-y-auto"
```

After the auto-next-chapter toggle (added in Task 1), add:

```heex
          <%!-- Theme --%>
          <div class="divider my-1"></div>
          <label class="text-xs text-base-content/60 mb-2 block">Theme</label>

          <div class="mb-2">
            <div class="text-[10px] uppercase tracking-widest text-base-content/40 mb-1">Dark</div>
            <div class="flex flex-wrap gap-1">
              <button
                :for={theme <- @dark_themes}
                data-set-theme={theme}
                class="theme-swatch"
                title={theme}
              >
                <div class="flex gap-0.5 !bg-transparent" data-theme={theme}>
                  <div class="w-1.5 h-1.5 rounded-full bg-base-100"></div>
                  <div class="w-1.5 h-1.5 rounded-full bg-primary"></div>
                  <div class="w-1.5 h-1.5 rounded-full bg-secondary"></div>
                </div>
              </button>
            </div>
          </div>

          <div>
            <div class="text-[10px] uppercase tracking-widest text-base-content/40 mb-1">Light</div>
            <div class="flex flex-wrap gap-1">
              <button
                :for={theme <- @light_themes}
                data-set-theme={theme}
                class="theme-swatch"
                title={theme}
              >
                <div class="flex gap-0.5 !bg-transparent" data-theme={theme}>
                  <div class="w-1.5 h-1.5 rounded-full bg-base-100"></div>
                  <div class="w-1.5 h-1.5 rounded-full bg-primary"></div>
                  <div class="w-1.5 h-1.5 rounded-full bg-secondary"></div>
                </div>
              </button>
            </div>
          </div>
```

Note: The `@dark_themes` and `@light_themes` module attributes are accessible in the template because they're defined at module level.

- [ ] **Step 2: Add theme swatch CSS**

In `app.css`, after the `.word-spoken` block (line 101), add:

```css
/* Theme swatches in reader settings */
.theme-swatch {
  padding: 4px;
  border-radius: 6px;
  border: 2px solid transparent;
  cursor: pointer;
  transition: border-color 0.15s;
}
.theme-swatch:hover {
  border-color: oklch(from var(--color-base-content) l c h / 30%);
}
.theme-swatch.active {
  border-color: var(--color-primary);
}
```

- [ ] **Step 3: Add theme switching logic to reader_settings.js**

In `reader_settings.js`, add to the end of `mounted()` (after line 21, before the closing `}`):

```javascript
    // Theme swatch click handlers
    this.setupThemeSwatches();
```

Add a new method after `applySettings()`:

```javascript
  setupThemeSwatches() {
    const swatches = document.querySelectorAll("[data-set-theme]");
    const currentTheme = localStorage.getItem("phx:theme") || "dark";

    swatches.forEach(btn => {
      // Mark active
      if (btn.dataset.setTheme === currentTheme) {
        btn.classList.add("active");
      }

      btn.addEventListener("click", () => {
        const theme = btn.dataset.setTheme;
        document.documentElement.setAttribute("data-theme", theme);
        localStorage.setItem("phx:theme", theme);

        // Update active state
        swatches.forEach(s => s.classList.remove("active"));
        btn.classList.add("active");
      });
    });
  },
```

- [ ] **Step 4: Verify manually**

1. Open reader settings → scroll down → verify theme grid appears
2. Click a theme swatch → verify theme changes immediately
3. Refresh → verify theme persists
4. Verify the active swatch has a highlight ring
5. On a small screen (or narrow window), verify the settings popover scrolls

- [ ] **Step 5: Commit**

```bash
cd /home/noah/projects/readaloud
git add apps/readaloud_web/lib/readaloud_web_web/live/reader_live.ex apps/readaloud_web/assets/js/hooks/reader_settings.js apps/readaloud_web/assets/css/app.css
git commit -m "feat: add theme selector to reader settings popover"
```

---

## Chunk 2: Accidental Navigation Popup (Task 4)

### Task 4: Accidental Navigation Popup

Detect backward navigation to stale tabs and show a confirmation modal.

**Files:**
- Modify: `apps/readaloud_web/lib/readaloud_web_web/live/reader_live.ex:5-51,71-83,193-504`
- Modify: `apps/readaloud_web/lib/readaloud_web_web/router.ex:23`

- [ ] **Step 1: Update router to accept optional nav query param**

The existing route `live "/books/:id/read/:chapter_id", ReaderLive` already handles query params via `socket.params` — no router change needed. LiveView mount receives query params in the first argument alongside path params when using `handle_params/3`. However, since `mount/3` receives the path params and `handle_params/3` receives the full URI params, we should use `handle_params` for this logic.

Actually, for `push_navigate`, query params arrive in `mount/3` params. Verify: Phoenix LiveView `mount/3` receives merged path + query params. So `%{"nav" => "internal"}` will be in the params map.

- [ ] **Step 2: Restructure mount to detect conflict and defer progress**

In `reader_live.ex`, replace the mount function (lines 5-51) with:

```elixir
  @impl true
  def mount(%{"id" => book_id, "chapter_id" => chapter_id} = params, _session, socket) do
    book_id = String.to_integer(book_id)
    chapter_id = String.to_integer(chapter_id)
    is_internal_nav = params["nav"] == "internal"

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

    # Conflict detection: only on external navigation (no ?nav=internal)
    {show_conflict, conflict_chapter} =
      if connected?(socket) && !is_internal_nav && progress &&
           progress.current_chapter_id != chapter_id do
        current_idx = Enum.find_index(chapters, &(&1.id == chapter_id)) || 0
        last_read_idx = Enum.find_index(chapters, &(&1.id == progress.current_chapter_id))

        if last_read_idx && last_read_idx > current_idx do
          conflict_ch = Enum.at(chapters, last_read_idx)
          {true, conflict_ch}
        else
          {false, nil}
        end
      else
        {false, nil}
      end

    if connected?(socket) do
      Phoenix.PubSub.subscribe(ReadaloudWeb.PubSub, "tasks:audiobook:#{book_id}")
      # Only update progress if no conflict detected
      unless show_conflict do
        ReadaloudReader.upsert_progress(%{book_id: book_id, current_chapter_id: chapter_id})
      end
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
       page_title: "#{chapter.title || "Chapter #{chapter.number}"} — #{book.title}",
       show_conflict_modal: show_conflict,
       conflict_chapter: conflict_chapter
     )}
  end
```

- [ ] **Step 3: Add conflict modal event handlers**

After the `handle_event("select_voice", ...)` handler (line 175), add:

```elixir
  @impl true
  def handle_event("dismiss_conflict", _params, socket) do
    # User chose "Stay" — update progress to current chapter
    ReadaloudReader.upsert_progress(%{
      book_id: socket.assigns.book.id,
      current_chapter_id: socket.assigns.chapter.id
    })
    {:noreply, assign(socket, show_conflict_modal: false, conflict_chapter: nil)}
  end

  @impl true
  def handle_event("go_to_conflict_chapter", _params, socket) do
    ch = socket.assigns.conflict_chapter
    {:noreply,
     socket
     |> assign(show_conflict_modal: false, conflict_chapter: nil)
     |> push_navigate(to: ~p"/books/#{socket.assigns.book.id}/read/#{ch.id}" <> "?nav=internal")}
  end
```

- [ ] **Step 4: Add ?nav=internal to all internal push_navigate calls**

Update `prev_chapter` handler (line 74):
```elixir
      ch -> {:noreply, push_navigate(socket, to: ~p"/books/#{socket.assigns.book.id}/read/#{ch.id}" <> "?nav=internal")}
```

Update `next_chapter` handler (line 82):
```elixir
      ch -> {:noreply, push_navigate(socket, to: ~p"/books/#{socket.assigns.book.id}/read/#{ch.id}" <> "?nav=internal")}
```

Update the chapter navigation footer links in the template (lines 491, 498):
```heex
            <.link navigate={~p"/books/#{@book.id}/read/#{prev.id}" <> "?nav=internal"} class="btn btn-ghost btn-sm">
```
```heex
            <.link navigate={~p"/books/#{@book.id}/read/#{nxt.id}" <> "?nav=internal"} class="btn btn-ghost btn-sm">
```

- [ ] **Step 5: Add conflict modal template**

In the render function, after the re-sync button (line 326) and before the bottom bar section, add:

```heex
      <%!-- Accidental navigation conflict modal --%>
      <div
        :if={@show_conflict_modal}
        class="modal modal-open"
      >
        <div class="modal-box">
          <h3 class="font-bold text-lg mb-2">Continue reading?</h3>
          <p class="text-base-content/70">
            Your last reading position is
            <span class="font-semibold text-base-content">
              <%= if @conflict_chapter do %>
                Chapter <%= @conflict_chapter.title || @conflict_chapter.number %>
              <% end %>
            </span>.
          </p>
          <div class="modal-action">
            <button phx-click="dismiss_conflict" class="btn btn-ghost">
              Stay on <%= @chapter.title || "Chapter #{@chapter.number}" %>
            </button>
            <button phx-click="go_to_conflict_chapter" class="btn btn-primary">
              Go to <%= if @conflict_chapter, do: @conflict_chapter.title || "Chapter #{@conflict_chapter.number}" %>
            </button>
          </div>
        </div>
        <div class="modal-backdrop"><button phx-click="dismiss_conflict">close</button></div>
      </div>
```

- [ ] **Step 6: Verify manually**

1. Open book → read to chapter 5 (ensure progress saves)
2. Manually navigate to `/books/1/read/2` (no `?nav=internal`) → verify conflict modal appears
3. Click "Go to Chapter 5" → verify it navigates to chapter 5
4. Navigate back to chapter 2 via URL → click "Stay on Chapter 2" → verify modal dismisses and progress updates
5. Use prev/next arrows → verify no popup (has `?nav=internal`)

- [ ] **Step 7: Commit**

```bash
cd /home/noah/projects/readaloud
git add apps/readaloud_web/lib/readaloud_web_web/live/reader_live.ex
git commit -m "feat: add accidental navigation popup with deferred progress"
```

---

## Chunk 3: Floating Pill Redesign (Tasks 5-6)

### Task 5: Floating Pill Button Redesign

Replace confusing back/library buttons with home + prev/next.

**Files:**
- Modify: `apps/readaloud_web/lib/readaloud_web_web/live/reader_live.ex:196-216`

- [ ] **Step 1: Replace the floating pill button layout**

Replace the pill contents (lines 203-215) with:

```heex
        <%!-- Home --%>
        <.link navigate={~p"/"} class="btn btn-ghost btn-xs btn-circle" title="Library">
          <.icon name="hero-home" class="w-4 h-4" />
        </.link>

        <%!-- Prev chapter --%>
        <%= if prev = prev_chapter(@chapter, @chapters) do %>
          <.link navigate={~p"/books/#{@book.id}/read/#{prev.id}" <> "?nav=internal"} class="btn btn-ghost btn-xs btn-circle">
            <.icon name="hero-chevron-left" class="w-4 h-4" />
          </.link>
        <% else %>
          <button class="btn btn-ghost btn-xs btn-circle opacity-30" disabled>
            <.icon name="hero-chevron-left" class="w-4 h-4" />
          </button>
        <% end %>

        <%!-- Chapter indicator (tappable → toggles chapter bar) --%>
        <button
          id="chapter-indicator"
          class="text-xs text-base-content/60 hover:text-base-content cursor-pointer px-1"
        >
          Ch <%= chapter_index(@chapter, @chapters) + 1 %> / <%= length(@chapters) %>
        </button>

        <%!-- Next chapter --%>
        <%= if nxt = next_chapter(@chapter, @chapters) do %>
          <.link navigate={~p"/books/#{@book.id}/read/#{nxt.id}" <> "?nav=internal"} class="btn btn-ghost btn-xs btn-circle">
            <.icon name="hero-chevron-right" class="w-4 h-4" />
          </.link>
        <% else %>
          <button class="btn btn-ghost btn-xs btn-circle opacity-30" disabled>
            <.icon name="hero-chevron-right" class="w-4 h-4" />
          </button>
        <% end %>

        <%!-- Settings --%>
        <button phx-click={JS.toggle(to: "#reader-settings")} class="btn btn-ghost btn-xs btn-circle">
          <.icon name="hero-cog-6-tooth" class="w-4 h-4" />
        </button>
```

- [ ] **Step 2: Verify manually**

1. Open reader → trigger pill visibility → verify Home, ‹, "Ch X/Y", ›, gear layout
2. At first chapter → verify ‹ is disabled/dimmed
3. At last chapter → verify › is disabled/dimmed
4. Click Home → verify it goes to library
5. Click ‹/› → verify chapter navigation (no conflict popup)

- [ ] **Step 3: Commit**

```bash
cd /home/noah/projects/readaloud
git add apps/readaloud_web/lib/readaloud_web_web/live/reader_live.ex
git commit -m "feat: redesign floating pill with home + prev/next chapter buttons"
```

---

### Task 6: Slide-Down Chapter Bar

Add the hybrid scrubber + chapter strip that slides down from the pill.

**Files:**
- Modify: `apps/readaloud_web/lib/readaloud_web_web/live/reader_live.ex` (after floating pill div)
- Create: `apps/readaloud_web/assets/js/hooks/chapter_bar.js`
- Modify: `apps/readaloud_web/assets/js/app.js`
- Modify: `apps/readaloud_web/assets/js/hooks/floating_pill.js`
- Modify: `apps/readaloud_web/assets/css/app.css`

- [ ] **Step 1: Add chapter bar markup**

In `reader_live.ex`, immediately after the closing `</div>` of the floating pill (line 216), add:

```heex
      <%!-- Slide-down chapter bar --%>
      <div
        id="chapter-bar"
        phx-hook="ChapterBarHook"
        data-current-index={chapter_index(@chapter, @chapters)}
        data-total-chapters={length(@chapters)}
        data-chapters={Jason.encode!(Enum.map(@chapters, fn ch -> %{id: ch.id, number: ch.number, title: ch.title} end))}
        data-book-id={@book.id}
        class="fixed top-16 left-1/2 -translate-x-1/2 z-[49]
               bg-base-200/95 backdrop-blur-xl rounded-xl px-4 py-3 shadow-lg border border-base-content/6
               w-[min(90vw,500px)] space-y-2
               transition-all duration-200 ease-out origin-top
               scale-y-0 opacity-0 pointer-events-none"
      >
        <%!-- Row 1: Progress scrubber --%>
        <div data-chapter-scrubber class="relative h-5 cursor-pointer select-none group">
          <div class="absolute top-2 left-0 right-0 h-1.5 bg-base-300 rounded-full">
            <div data-scrubber-fill class="h-full bg-primary rounded-full" style="width: 0%"></div>
          </div>
          <div data-scrubber-thumb class="absolute top-0.5 w-4 h-4 bg-primary rounded-full shadow -translate-x-1/2" style="left: 0%"></div>
          <div data-scrubber-tooltip class="absolute -top-7 bg-base-300 text-xs px-2 py-0.5 rounded shadow hidden -translate-x-1/2 whitespace-nowrap"></div>
        </div>

        <%!-- Row 2: Nearby chapter strip --%>
        <div data-chapter-strip class="flex gap-1 overflow-x-auto py-1 scrollbar-hide">
          <button
            :for={{ch, idx} <- Enum.with_index(@chapters)}
            data-chapter-pill={idx}
            data-chapter-id={ch.id}
            class={"shrink-0 w-8 h-8 rounded-full text-xs flex items-center justify-center cursor-pointer transition-colors " <>
              if(idx == chapter_index(@chapter, @chapters),
                do: "bg-primary text-primary-content font-bold",
                else: "bg-base-300/50 text-base-content/60 hover:bg-base-300")}
          >
            <%= idx + 1 %>
          </button>
        </div>
      </div>
```

- [ ] **Step 2: Create ChapterBarHook**

Create `apps/readaloud_web/assets/js/hooks/chapter_bar.js`:

```javascript
const ChapterBarHook = {
  mounted() {
    this.currentIndex = parseInt(this.el.dataset.currentIndex)
    this.totalChapters = parseInt(this.el.dataset.totalChapters)
    this.chapters = JSON.parse(this.el.dataset.chapters)
    this.bookId = this.el.dataset.bookId
    this.isOpen = false

    this.scrubber = this.el.querySelector("[data-chapter-scrubber]")
    this.fill = this.el.querySelector("[data-scrubber-fill]")
    this.thumb = this.el.querySelector("[data-scrubber-thumb]")
    this.tooltip = this.el.querySelector("[data-scrubber-tooltip]")
    this.strip = this.el.querySelector("[data-chapter-strip]")

    // Set initial scrubber position
    this.setScrubberPosition(this.currentIndex)

    // Scroll strip to center current chapter
    this.scrollStripToIndex(this.currentIndex)

    // Scrubber drag
    this.setupScrubber()

    // Chapter indicator toggle
    const indicator = document.getElementById("chapter-indicator")
    if (indicator) {
      indicator.addEventListener("click", () => this.toggle())
    }

    // Click outside to close
    this._outsideClickHandler = (e) => {
      if (this.isOpen && !this.el.contains(e.target) && e.target.id !== "chapter-indicator") {
        this.close()
      }
    }
    document.addEventListener("click", this._outsideClickHandler)

    // Chapter pill clicks
    this.el.querySelectorAll("[data-chapter-pill]").forEach(pill => {
      pill.addEventListener("click", () => {
        const idx = parseInt(pill.dataset.chapterPill)
        const ch = this.chapters[idx]
        if (ch) {
          this.pushEvent("jump_to_chapter", { chapter_id: ch.id })
        }
      })
    })
  },

  toggle() {
    this.isOpen ? this.close() : this.open()
  },

  open() {
    this.el.classList.remove("scale-y-0", "opacity-0", "pointer-events-none")
    this.el.classList.add("scale-y-100", "opacity-100")
    this.isOpen = true
  },

  close() {
    this.el.classList.add("scale-y-0", "opacity-0", "pointer-events-none")
    this.el.classList.remove("scale-y-100", "opacity-100")
    this.isOpen = false
  },

  setScrubberPosition(index) {
    const pct = this.totalChapters > 1
      ? (index / (this.totalChapters - 1)) * 100
      : 0
    if (this.fill) this.fill.style.width = pct + "%"
    if (this.thumb) this.thumb.style.left = pct + "%"
  },

  scrollStripToIndex(index) {
    if (!this.strip) return
    const pill = this.strip.children[index]
    if (pill) {
      // Center the pill in the strip
      const stripRect = this.strip.getBoundingClientRect()
      const pillRect = pill.getBoundingClientRect()
      const scrollLeft = pill.offsetLeft - stripRect.width / 2 + pillRect.width / 2
      this.strip.scrollTo({ left: scrollLeft, behavior: "smooth" })
    }
  },

  setupScrubber() {
    if (!this.scrubber) return

    const indexFromClientX = (clientX) => {
      const rect = this.scrubber.getBoundingClientRect()
      const pct = Math.min(1, Math.max(0, (clientX - rect.left) / rect.width))
      return Math.round(pct * (this.totalChapters - 1))
    }

    const showTooltip = (clientX) => {
      const idx = indexFromClientX(clientX)
      const ch = this.chapters[idx]
      if (!ch || !this.tooltip) return
      const label = ch.title || `Chapter ${ch.number}`
      this.tooltip.textContent = `${idx + 1}. ${label}`
      this.tooltip.classList.remove("hidden")
      const rect = this.scrubber.getBoundingClientRect()
      const pct = (clientX - rect.left) / rect.width * 100
      this.tooltip.style.left = pct + "%"
    }

    const hideTooltip = () => {
      if (this.tooltip) this.tooltip.classList.add("hidden")
    }

    let isDragging = false

    // Mouse events
    this.scrubber.addEventListener("mousedown", (e) => {
      isDragging = true
      const idx = indexFromClientX(e.clientX)
      this.setScrubberPosition(idx)
      this.scrollStripToIndex(idx)
      showTooltip(e.clientX)
      e.preventDefault()
    })

    this._onMouseMove = (e) => {
      if (!isDragging) return
      const idx = indexFromClientX(e.clientX)
      this.setScrubberPosition(idx)
      this.scrollStripToIndex(idx)
      showTooltip(e.clientX)
    }

    this._onMouseUp = (e) => {
      if (!isDragging) return
      isDragging = false
      hideTooltip()
      const idx = indexFromClientX(e.clientX)
      const ch = this.chapters[idx]
      if (ch) {
        this.pushEvent("jump_to_chapter", { chapter_id: ch.id })
      }
    }

    window.addEventListener("mousemove", this._onMouseMove)
    window.addEventListener("mouseup", this._onMouseUp)

    // Touch events
    this.scrubber.addEventListener("touchstart", (e) => {
      isDragging = true
      const touch = e.touches[0]
      const idx = indexFromClientX(touch.clientX)
      this.setScrubberPosition(idx)
      this.scrollStripToIndex(idx)
      showTooltip(touch.clientX)
      e.preventDefault()
    }, { passive: false })

    this.scrubber.addEventListener("touchmove", (e) => {
      if (!isDragging) return
      const touch = e.touches[0]
      const idx = indexFromClientX(touch.clientX)
      this.setScrubberPosition(idx)
      this.scrollStripToIndex(idx)
      showTooltip(touch.clientX)
      e.preventDefault()
    }, { passive: false })

    this.scrubber.addEventListener("touchend", (e) => {
      if (!isDragging) return
      isDragging = false
      hideTooltip()
      const touch = e.changedTouches[0]
      if (touch) {
        const idx = indexFromClientX(touch.clientX)
        const ch = this.chapters[idx]
        if (ch) {
          this.pushEvent("jump_to_chapter", { chapter_id: ch.id })
        }
      }
    })
  },

  destroyed() {
    if (this._onMouseMove) window.removeEventListener("mousemove", this._onMouseMove)
    if (this._onMouseUp) window.removeEventListener("mouseup", this._onMouseUp)
    if (this._outsideClickHandler) document.removeEventListener("click", this._outsideClickHandler)
  }
}

export default ChapterBarHook
```

- [ ] **Step 3: Add jump_to_chapter event handler to ReaderLive**

In `reader_live.ex`, after the `next_chapter` handler, add:

```elixir
  @impl true
  def handle_event("jump_to_chapter", %{"chapter_id" => chapter_id}, socket) do
    chapter_id = if is_binary(chapter_id), do: String.to_integer(chapter_id), else: chapter_id
    {:noreply, push_navigate(socket, to: ~p"/books/#{socket.assigns.book.id}/read/#{chapter_id}" <> "?nav=internal")}
  end
```

- [ ] **Step 5: Register ChapterBarHook in app.js**

In `app.js`, add import (after line 34):

```javascript
import ChapterBarHook from "./hooks/chapter_bar"
```

Add to the Hooks object (line 38-39):

```javascript
const Hooks = {
  ...colocatedHooks, ScrollTracker, AudioPlayer, ThemeHook, SidebarHook,
  DragDropHook, FloatingPillHook, ReaderSettingsHook, KeyboardShortcutsHook, ChapterBarHook
}
```

- [ ] **Step 6: Update FloatingPillHook to collapse chapter bar on hide**

In `floating_pill.js`, update `hide()` (lines 39-43):

```javascript
  hide() {
    this.pill.classList.add("opacity-0", "pointer-events-none");
    this.pill.classList.remove("opacity-100");
    this.visible = false;
    // Also collapse the chapter bar via its CSS transition classes
    const chapterBar = document.getElementById("chapter-bar");
    if (chapterBar) {
      chapterBar.classList.add("scale-y-0", "opacity-0", "pointer-events-none");
      chapterBar.classList.remove("scale-y-100", "opacity-100");
    }
  },
```

- [ ] **Step 7: Add chapter bar CSS**

In `app.css`, after the theme-swatch styles (added in Task 3), add:

```css
/* Chapter bar scrollbar hide */
.scrollbar-hide {
  -ms-overflow-style: none;
  scrollbar-width: none;
}
.scrollbar-hide::-webkit-scrollbar {
  display: none;
}
```

- [ ] **Step 8: Verify manually**

1. Open reader → trigger pill → verify new layout with chapter indicator
2. Click "Ch X / Y" → verify chapter bar slides down (animated) with scrubber + strip
3. Click "Ch X / Y" again → verify it slides up (animated)
4. Click outside the chapter bar → verify it closes
4. Drag scrubber thumb → verify tooltip shows chapter name, strip scrolls to match
5. Release scrubber → verify navigation to that chapter
6. Click a chapter pill → verify navigation
7. Wait for pill to auto-hide → verify chapter bar also hides
8. Test on mobile viewport → verify touch drag works on scrubber

- [ ] **Step 9: Commit**

```bash
cd /home/noah/projects/readaloud
git add apps/readaloud_web/lib/readaloud_web_web/live/reader_live.ex apps/readaloud_web/assets/js/hooks/chapter_bar.js apps/readaloud_web/assets/js/app.js apps/readaloud_web/assets/js/hooks/floating_pill.js apps/readaloud_web/assets/css/app.css
git commit -m "feat: add slide-down chapter bar with scrubber and chapter strip"
```

---

## Chunk 4: Final Verification (Task 7)

### Task 7: Integration Verification

Verify all changes work together end-to-end.

**Files:** None (verification only)

- [ ] **Step 1: Compile and check for warnings**

```bash
cd /home/noah/projects/readaloud && mix compile --warnings-as-errors 2>&1
```

Expected: clean compilation with no warnings.

- [ ] **Step 2: Run existing tests**

```bash
cd /home/noah/projects/readaloud && mix test 2>&1
```

Expected: all existing tests pass.

- [ ] **Step 3: Full manual integration test**

Test checklist:
1. Open library → click book → open a chapter
2. **Floating pill**: verify Home, ‹, Ch X/Y, ›, gear icons appear correctly
3. **Chapter bar**: tap Ch indicator → scrubber + strip appear → drag scrubber → navigate via pill
4. **Speed badge**: verify "1x" shows, click cycles through speeds, +/- keys still work
5. **Theme selector**: open settings → scroll to Theme → change theme → verify immediate change + persistence
6. **Auto next chapter**: enable toggle → play audio to end → verify navigation to next chapter
7. **Accidental navigation**: note current chapter → paste URL to earlier chapter → verify conflict modal → test both "Stay" and "Go to" buttons
8. **Edge cases**: first chapter (no prev), last chapter (no next), book with 1 chapter

- [ ] **Step 4: Deploy**

```bash
cd /home/noah/projects/readaloud && git push
ssh root@pylon "cd /root/projects/readaloud && git pull && mix deps.get && mix compile && systemctl restart readaloud"
```

Wait 10s, then verify at `pylon:4000`.
