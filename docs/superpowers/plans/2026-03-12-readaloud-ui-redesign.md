# Readaloud UI Redesign Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Transform Readaloud from a functional but basic UI into a polished, share-ready audiobook reader with hybrid sidebar navigation, full DaisyUI theming, rich library cards with covers, a merged reader/audio player with word highlighting, and PWA support.

**Architecture:** Full page rewrites of each LiveView module against the existing Elixir umbrella backend. Backend changes are limited to two schema migrations (audio_preferences, model), a TTS model/voice discovery function, and an Oban job for cover resolution. The frontend is Phoenix LiveView + DaisyUI + Heroicons with JS hooks for audio playback, scroll tracking, and the floating pill bar.

**Tech Stack:** Elixir 1.17, Phoenix 1.8, LiveView 1.1, SQLite (ecto_sqlite3), DaisyUI 5 (Tailwind CSS 4), Heroicons, esbuild, Oban, Req (HTTP client)

**Spec:** `docs/superpowers/specs/2026-03-12-readaloud-ui-redesign-design.md`

---

## File Map

### Files to Create

| Path | Purpose |
|------|---------|
| `apps/readaloud_library/priv/repo/migrations/TIMESTAMP_add_audio_preferences_and_model.exs` | Migration: audio_preferences on books, model on audiobook_tasks |
| `apps/readaloud_web/lib/readaloud_web_web/components/sidebar.ex` | Sidebar navigation component (collapsed/expanded/mobile) |
| `apps/readaloud_web/lib/readaloud_web_web/components/theme_selector.ex` | Theme selector modal component |
| `apps/readaloud_web/lib/readaloud_web_web/components/toast.ex` | Toast notification component |
| `apps/readaloud_web/assets/js/hooks/sidebar.js` | Sidebar expand-on-hover + mobile toggle behavior |
| `apps/readaloud_web/assets/js/hooks/floating_pill.js` | Immersive reader floating controls (show/hide/timer) |
| `apps/readaloud_web/assets/js/hooks/reader_settings.js` | Reader settings persistence + live preview |
| `apps/readaloud_web/assets/js/hooks/keyboard_shortcuts.js` | Global keyboard shortcut handler |
| `apps/readaloud_web/assets/js/hooks/drag_drop.js` | Drag-and-drop file upload overlay |
| `apps/readaloud_web/assets/js/hooks/theme.js` | Theme persistence + switcher |
| `apps/readaloud_web/priv/static/fonts/Inter-Variable.woff2` | Self-hosted Inter font |
| `apps/readaloud_web/priv/static/manifest.json` | PWA manifest |
| `apps/readaloud_web/priv/static/sw.js` | Service worker |
| `apps/readaloud_web/priv/static/images/icon-192.png` | PWA icon 192x192 |
| `apps/readaloud_web/priv/static/images/icon-512.png` | PWA icon 512x512 |
| `apps/readaloud_importer/lib/readaloud_importer/cover_resolver.ex` | Cover image extraction + Open Library fallback |
| `apps/readaloud_importer/lib/readaloud_importer/cover_job.ex` | Oban worker for async Open Library cover fetch |
| `apps/readaloud_library/test/readaloud_library/book_test.exs` | Book schema + audio_preferences tests |
| `apps/readaloud_web/test/readaloud_web_web/live/library_live_test.exs` | Library page LiveView tests |
| `apps/readaloud_web/test/readaloud_web_web/live/book_live_test.exs` | Book detail LiveView tests |
| `apps/readaloud_web/lib/readaloud_web_web/live_helpers.ex` | Shared helper functions for all LiveViews (active_task_count, fetch_models, default_model/voice) |
| `apps/readaloud_web/test/readaloud_web_web/live/reader_live_test.exs` | Merged reader/player LiveView tests |

### Files to Modify

| Path | Changes |
|------|---------|
| `apps/readaloud_library/lib/readaloud_library/book.ex` | Add `audio_preferences` field (map) |
| `apps/readaloud_library/lib/readaloud_library.ex` | Add `search_books/1`, `list_books_sorted/1` |
| `apps/readaloud_audiobook/lib/readaloud_audiobook/audiobook_task.ex` | Add `model` field |
| `apps/readaloud_audiobook/lib/readaloud_audiobook/generate_job.ex` | Pass model from task to TTS.synthesize |
| `apps/readaloud_audiobook/lib/readaloud_audiobook.ex` | Accept model in generate_for_chapter opts |
| `apps/readaloud_tts/lib/readaloud_tts.ex` | Add `list_models_and_voices/0` |
| `apps/readaloud_tts/lib/readaloud_tts/local_ai_provider.ex` | Implement `list_models_and_voices/0` |
| `apps/readaloud_tts/lib/readaloud_tts/config.ex` | Add known voice lists per model |
| `apps/readaloud_importer/lib/readaloud_importer/epub_parser.ex` | Add cover extraction to parse result |
| `apps/readaloud_importer/lib/readaloud_importer/pdf_parser.ex` | Add PDF first-page thumbnail |
| `apps/readaloud_importer/lib/readaloud_importer/parse_job.ex` | Call cover resolver after import, store cover_path |
| `apps/readaloud_web/lib/readaloud_web_web/router.ex` | Remove /listen route, add redirect, update layout assigns |
| `apps/readaloud_web/lib/readaloud_web_web/components/layouts/root.html.heex` | Full rewrite: sidebar layout, theme system, PWA meta tags |
| `apps/readaloud_web/lib/readaloud_web_web/components/layouts/app.html.heex` | Update for sidebar + content area layout |
| `apps/readaloud_web/lib/readaloud_web_web/components/layouts.ex` | Add sidebar assigns, active nav detection |
| `apps/readaloud_web/lib/readaloud_web_web/components/core_components.ex` | Add toast, skeleton, badge helpers |
| `apps/readaloud_web/lib/readaloud_web_web/live/library_live.ex` | Full rewrite: search, sort, rich cards, drag-drop |
| `apps/readaloud_web/lib/readaloud_web_web/live/book_live.ex` | Full rewrite: detail layout, batch generation, chapter list |
| `apps/readaloud_web/lib/readaloud_web_web/live/reader_live.ex` | Full rewrite: merge PlayerLive, immersive mode, floating pill, 3-state player |
| `apps/readaloud_web/lib/readaloud_web_web/live/tasks_live.ex` | Full rewrite: cancel, clear completed, retry |
| `apps/readaloud_web/lib/readaloud_web_web/controllers/audio_controller.ex` | Add cover image serving endpoint |
| `apps/readaloud_web/assets/css/app.css` | Full rewrite: enable all DaisyUI themes, vampire/blood, Inter font, semantic highlighting |
| `apps/readaloud_web/assets/js/app.js` | Register all new hooks, remove old hook imports |
| `apps/readaloud_web/assets/js/hooks/audio_player.js` | Major rewrite: collapsible, re-sync, speed/volume persistence |
| `apps/readaloud_web/assets/js/hooks/scroll_tracker.js` | Add re-sync button logic, manual scroll detection |
| `Dockerfile` | Ensure poppler-utils is installed (already present per explorer) |

### Files to Delete

| Path | Reason |
|------|--------|
| `apps/readaloud_web/lib/readaloud_web_web/live/player_live.ex` | Merged into ReaderLive |

---

## Chunk 1: Backend Infrastructure & Foundation

### Task 1: Schema Migrations & Backend Enhancements

**Files:**
- Create: `apps/readaloud_library/priv/repo/migrations/TIMESTAMP_add_audio_preferences_and_model.exs`
- Modify: `apps/readaloud_library/lib/readaloud_library/book.ex`
- Modify: `apps/readaloud_audiobook/lib/readaloud_audiobook/audiobook_task.ex`
- Modify: `apps/readaloud_audiobook/lib/readaloud_audiobook/generate_job.ex`
- Modify: `apps/readaloud_audiobook/lib/readaloud_audiobook.ex`
- Test: `apps/readaloud_library/test/readaloud_library/book_test.exs`

- [ ] **Step 1: Write test for Book audio_preferences field**

```elixir
# apps/readaloud_library/test/readaloud_library/book_test.exs
defmodule ReadaloudLibrary.BookTest do
  use ReadaloudLibrary.DataCase

  alias ReadaloudLibrary.Book

  describe "changeset/2" do
    test "accepts audio_preferences as a map" do
      attrs = %{title: "Test Book", source_type: "epub", audio_preferences: %{"model" => "kokoro", "voice" => "af_heart"}}
      changeset = Book.changeset(%Book{}, attrs)
      assert changeset.valid?
      assert get_change(changeset, :audio_preferences) == %{"model" => "kokoro", "voice" => "af_heart"}
    end

    test "audio_preferences defaults to nil" do
      attrs = %{title: "Test Book", source_type: "epub"}
      changeset = Book.changeset(%Book{}, attrs)
      assert changeset.valid?
      assert get_change(changeset, :audio_preferences) == nil
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /home/noah/projects/readaloud && mix test apps/readaloud_library/test/readaloud_library/book_test.exs -v`
Expected: FAIL — `audio_preferences` field doesn't exist on Book schema

- [ ] **Step 3: Generate and write migration**

Run: `cd /home/noah/projects/readaloud && mix ecto.gen.migration add_audio_preferences_and_model --migrations-path apps/readaloud_library/priv/repo/migrations`

Then edit the generated migration:

```elixir
defmodule ReadaloudLibrary.Repo.Migrations.AddAudioPreferencesAndModel do
  use Ecto.Migration

  def change do
    alter table(:books) do
      add :audio_preferences, :map
    end

    alter table(:audiobook_tasks) do
      add :model, :string
    end
  end
end
```

- [ ] **Step 4: Update Book schema**

In `apps/readaloud_library/lib/readaloud_library/book.ex`, add to the schema block:

```elixir
field :audio_preferences, :map
```

And in `changeset/2`, add `:audio_preferences` to the `cast` list.

- [ ] **Step 5: Update AudiobookTask schema**

In `apps/readaloud_audiobook/lib/readaloud_audiobook/audiobook_task.ex`, add to schema:

```elixir
field :model, :string
```

Add `:model` to the `cast` list in `changeset/2`.

- [ ] **Step 6: Update generate_for_chapter to accept and pass model**

In `apps/readaloud_audiobook/lib/readaloud_audiobook.ex`, update `generate_for_chapter/3`:

```elixir
def generate_for_chapter(book_id, chapter_id, opts \\ []) do
  voice = Keyword.get(opts, :voice)
  speed = Keyword.get(opts, :speed)
  model = Keyword.get(opts, :model)

  attrs = %{book_id: book_id, chapter_id: chapter_id, scope: "chapter", voice: voice, speed: speed, model: model}

  {:ok, task} =
    %AudiobookTask{}
    |> AudiobookTask.changeset(attrs)
    |> Repo.insert()

  %{"task_id" => task.id}
  |> GenerateJob.new()
  |> Oban.insert()

  {:ok, task}
end
```

- [ ] **Step 7: Update GenerateJob to use task.model**

In `apps/readaloud_audiobook/lib/readaloud_audiobook/generate_job.ex`, in the `perform/1` function where it calls `ReadaloudTTS.synthesize/2`, pass the model from the task:

```elixir
# Replace the existing synthesize call:
tts_opts = [
  voice: task.voice || config.voice,
  speed: task.speed || config.speed,
  model: task.model || config.tts_model
]
{:ok, %{audio: chunk_audio}} = ReadaloudTTS.synthesize(chunk, tts_opts)
```

- [ ] **Step 8: Run migration and tests**

Run: `cd /home/noah/projects/readaloud && mix ecto.migrate && mix test apps/readaloud_library/test/readaloud_library/book_test.exs -v`
Expected: Migration succeeds, tests PASS

- [ ] **Step 9: Commit**

```bash
cd /home/noah/projects/readaloud
git add apps/readaloud_library/priv/repo/migrations/ apps/readaloud_library/lib/ apps/readaloud_library/test/ apps/readaloud_audiobook/lib/
git commit -m "feat: add audio_preferences to books and model to audiobook_tasks"
```

---

### Task 2: TTS Model & Voice Discovery

**Files:**
- Modify: `apps/readaloud_tts/lib/readaloud_tts.ex`
- Modify: `apps/readaloud_tts/lib/readaloud_tts/local_ai_provider.ex`
- Modify: `apps/readaloud_tts/lib/readaloud_tts/config.ex`

- [ ] **Step 1: Add known voice map to Config**

In `apps/readaloud_tts/lib/readaloud_tts/config.ex`, add a module attribute:

```elixir
@known_voices %{
  "kokoro" => [
    "af_heart", "af_nicole", "af_sarah", "af_sky",
    "am_adam", "am_michael",
    "bf_emma", "bf_isabella",
    "bm_george", "bm_lewis"
  ]
}

def known_voices, do: @known_voices
```

- [ ] **Step 2: Implement list_models_and_voices in LocalAIProvider**

In `apps/readaloud_tts/lib/readaloud_tts/local_ai_provider.ex`, add:

```elixir
def list_models_and_voices(opts \\ []) do
  config = Keyword.get(opts, :config, Config.from_env())

  case Req.get("#{config.base_url}/v1/models") do
    {:ok, %{status: 200, body: %{"data" => models}}} ->
      tts_models =
        models
        |> Enum.filter(fn m -> String.contains?(m["id"] || "", ["tts", "kokoro", "piper"]) end)
        |> Enum.map(fn m ->
          model_id = m["id"]
          voices = Map.get(Config.known_voices(), model_id, [])
          %{id: model_id, voices: voices}
        end)

      {:ok, tts_models}

    {:ok, %{status: status}} ->
      {:error, "LocalAI returned #{status}"}

    {:error, reason} ->
      {:error, reason}
  end
end
```

- [ ] **Step 3: Add caching wrapper in ReadaloudTTS**

In `apps/readaloud_tts/lib/readaloud_tts.ex`, add:

```elixir
@cache_ttl_ms :timer.minutes(5)

def list_models_and_voices(opts \\ []) do
  case Process.get(:tts_models_cache) do
    {models, cached_at} when is_list(models) ->
      if System.monotonic_time(:millisecond) - cached_at < @cache_ttl_ms do
        {:ok, models}
      else
        fetch_and_cache_models(opts)
      end

    _ ->
      fetch_and_cache_models(opts)
  end
end

defp fetch_and_cache_models(opts) do
  provider = Keyword.get(opts, :provider, LocalAIProvider)
  case provider.list_models_and_voices(opts) do
    {:ok, models} = result ->
      Process.put(:tts_models_cache, {models, System.monotonic_time(:millisecond)})
      result

    error ->
      error
  end
end
```

Note: Process dictionary cache is per-process (per LiveView). For production, consider ETS or `:persistent_term`. This is adequate for a single-user self-hosted app.

- [ ] **Step 4: Verify manually**

Run: `cd /home/noah/projects/readaloud && mix run -e "IO.inspect(ReadaloudTTS.list_models_and_voices())"`
Expected: `{:ok, [%{id: "kokoro", voices: ["af_heart", ...]}]}` (or `{:error, ...}` if LocalAI is not running — that's fine)

- [ ] **Step 5: Commit**

```bash
cd /home/noah/projects/readaloud
git add apps/readaloud_tts/lib/
git commit -m "feat: add TTS model and voice discovery with caching"
```

---

### Task 3: Cover Image Pipeline

**Files:**
- Create: `apps/readaloud_importer/lib/readaloud_importer/cover_resolver.ex`
- Create: `apps/readaloud_importer/lib/readaloud_importer/cover_job.ex`
- Modify: `apps/readaloud_importer/lib/readaloud_importer/epub_parser.ex`
- Modify: `apps/readaloud_importer/lib/readaloud_importer/pdf_parser.ex`
- Modify: `apps/readaloud_importer/lib/readaloud_importer/parse_job.ex`
- Modify: `apps/readaloud_web/lib/readaloud_web_web/controllers/audio_controller.ex`
- Modify: `apps/readaloud_web/lib/readaloud_web_web/router.ex`

- [ ] **Step 1: Create CoverResolver module**

```elixir
# apps/readaloud_importer/lib/readaloud_importer/cover_resolver.ex
defmodule ReadaloudImporter.CoverResolver do
  @moduledoc "Resolves cover images for books via extraction or external APIs."

  @storage_path Application.compile_env(:readaloud_library, :storage_path, "priv/static/files")

  def covers_dir, do: Path.join(@storage_path, "covers")

  def cover_path(book_id), do: Path.join(covers_dir(), "#{book_id}.jpg")

  @doc "Save raw cover bytes for a book. Returns {:ok, path} or {:error, reason}."
  def save_cover(book_id, image_bytes) when is_binary(image_bytes) do
    path = cover_path(book_id)
    File.mkdir_p!(covers_dir())

    case File.write(path, image_bytes) do
      :ok -> {:ok, path}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Generate a deterministic gradient CSS string from a title hash."
  def gradient_placeholder(title) do
    hash = :erlang.phash2(title, 360)
    h1 = hash
    h2 = rem(hash + 120, 360)
    "linear-gradient(145deg, oklch(30% 0.15 #{h1}), oklch(15% 0.10 #{h2}))"
  end

  @doc "Fetch cover from Open Library by title and author. Returns {:ok, image_bytes} or {:error, reason}."
  def fetch_from_open_library(title, author) do
    query = URI.encode_query(%{title: title, author: author || "", limit: "1", fields: "cover_i"})
    search_url = "https://openlibrary.org/search.json?#{query}"

    with {:ok, %{status: 200, body: body}} <- Req.get(search_url, receive_timeout: 10_000),
         [%{"cover_i" => cover_id} | _] when is_integer(cover_id) <- body["docs"] do
      cover_url = "https://covers.openlibrary.org/b/id/#{cover_id}-M.jpg"

      case Req.get(cover_url, receive_timeout: 10_000) do
        {:ok, %{status: 200, body: image_bytes}} when is_binary(image_bytes) ->
          {:ok, image_bytes}

        _ ->
          {:error, :cover_download_failed}
      end
    else
      _ -> {:error, :no_cover_found}
    end
  end
end
```

- [ ] **Step 2: Create CoverJob Oban worker**

```elixir
# apps/readaloud_importer/lib/readaloud_importer/cover_job.ex
defmodule ReadaloudImporter.CoverJob do
  use Oban.Worker, queue: :import, max_attempts: 1

  alias ReadaloudImporter.CoverResolver
  alias ReadaloudLibrary.{Repo, Book}

  @impl true
  def perform(%Oban.Job{args: %{"book_id" => book_id, "title" => title, "author" => author}}) do
    case CoverResolver.fetch_from_open_library(title, author) do
      {:ok, image_bytes} ->
        {:ok, path} = CoverResolver.save_cover(book_id, image_bytes)

        Repo.get!(Book, book_id)
        |> Ecto.Changeset.change(%{cover_path: path})
        |> Repo.update!()

        :ok

      {:error, _reason} ->
        # No cover found — not a failure, just no result. Book keeps gradient placeholder.
        :ok
    end
  end
end
```

- [ ] **Step 3: Add cover extraction to EpubParser**

In `apps/readaloud_importer/lib/readaloud_importer/epub_parser.ex`, add a `extract_cover/2` function and call it from `parse/2`. The function should:

```elixir
defp extract_cover(files, opf_content) do
  # Try to find cover meta in OPF
  cover_id =
    case Regex.run(~r/meta\s+name="cover"\s+content="([^"]+)"/, opf_content) do
      [_, id] -> id
      _ -> nil
    end

  # Reuse parse_manifest's attribute extraction approach (order-independent)
  {:ok, item_regex} = Regex.compile(~S'<item\s+([^>]+)/>', "s")

  manifest =
    Regex.scan(item_regex, opf_content)
    |> Enum.map(fn [_, attrs] ->
      id = extract_attr(attrs, "id")
      href = extract_attr(attrs, "href")
      media_type = extract_attr(attrs, "media-type")
      if id && href && media_type, do: {id, {href, media_type}}, else: nil
    end)
    |> Enum.reject(&is_nil/1)
    |> Map.new()

  # Try cover_id first, then scan for "cover" in image filenames
  image_items =
    manifest
    |> Enum.filter(fn {_, {_, type}} -> String.starts_with?(type, "image/") end)

  cover_item =
    if cover_id && Map.has_key?(manifest, cover_id) do
      Map.get(manifest, cover_id)
    else
      image_items
      |> Enum.find(fn {_, {href, _}} -> String.contains?(String.downcase(href), "cover") end)
      |> case do
        {_, item} -> item
        nil -> nil
      end
    end

  case cover_item do
    {href, _type} ->
      # files is a map from read_epub_zip — look up by href key
      case Map.get(files, href) do
        nil -> {:error, :cover_not_found}
        bytes -> {:ok, bytes}
      end

    nil ->
      {:error, :no_cover_in_epub}
  end
end
```

Call `extract_cover(files, opf_content)` from `parse/2` (the `files` map is already available). Include `cover_image: bytes | nil` in the parse return value.

- [ ] **Step 4: Add PDF thumbnail to PdfParser**

In `apps/readaloud_importer/lib/readaloud_importer/pdf_parser.ex`, add:

```elixir
defp extract_thumbnail(pdf_path, storage_dir) do
  output_prefix = Path.join(storage_dir, "cover")

  case System.cmd("pdftoppm", [
    "-jpeg", "-f", "1", "-l", "1",
    "-scale-to-x", "300", "-scale-to-y", "400",
    pdf_path, output_prefix
  ], stderr_to_stdout: true) do
    {_, 0} ->
      # pdftoppm adds page number suffix: cover-1.jpg
      cover_file = Path.join(storage_dir, "cover-1.jpg")
      if File.exists?(cover_file), do: {:ok, File.read!(cover_file)}, else: {:error, :thumbnail_failed}

    {output, _} ->
      {:error, "pdftoppm failed: #{output}"}
  end
end
```

Include `cover_image: bytes | nil` in the parse return value.

- [ ] **Step 5: Update ParseJob to handle covers**

In `apps/readaloud_importer/lib/readaloud_importer/parse_job.ex`, after the book is created:

```elixir
# After book is created successfully:
case result.cover_image do
  bytes when is_binary(bytes) ->
    CoverResolver.save_cover(book.id, bytes)
    Ecto.Changeset.change(book, %{cover_path: CoverResolver.cover_path(book.id)})
    |> Repo.update!()

  _ ->
    # No embedded cover — enqueue Open Library lookup
    %{"book_id" => book.id, "title" => book.title, "author" => book.author}
    |> CoverJob.new()
    |> Oban.insert()
end
```

- [ ] **Step 6: Add cover serving endpoint**

In `apps/readaloud_web/lib/readaloud_web_web/controllers/audio_controller.ex`, add:

```elixir
def cover(conn, %{"book_id" => book_id}) do
  book = ReadaloudLibrary.get_book!(book_id)

  case book.cover_path do
    path when is_binary(path) and path != "" ->
      if File.exists?(path) do
        send_file(conn, 200, path)
      else
        send_resp(conn, 404, "Cover not found")
      end

    _ ->
      send_resp(conn, 404, "No cover")
  end
end
```

In `router.ex`, add inside the `/api` scope:

```elixir
get "/books/:book_id/cover", AudioController, :cover
```

- [ ] **Step 7: Test cover pipeline manually**

Run: `cd /home/noah/projects/readaloud && mix compile --warnings-as-errors`
Expected: Clean compilation

- [ ] **Step 8: Commit**

```bash
cd /home/noah/projects/readaloud
git add apps/readaloud_importer/lib/ apps/readaloud_web/lib/readaloud_web_web/controllers/ apps/readaloud_web/lib/readaloud_web_web/router.ex
git commit -m "feat: add cover image pipeline with EPUB extraction, PDF thumbnail, and Open Library fallback"
```

---

### Task 4: Theme System, Typography & Root Layout

**Files:**
- Create: `apps/readaloud_web/priv/static/fonts/Inter-Variable.woff2`
- Create: `apps/readaloud_web/assets/js/hooks/theme.js`
- Create: `apps/readaloud_web/lib/readaloud_web_web/components/theme_selector.ex`
- Modify: `apps/readaloud_web/assets/css/app.css`
- Modify: `apps/readaloud_web/lib/readaloud_web_web/components/layouts/root.html.heex`
- Modify: `apps/readaloud_web/assets/js/app.js`

- [ ] **Step 1: Download and install Inter font**

```bash
cd /home/noah/projects/readaloud/apps/readaloud_web/priv/static/fonts
curl -L -o Inter-Variable.woff2 "https://github.com/rsms/inter/raw/master/docs/font-files/InterVariable.woff2"
```

- [ ] **Step 2: Rewrite app.css**

Full rewrite of `apps/readaloud_web/assets/css/app.css`:

```css
/* Preserve existing Tailwind source directives */
@import "tailwindcss" source(none);
@source "../css";
@source "../js";
@source "../../lib/readaloud_web_web";

@plugin "../vendor/heroicons";

/* Enable all DaisyUI built-in themes */
@plugin "../vendor/daisyui" {
  themes: true;
}

/* Custom theme: Vampire (dark, blue-light-filter friendly, orange/amber accents) */
@plugin "../vendor/daisyui-theme" {
  name: "vampire";
  default: false;
  prefersdark: false;
  color-scheme: "dark";
  --color-base-100: oklch(10% 0 0);
  --color-base-200: oklch(15% 0 0);
  --color-base-300: oklch(20% 0 0);
  --color-base-content: oklch(85% 0 0);
  --color-primary: oklch(50% 0.25 20);
  --color-primary-content: oklch(98% 0 0);
  --color-secondary: oklch(40% 0.2 15);
  --color-secondary-content: oklch(98% 0 0);
  --color-accent: oklch(60% 0.3 25);
  --color-accent-content: oklch(98% 0 0);
  --color-neutral: oklch(25% 0 0);
  --color-neutral-content: oklch(85% 0 0);
  --color-info: oklch(60% 0.15 200);
  --color-success: oklch(65% 0.2 140);
  --color-warning: oklch(70% 0.2 60);
  --color-error: oklch(60% 0.3 20);
  --radius-selector: 0.25rem;
  --radius-field: 0.25rem;
  --radius-box: 0.5rem;
}

/* Custom theme: Blood (dark, high contrast vivid red accents) */
@plugin "../vendor/daisyui-theme" {
  name: "blood";
  default: false;
  prefersdark: false;
  color-scheme: "dark";
  --color-base-100: oklch(15% 0.12 20);
  --color-base-200: oklch(22% 0.15 22);
  --color-base-300: oklch(30% 0.18 25);
  --color-base-content: oklch(90% 0.05 20);
  --color-primary: oklch(58% 0.4 25);
  --color-primary-content: oklch(98% 0 0);
  --color-secondary: oklch(45% 0.3 20);
  --color-secondary-content: oklch(98% 0 0);
  --color-accent: oklch(68% 0.45 28);
  --color-accent-content: oklch(98% 0 0);
  --color-neutral: oklch(20% 0.1 20);
  --color-neutral-content: oklch(85% 0.05 20);
  --color-info: oklch(60% 0.15 200);
  --color-success: oklch(65% 0.2 140);
  --color-warning: oklch(70% 0.2 60);
  --color-error: oklch(60% 0.3 20);
  --radius-selector: 0.25rem;
  --radius-field: 0.25rem;
  --radius-box: 0.5rem;
}

/* Preserve LiveView custom variants */
@custom-variant phx-click-loading (.phx-click-loading&, .phx-click-loading &);
@custom-variant phx-submit-loading (.phx-submit-loading&, .phx-submit-loading &);
@custom-variant phx-change-loading (.phx-change-loading&, .phx-change-loading &);

/* Make LiveView wrapper divs transparent for layout */
[data-phx-session], [data-phx-teleported-src] { display: contents }

/* Self-hosted Inter font */
@font-face {
  font-family: "Inter";
  src: url("/fonts/Inter-Variable.woff2") format("woff2");
  font-weight: 100 900;
  font-display: swap;
}

/* Global typography */
body {
  font-family: "Inter", sans-serif;
  -webkit-font-smoothing: antialiased;
  -moz-osx-font-smoothing: grayscale;
}

/* Word highlighting (uses DaisyUI 5 semantic color vars) */
.word-active {
  color: var(--color-base-content);
  background: oklch(from var(--color-primary) l c h / 20%);
  border-radius: 3px;
  padding: 1px 2px;
}

.word-spoken {
  color: oklch(from var(--color-base-content) l c h / 40%);
}

/* Reduced motion */
@media (prefers-reduced-motion: reduce) {
  * {
    animation-duration: 0.01ms !important;
    transition-duration: 0.01ms !important;
    scroll-behavior: auto !important;
  }
}

/* Skeleton shimmer */
@keyframes shimmer {
  0% { background-position: -200% 0; }
  100% { background-position: 200% 0; }
}

.skeleton-shimmer {
  background: linear-gradient(90deg, var(--color-base-200) 25%, var(--color-base-300) 50%, var(--color-base-200) 75%);
  background-size: 200% 100%;
  animation: shimmer 1.5s infinite;
}
```

Note: The old `@custom-variant dark` (hardcoded to `data-theme=dark`) is removed — with multiple dark themes, rely on each theme's `color-scheme: "dark"` declaration. The old `@plugin "../vendor/daisyui-theme"` blocks for "dark" and "light" are replaced by the vampire and blood themes above; the built-in `dark` and `light` themes are included via `themes: true`.

- [ ] **Step 3: Create theme.js hook**

```javascript
// apps/readaloud_web/assets/js/hooks/theme.js
// Theme persistence is handled by the inline <script> in root.html.heex
// (restores before first paint + listens for phx:set_theme events).
// This hook is mounted on an element inside the LiveView (e.g., the sidebar)
// to handle the initial theme-modal open via JS commands.

const ThemeHook = {
  mounted() {
    // The theme modal uses the native <dialog> API via JS.exec("data-show"),
    // so no additional JS is needed for opening/closing.
    // Theme selection is handled server-side (set_theme event → push_event).
  }
};

export default ThemeHook;
```

Note: The heavy lifting for theme persistence is in the root layout inline `<script>`: it restores from localStorage before first paint and listens for `phx:set_theme` events pushed by LiveView. The ThemeHook is kept minimal — it exists mainly as a mount point. Each LiveView handles `set_theme` events by calling `push_event(socket, "set_theme", %{theme: theme})`.

- [ ] **Step 4: Create ThemeSelector component**

```elixir
# apps/readaloud_web/lib/readaloud_web_web/components/theme_selector.ex
defmodule ReadaloudWebWeb.ThemeSelector do
  use Phoenix.Component

  @dark_themes ~w(dark dracula night coffee dim sunset abyss vampire blood)
  @light_themes ~w(light cupcake bumblebee emerald corporate retro cyberpunk valentine garden lofi pastel fantasy wireframe cmyk autumn acid lemonade nord silk)

  def theme_modal(assigns) do
    assigns =
      assigns
      |> assign(:dark_themes, @dark_themes)
      |> assign(:light_themes, @light_themes)

    ~H"""
    <dialog id="theme-modal" class="modal">
      <div class="modal-box max-w-md">
        <div class="flex justify-between items-center mb-4">
          <h3 class="font-bold text-lg">Choose Theme</h3>
          <form method="dialog"><button class="btn btn-ghost btn-sm btn-circle">✕</button></form>
        </div>

        <div class="mb-4">
          <div class="text-xs uppercase tracking-widest text-base-content/50 mb-2">Dark Themes</div>
          <div class="grid grid-cols-3 gap-2">
            <button :for={theme <- @dark_themes} phx-click="set_theme" phx-value-theme={theme}
              class="btn btn-sm btn-ghost justify-start gap-2">
              <div class="flex gap-0.5">
                <div class="w-2 h-2 rounded-full" data-theme={theme} style="background: var(--color-base-100)"></div>
                <div class="w-2 h-2 rounded-full" data-theme={theme} style="background: var(--color-primary)"></div>
                <div class="w-2 h-2 rounded-full" data-theme={theme} style="background: var(--color-secondary)"></div>
                <div class="w-2 h-2 rounded-full" data-theme={theme} style="background: var(--color-accent)"></div>
              </div>
              <span class="text-xs capitalize"><%= theme %></span>
            </button>
          </div>
        </div>

        <div>
          <div class="text-xs uppercase tracking-widest text-base-content/50 mb-2">Light Themes</div>
          <div class="grid grid-cols-3 gap-2">
            <button :for={theme <- @light_themes} phx-click="set_theme" phx-value-theme={theme}
              class="btn btn-sm btn-ghost justify-start gap-2">
              <div class="flex gap-0.5">
                <div class="w-2 h-2 rounded-full" data-theme={theme} style="background: var(--color-base-100)"></div>
                <div class="w-2 h-2 rounded-full" data-theme={theme} style="background: var(--color-primary)"></div>
                <div class="w-2 h-2 rounded-full" data-theme={theme} style="background: var(--color-secondary)"></div>
                <div class="w-2 h-2 rounded-full" data-theme={theme} style="background: var(--color-accent)"></div>
              </div>
              <span class="text-xs capitalize"><%= theme %></span>
            </button>
          </div>
        </div>
      </div>
      <form method="dialog" class="modal-backdrop"><button>close</button></form>
    </dialog>
    """
  end
end
```

- [ ] **Step 5: Register ThemeHook in app.js**

In `apps/readaloud_web/assets/js/app.js`, add:

```javascript
import ThemeHook from "./hooks/theme"

// In the Hooks object:
let Hooks = { ScrollTracker, AudioPlayer, ThemeHook }
```

- [ ] **Step 6: Update root layout with theme support and PWA meta**

Full rewrite of `apps/readaloud_web/lib/readaloud_web_web/components/layouts/root.html.heex` — add `data-theme` attribute on `<html>`, meta tags for PWA, Inter font `@font-face` reference, and the theme modal. The sidebar will be added in the next task.

```heex
<!DOCTYPE html>
<html lang="en" data-theme="dark">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <meta name="csrf-token" content={get_csrf_token()} />
    <meta name="theme-color" content="#6366f1" />
    <meta name="apple-mobile-web-app-capable" content="yes" />
    <link rel="manifest" href="/manifest.json" />
    <link rel="icon" type="image/png" href="/images/icon-192.png" />
    <link rel="apple-touch-icon" href="/images/icon-192.png" />
    <.live_title><%= assigns[:page_title] || "Readaloud" %></.live_title>
    <link phx-track-static rel="stylesheet" href={~p"/assets/app.css"} />
    <script defer phx-track-static type="text/javascript" src={~p"/assets/app.js"}></script>
    <script>
      // Restore theme before first paint to prevent flash
      (function() {
        var theme = localStorage.getItem("phx:theme");
        if (theme) document.documentElement.setAttribute("data-theme", theme);
      })();
      // Listen for LiveView theme-change push events (phx-hook can't be on <html>)
      window.addEventListener("phx:set_theme", (e) => {
        document.documentElement.setAttribute("data-theme", e.detail.theme);
        localStorage.setItem("phx:theme", e.detail.theme);
      });
    </script>
  </head>
  <body class="antialiased">
    <%= @inner_content %>
  </body>
</html>
```

Note: `phx-hook` does not work on `<html>` since it is outside the LiveView mount point. Theme switching uses `window.addEventListener("phx:set_theme", ...)` instead — LiveView's `push_event(socket, "set_theme", %{theme: theme})` dispatches to `phx:set_theme` on `window` automatically.

- [ ] **Step 7: Verify theme system works**

Run: `cd /home/noah/projects/readaloud && mix compile --warnings-as-errors && mix phx.server`
Navigate to `http://localhost:4000`. Verify:
- Page loads with dark theme
- No compilation errors
- Inter font loads from `/fonts/Inter-Variable.woff2`

- [ ] **Step 8: Commit**

```bash
cd /home/noah/projects/readaloud
git add apps/readaloud_web/priv/static/fonts/ apps/readaloud_web/assets/ apps/readaloud_web/lib/
git commit -m "feat: add theme system with Inter font, vampire/blood themes, and all DaisyUI themes"
```

---

### Task 5: Sidebar Navigation Component

**Files:**
- Create: `apps/readaloud_web/lib/readaloud_web_web/components/sidebar.ex`
- Create: `apps/readaloud_web/assets/js/hooks/sidebar.js`
- Modify: `apps/readaloud_web/lib/readaloud_web_web/components/layouts/app.html.heex`
- Modify: `apps/readaloud_web/lib/readaloud_web_web/components/layouts.ex`
- Modify: `apps/readaloud_web/assets/js/app.js`

- [ ] **Step 1: Create Sidebar component**

```elixir
# apps/readaloud_web/lib/readaloud_web_web/components/sidebar.ex
defmodule ReadaloudWebWeb.Sidebar do
  use Phoenix.Component
  use ReadaloudWebWeb, :html

  attr :active, :atom, required: true
  attr :task_count, :integer, default: 0

  def sidebar(assigns) do
    ~H"""
    <aside id="sidebar" phx-hook="SidebarHook"
      class="fixed left-0 top-0 h-full z-40 w-14 hover:w-[200px] transition-all duration-200
             bg-base-200/95 backdrop-blur-xl border-r border-base-content/6
             flex flex-col items-start overflow-hidden
             max-sm:translate-x-[-100%] max-sm:w-[200px]"
      data-expanded="false">

      <%!-- Logo --%>
      <div class="flex items-center gap-2.5 px-[9px] pt-3.5 pb-5 min-h-[60px]">
        <div class="w-9 h-9 min-w-9 rounded-[10px] bg-gradient-to-br from-indigo-500 to-violet-500
                    flex items-center justify-center">
          <.icon name="hero-headphones-solid" class="w-[18px] h-[18px] text-white" />
        </div>
        <span class="text-base font-bold tracking-tight whitespace-nowrap opacity-0
                     transition-opacity">Readaloud</span>
      </div>

      <%!-- Nav items --%>
      <.nav_item icon="hero-book-open" label="Library" href={~p"/"} active={@active == :library} />
      <.nav_item icon="hero-chart-bar" label="Tasks" href={~p"/tasks"} active={@active == :tasks} badge={@task_count} />

      <div class="flex-1" />

      <%!-- Bottom items --%>
      <button phx-click={JS.exec("data-show", to: "#theme-modal")}
        class="flex items-center gap-3 w-full px-2 py-2.5 mx-0 rounded-[10px] hover:bg-base-content/8 transition-colors"
        aria-label="Theme">
        <div class="w-10 h-10 min-w-10 flex items-center justify-center">
          <.icon name="hero-sun" class="w-[18px] h-[18px] text-base-content/50" />
        </div>
        <span class="text-sm text-base-content/60 whitespace-nowrap">Theme</span>
      </button>

      <div class="pb-3" />
    </aside>

    <%!-- Mobile hamburger --%>
    <button id="sidebar-toggle"
      class="sm:hidden fixed top-3 left-3 z-50 btn btn-ghost btn-sm btn-circle bg-base-200/80 backdrop-blur"
      aria-label="Menu">
      <.icon name="hero-bars-3" class="w-5 h-5" />
    </button>

    <%!-- Mobile backdrop --%>
    <div id="sidebar-backdrop" class="sm:hidden fixed inset-0 z-30 bg-black/50 hidden" />
    """
  end

  defp nav_item(assigns) do
    assigns = assign_new(assigns, :badge, fn -> nil end)

    ~H"""
    <.link navigate={@href}
      class={[
        "flex items-center gap-3 w-full px-2 py-1 mx-0 rounded-[10px] transition-colors",
        @active && "bg-primary/15",
        !@active && "hover:bg-base-content/8"
      ]}>
      <div class="w-10 h-10 min-w-10 flex items-center justify-center">
        <.icon name={@icon} class={["w-[18px] h-[18px]", @active && "text-primary", !@active && "text-base-content/50"]} />
      </div>
      <span class={["text-sm whitespace-nowrap", @active && "font-semibold text-primary", !@active && "text-base-content/60"]}>
        <%= @label %>
      </span>
      <span :if={@badge && @badge > 0}
        class="badge badge-sm badge-primary ml-auto"><%= @badge %></span>
    </.link>
    """
  end
end
```

- [ ] **Step 2: Create sidebar.js hook**

```javascript
// apps/readaloud_web/assets/js/hooks/sidebar.js
const SidebarHook = {
  mounted() {
    const sidebar = this.el;
    const toggle = document.getElementById("sidebar-toggle");
    const backdrop = document.getElementById("sidebar-backdrop");
    const labels = sidebar.querySelectorAll("span:not(.badge)");

    // Desktop: show labels when sidebar is hovered (expand on hover)
    sidebar.addEventListener("mouseenter", () => {
      labels.forEach(el => el.style.opacity = "1");
    });
    sidebar.addEventListener("mouseleave", () => {
      labels.forEach(el => el.style.opacity = "0");
    });

    // Mobile toggle
    if (toggle) {
      toggle.addEventListener("click", () => {
        const isOpen = !sidebar.classList.contains("max-sm:translate-x-[-100%]");
        if (isOpen) {
          sidebar.classList.add("max-sm:translate-x-[-100%]");
          backdrop.classList.add("hidden");
        } else {
          sidebar.classList.remove("max-sm:translate-x-[-100%]");
          backdrop.classList.remove("hidden");
          // Show labels when mobile menu opens
          labels.forEach(el => el.style.opacity = "1");
        }
      });
    }

    if (backdrop) {
      backdrop.addEventListener("click", () => {
        sidebar.classList.add("max-sm:translate-x-[-100%]");
        backdrop.classList.add("hidden");
      });
    }
  }
};

export default SidebarHook;
```

- [ ] **Step 3: Update app layout**

Rewrite the `app/1` function in `apps/readaloud_web/lib/readaloud_web_web/components/layouts.ex` (the app layout is defined inline, not as a separate `.heex` file):

```elixir
def app(assigns) do
  ~H"""
  <div id="app-shell" phx-hook="ThemeHook">
    <.sidebar :if={@active_nav != :reader} active={@active_nav} task_count={@task_count} />
    <ReadaloudWebWeb.ThemeSelector.theme_modal />

    <main class={[@active_nav != :reader && "sm:ml-14", "min-h-screen p-4 sm:p-6 lg:p-8"]}>
      <.flash_group flash={@flash} />
      {render_slot(@inner_block)}
    </main>
  </div>
  """
end
```

Note: The sidebar is conditionally hidden when `active_nav == :reader` (immersive mode). The `phx-hook="ThemeHook"` goes on the app shell div inside the LiveView, not on `<html>`.

- [ ] **Step 4: Update layouts.ex to pass sidebar assigns**

In `apps/readaloud_web/lib/readaloud_web_web/components/layouts.ex`, import the Sidebar module. Each LiveView will set `active_nav` and `task_count` in its `mount/3`:

```elixir
# In each LiveView's mount:
socket = assign(socket, active_nav: :library, task_count: ReadaloudWebWeb.LiveHelpers.active_task_count())
```

Create a shared helper module (NOT in the `live_view` quote block — `readaloud_web_web.ex` line 15 says "Do NOT define functions inside the quoted expressions"):

```elixir
# apps/readaloud_web/lib/readaloud_web_web/live_helpers.ex
defmodule ReadaloudWebWeb.LiveHelpers do
  @moduledoc "Shared helpers for all LiveViews."

  def active_task_count do
    import_count = ReadaloudImporter.list_tasks() |> Enum.count(& &1.status in ["pending", "processing"])
    audio_count = ReadaloudAudiobook.list_tasks() |> Enum.count(& &1.status in ["pending", "processing"])
    import_count + audio_count
  end

  def fetch_models do
    case ReadaloudTTS.list_models_and_voices() do
      {:ok, models} -> models
      {:error, _} -> []
    end
  end

  def default_model(book, models) do
    prefs = book.audio_preferences || %{}
    prefs["model"] || List.first(models)[:id] || ReadaloudTTS.Config.from_env().tts_model
  end

  def default_voice(book, models) do
    prefs = book.audio_preferences || %{}
    model_id = prefs["model"] || List.first(models)[:id]
    prefs["voice"] || get_in(Enum.find(models, & &1[:id] == model_id) || %{}, [:voices]) |> List.first() || ReadaloudTTS.Config.from_env().voice
  end
end
```

Add to the `live_view` quote block in `readaloud_web_web.ex`:
```elixir
import ReadaloudWebWeb.LiveHelpers
```

Note: This file also goes in the File Map as a new file to create.

- [ ] **Step 5: Register SidebarHook in app.js**

In `apps/readaloud_web/assets/js/app.js`:

```javascript
import SidebarHook from "./hooks/sidebar"

let Hooks = { ScrollTracker, AudioPlayer, ThemeHook, SidebarHook }
```

- [ ] **Step 6: Verify sidebar renders**

Run: `cd /home/noah/projects/readaloud && mix compile --warnings-as-errors && mix phx.server`
Navigate to `http://localhost:4000`. Verify:
- Sidebar icon rail visible on left (56px)
- Expands on hover to show labels
- Library nav item is active (highlighted)
- Theme button opens modal (even if styling isn't perfect yet)
- Mobile: hamburger shows, sidebar slides out

- [ ] **Step 7: Commit**

```bash
cd /home/noah/projects/readaloud
git add apps/readaloud_web/lib/ apps/readaloud_web/assets/
git commit -m "feat: add collapsible sidebar navigation with mobile hamburger menu"
```

---

## Chunk 2: Library & Book Detail Page Rewrites

### Task 6: Library Page Rewrite

**Files:**
- Modify: `apps/readaloud_library/lib/readaloud_library.ex`
- Modify: `apps/readaloud_web/lib/readaloud_web_web/live/library_live.ex`
- Create: `apps/readaloud_web/assets/js/hooks/drag_drop.js`
- Modify: `apps/readaloud_web/assets/js/app.js`

- [ ] **Step 1: Add search and sort functions to Library context**

In `apps/readaloud_library/lib/readaloud_library.ex`:

Note: `readaloud_library.ex` already has `import Ecto.Query` — add these functions to the existing module:

```elixir
def search_books(query_string) when is_binary(query_string) do
  # Escape SQL wildcards in user input to prevent unintended matches
  escaped = query_string |> String.replace("%", "\\%") |> String.replace("_", "\\_")
  pattern = "%#{escaped}%"

  from(b in Book,
    where: ilike(b.title, ^pattern) or ilike(b.author, ^pattern),
    order_by: [desc: b.inserted_at]
  )
  |> Repo.all()
end

def list_books_sorted(sort_by) do
  base = from(b in Book)

  query =
    case sort_by do
      "title" -> from(b in base, order_by: [asc: b.title])
      "author" -> from(b in base, order_by: [asc: b.author, asc: b.title])
      "added" -> from(b in base, order_by: [desc: b.inserted_at])
      _ ->
        # "recent" (default): sort by last reading activity, unread books at end by import date
        # Note: Cross-app join (Library → Reader). If this violates DDD boundaries,
        # consider having ReadaloudReader expose a `list_recently_read_book_ids/0` function
        # and sorting in-memory. For a single-user app this join is pragmatic.
        from(b in base,
          left_join: rp in ReadaloudReader.ReadingProgress, on: rp.book_id == b.id,
          order_by: [desc_nulls_last: rp.last_read_at, desc: b.inserted_at]
        )
    end

  Repo.all(query)
end

def update_book(%Book{} = book, attrs) do
  book
  |> Book.changeset(attrs)
  |> Repo.update()
end
```

Note: `update_book/2` is needed by Tasks 7 and 8 for saving audio preferences.

- [ ] **Step 2: Create drag_drop.js hook**

```javascript
// apps/readaloud_web/assets/js/hooks/drag_drop.js
const DragDropHook = {
  mounted() {
    const zone = this.el;
    const overlay = zone.querySelector("[data-drop-overlay]");

    ["dragenter", "dragover"].forEach(evt => {
      zone.addEventListener(evt, (e) => {
        e.preventDefault();
        if (overlay) overlay.classList.remove("hidden");
      });
    });

    ["dragleave", "drop"].forEach(evt => {
      zone.addEventListener(evt, (e) => {
        e.preventDefault();
        if (overlay) overlay.classList.add("hidden");
      });
    });

    zone.addEventListener("drop", (e) => {
      const files = e.dataTransfer.files;
      if (files.length > 0) {
        // Trigger the LiveView file input
        const input = zone.querySelector("input[type=file]");
        if (input) {
          const dt = new DataTransfer();
          for (const f of files) dt.items.add(f);
          input.files = dt.files;
          input.dispatchEvent(new Event("change", { bubbles: true }));
        }
      }
    });
  }
};

export default DragDropHook;
```

- [ ] **Step 3: Rewrite LibraryLive**

Full rewrite of `apps/readaloud_web/lib/readaloud_web_web/live/library_live.ex`. Key changes:

- Add `search` and `sort` assigns
- Handle `phx-change` on search input with debounce
- Handle `phx-click` on sort buttons
- Render rich book cards with cover images, badges, gradient placeholders
- Quick-resume on card click (navigate to reader at last chapter)
- Info icon for book detail
- Drag-and-drop zone wrapping the whole page
- Skeleton loading states
- PubSub subscription for import completion + cover resolution

The template should include:
- Search input + sort dropdown in header
- Responsive grid: `grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6`
- Each card: `aspect-[3/4]` with cover image or gradient background, gradient overlay, title/author text, badges
- Upload form (existing, enhanced with drag-drop)

```elixir
defmodule ReadaloudWebWeb.LibraryLive do
  use ReadaloudWebWeb, :live_view

  alias ReadaloudImporter.CoverResolver

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(ReadaloudLibrary.PubSub, "tasks:import")
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
     |> allow_upload(:file, accept: ~w(.epub .pdf), max_entries: 1, max_file_size: 100_000_000)}
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

  def handle_event("sort", %{"sort" => sort_by}, socket) do
    books = ReadaloudLibrary.list_books_sorted(sort_by)
    {:noreply, assign(socket, books: books, sort: sort_by, progress_map: build_progress_map(books))}
  end

  def handle_event("set_theme", %{"theme" => theme}, socket) do
    {:noreply, push_event(socket, "set_theme", %{theme: theme})}
  end

  # Preserve existing handlers from current LibraryLive:
  # - handle_event("validate", ...) — file upload validation (existing, keep unchanged)
  # - handle_event("import", ...) — file upload + import trigger (existing, update to show toast on completion/failure)
  # - handle_info({:import_complete, book}, ...) — PubSub handler (existing, update to refresh books list + show success toast)
  # - handle_info({:import_failed, reason}, ...) — show error toast with filename and reason, no auto-dismiss

  @impl true
  def handle_event("set_theme", %{"theme" => theme}, socket) do
    {:noreply, push_event(socket, "set_theme", %{theme: theme})}
  end

  @impl true
  def handle_event("search", %{"search" => query}, socket) do
    # ... as above
  end

  @impl true
  def handle_event("sort", %{"sort" => sort_by}, socket) do
    books = ReadaloudLibrary.list_books_sorted(sort_by)
    {:noreply,
     socket
     |> assign(books: books, sort: sort_by, progress_map: build_progress_map(books))
     |> push_event("persist_sort", %{sort: sort_by})}
  end

  # Private helpers

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
    # CoverResolver is created in Chunk 1, Task 3 — must be completed first
    ReadaloudImporter.CoverResolver.gradient_placeholder(book.title)
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
    # Count chapters that have been read based on reading progress
    # current_chapter_id gives us the furthest chapter reached
    case progress.current_chapter_id do
      nil -> 0
      ch_id ->
        chapters = ReadaloudLibrary.list_chapters(book.id)
        current = Enum.find(chapters, & &1.id == ch_id)
        if current, do: current.number, else: 0
    end
  end
end
```

The full HEEx template is extensive — implement the grid layout, card components, badges, search/sort bar, drag-drop overlay, and skeleton placeholders as described in the spec. Use `phx-click` with `JS.navigate` for card clicks.

- [ ] **Step 4: Add sort persistence to app.js and register DragDropHook**

In `app.js`, add:
```javascript
import DragDropHook from "./hooks/drag_drop"

let Hooks = { ScrollTracker, AudioPlayer, ThemeHook, SidebarHook, DragDropHook }

// Sort preference persistence (Library page)
window.addEventListener("phx:persist_sort", (e) => {
  localStorage.setItem("readaloud-library-sort", e.detail.sort);
});
```

In LibraryLive `mount/3`, read the saved sort preference on connect:
```elixir
sort = if connected?(socket) do
  # The client will send the saved sort via a hook or we default to "recent"
  "recent"  # Initial default; a small JS snippet sends the stored value on mount
end
```

Alternative: Add a `mounted` callback in a small LibraryHook that pushes the saved sort on connect:
```javascript
// In drag_drop.js or a new library.js hook:
mounted() {
  const savedSort = localStorage.getItem("readaloud-library-sort");
  if (savedSort) this.pushEvent("sort", { sort: savedSort });
}
```

- [ ] **Step 5: Verify library page**

Run: `cd /home/noah/projects/readaloud && mix phx.server`
Navigate to `http://localhost:4000`. Verify:
- Book cards render with 3:4 aspect ratio
- Gradient placeholders show for books without covers
- Cover images load for books with covers
- Search filters as you type
- Sort dropdown changes order
- Click card → reader
- Info icon → book detail
- Upload works (drag-drop and button)

- [ ] **Step 6: Commit**

```bash
cd /home/noah/projects/readaloud
git add apps/readaloud_library/lib/ apps/readaloud_web/lib/ apps/readaloud_web/assets/
git commit -m "feat: rewrite library page with rich cards, search, sort, and drag-drop import"
```

---

### Task 7: Book Detail Page Rewrite

**Files:**
- Modify: `apps/readaloud_web/lib/readaloud_web_web/live/book_live.ex`

- [ ] **Step 1: Rewrite BookLive**

Full rewrite of `apps/readaloud_web/lib/readaloud_web_web/live/book_live.ex`. Key changes:

- Book header with cover image, title, author, metadata badges
- Chapter list with word count, estimated reading time (word_count / 250), status icons
- Current chapter highlighting
- Batch audio generation panel (opened via "Generate Audio" button):
  - Selection modes: all, from current, individual checkboxes
  - Model/voice dropdowns populated from `ReadaloudTTS.list_models_and_voices/0`
  - "Generate Selected" button queues batch
- Delete book with confirmation modal
- Inline retry for failed chapter audio (red warning + "Retry" link)
- `set_theme` event handler (same as library)

```elixir
@impl true
def mount(%{"id" => book_id}, _session, socket) do
  book = ReadaloudLibrary.get_book!(book_id)
  chapters = ReadaloudLibrary.list_chapters(book_id)
  progress = ReadaloudReader.get_progress(book_id)
  audio_map = build_audio_map(chapters)
  models = fetch_models()  # from LiveHelpers (imported via readaloud_web_web.ex)

  if connected?(socket) do
    Phoenix.PubSub.subscribe(ReadaloudLibrary.PubSub, "tasks:audiobook:#{book_id}")
  end

  {:ok,
   socket
   |> assign(
     active_nav: :library,
     task_count: active_task_count(),  # from LiveHelpers
     book: book,
     chapters: chapters,
     progress: progress,
     audio_map: audio_map,
     models: models,
     selected_model: default_model(book, models),  # from LiveHelpers
     selected_voice: default_voice(book, models),  # from LiveHelpers
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

  # Save preferences to book
  ReadaloudLibrary.update_book(book, %{audio_preferences: %{"model" => model, "voice" => voice}})

  # Queue generation for each selected chapter
  for chapter_id <- selected do
    ReadaloudAudiobook.generate_for_chapter(book.id, chapter_id, model: model, voice: voice)
  end

  {:noreply, assign(socket, show_generate_panel: false)}
end

@impl true
def handle_event("select_all_chapters", _params, socket) do
  all_ids = socket.assigns.chapters |> Enum.map(& &1.id) |> MapSet.new()
  {:noreply, assign(socket, selected_chapters: all_ids)}
end

@impl true
def handle_event("select_from_current", _params, socket) do
  current_num = current_chapter_number(socket.assigns.progress, socket.assigns.chapters)  # defined below
  ids = socket.assigns.chapters |> Enum.filter(& &1.number >= current_num) |> Enum.map(& &1.id) |> MapSet.new()
  {:noreply, assign(socket, selected_chapters: ids)}
end

@impl true
def handle_event("toggle_chapter", %{"chapter-id" => ch_id}, socket) do
  ch_id = String.to_integer(ch_id)
  selected = socket.assigns.selected_chapters
  updated = if MapSet.member?(selected, ch_id), do: MapSet.delete(selected, ch_id), else: MapSet.put(selected, ch_id)
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
```

The `render/1` function template structure:

```heex
<div class="max-w-4xl mx-auto">
  <%!-- Back link --%>
  <.link navigate={~p"/"} class="flex items-center gap-1 text-sm text-base-content/60 hover:text-base-content mb-6">
    <.icon name="hero-arrow-left-mini" class="w-4 h-4" /> Back to Library
  </.link>

  <%!-- Book header: cover + info side by side (stacked on mobile) --%>
  <div class="flex flex-col sm:flex-row gap-6 mb-8">
    <img :if={cover_url(@book)} src={"/api/books/#{@book.id}/cover"} class="w-24 rounded-lg shadow" />
    <div :if={!cover_url(@book)} class="w-24 h-32 rounded-lg" style={"background: #{gradient_style(@book)}"} />
    <div class="flex-1">
      <h1 class="text-2xl font-bold tracking-tight"><%= @book.title %></h1>
      <p :if={@book.author} class="text-base-content/60 mt-1"><%= @book.author %></p>
      <div class="flex flex-wrap gap-2 mt-3">
        <span class="badge badge-outline"><%= length(@chapters) %> chapters</span>
        <span class="badge badge-outline"><%= progress_count(@progress, @book) %>/<%= length(@chapters) %> read</span>
        <span class="badge badge-outline"><%= audio_count(@audio_map) %>/<%= length(@chapters) %> audio</span>
      </div>
      <div class="flex flex-wrap gap-2 mt-4">
        <.link navigate={resume_path(@book, @progress)} class="btn btn-primary btn-sm">Continue Reading</.link>
        <button phx-click="toggle_generate_panel" class="btn btn-sm btn-outline">Generate Audio</button>
        <button phx-click="delete_book" data-confirm="This will remove the book and all generated audio. Continue?" class="btn btn-sm btn-ghost text-error">Delete Book</button>
      </div>
    </div>
  </div>

  <%!-- Batch generation panel (conditionally shown) --%>
  <div :if={@show_generate_panel} class="card bg-base-200 p-4 mb-6">
    <div class="flex flex-wrap gap-2 mb-3">
      <button phx-click="select_all_chapters" class="btn btn-xs">All chapters</button>
      <button phx-click="select_from_current" class="btn btn-xs">From current onward</button>
    </div>
    <div class="flex flex-wrap gap-3 mb-3">
      <select phx-change="select_model" class="select select-sm select-bordered">
        <option :for={m <- @models} value={m.id} selected={m.id == @selected_model}><%= m.id %></option>
      </select>
      <select phx-change="select_voice" class="select select-sm select-bordered">
        <%!-- Voices for selected model --%>
      </select>
    </div>
    <button phx-click="generate_batch" class="btn btn-primary btn-sm" disabled={MapSet.size(@selected_chapters) == 0}>
      Generate Selected (<%= MapSet.size(@selected_chapters) %>)
    </button>
  </div>

  <%!-- Chapter list --%>
  <div class="space-y-1">
    <div :for={ch <- @chapters} class={["flex items-center gap-3 p-3 rounded-lg", is_current?(ch, @progress) && "bg-primary/10"]}>
      <span class="text-sm font-mono text-base-content/40 w-8"><%= ch.number %></span>
      <.link navigate={~p"/books/#{@book.id}/read/#{ch.id}"} class="flex-1 text-sm hover:text-primary"><%= ch.title %></.link>
      <span class="text-xs text-base-content/40"><%= format_word_count(ch.word_count) %></span>
      <span class="text-xs text-base-content/40"><%= estimate_reading_time(ch.word_count) %></span>
      <.icon :if={Map.get(@audio_map, ch.id) == :ready} name="hero-speaker-wave" class="w-4 h-4 text-success" />
      <.icon :if={Map.get(@audio_map, ch.id) == :failed} name="hero-exclamation-triangle" class="w-4 h-4 text-error" />
      <button :if={Map.get(@audio_map, ch.id) == :failed} phx-click="retry_chapter_audio" phx-value-chapter-id={ch.id} class="text-xs text-primary hover:underline">Retry</button>
      <span :if={is_current?(ch, @progress)} class="badge badge-primary badge-xs">CURRENT</span>
      <input :if={@show_generate_panel && Map.get(@audio_map, ch.id) != :ready}
        type="checkbox" checked={MapSet.member?(@selected_chapters, ch.id)}
        phx-click="toggle_chapter" phx-value-chapter-id={ch.id} class="checkbox checkbox-xs checkbox-primary" />
    </div>
  </div>
</div>
```

Private helpers for the template:
```elixir
defp build_audio_map(chapters) do
  # Returns %{chapter_id => :ready | :generating | :failed | nil}
  chapter_ids = Enum.map(chapters, & &1.id)
  audios = ReadaloudAudiobook.list_chapter_audio_for_chapters(chapter_ids)
  tasks = ReadaloudAudiobook.list_tasks_for_chapters(chapter_ids)

  Enum.map(chapter_ids, fn id ->
    cond do
      Enum.any?(audios, & &1.chapter_id == id) -> {id, :ready}
      Enum.any?(tasks, & &1.chapter_id == id && &1.status == "failed") -> {id, :failed}
      Enum.any?(tasks, & &1.chapter_id == id && &1.status in ["pending", "processing"]) -> {id, :generating}
      true -> {id, nil}
    end
  end)
  |> Map.new()
end

defp current_chapter_number(nil, _chapters), do: 1
defp current_chapter_number(progress, chapters) do
  case Enum.find(chapters, & &1.id == progress.current_chapter_id) do
    nil -> 1
    ch -> ch.number
  end
end

defp is_current?(chapter, nil), do: false
defp is_current?(chapter, progress), do: chapter.id == progress.current_chapter_id

defp resume_path(book, nil), do: ~p"/books/#{book.id}"
defp resume_path(book, %{current_chapter_id: nil}), do: ~p"/books/#{book.id}"
defp resume_path(book, progress), do: ~p"/books/#{book.id}/read/#{progress.current_chapter_id}"

defp progress_count(nil, _book), do: 0
defp progress_count(progress, book), do: current_chapter_number(progress, ReadaloudLibrary.list_chapters(book.id))

defp audio_count(audio_map), do: Enum.count(audio_map, fn {_, v} -> v == :ready end)

defp format_word_count(nil), do: ""
defp format_word_count(count), do: "~#{div(count, 100) * 100} words"

defp estimate_reading_time(nil), do: ""
defp estimate_reading_time(count), do: "#{max(1, div(count, 250))} min"
```

Note: `ReadaloudAudiobook.list_chapter_audio_for_chapters/1` and `list_tasks_for_chapters/1` are new query functions that batch-fetch by chapter ID list. Add them to the audiobook context.

- [ ] **Step 2: Verify book detail page**

Run: `cd /home/noah/projects/readaloud && mix phx.server`
Navigate to a book detail page. Verify:
- Book header with cover image and metadata
- Chapter list with word counts and reading times
- "Generate Audio" opens selection panel
- Selection modes work (all, from current, individual)
- Delete button shows confirmation
- Retry link on failed chapters

- [ ] **Step 3: Commit**

```bash
cd /home/noah/projects/readaloud
git add apps/readaloud_web/lib/readaloud_web_web/live/book_live.ex
git commit -m "feat: rewrite book detail page with batch audio generation and chapter management"
```

---

## Chunk 3: Reader + Audio Player Merge

### Task 8: Route Merging & Immersive Reader Structure

**Files:**
- Delete: `apps/readaloud_web/lib/readaloud_web_web/live/player_live.ex`
- Modify: `apps/readaloud_web/lib/readaloud_web_web/router.ex`
- Modify: `apps/readaloud_web/lib/readaloud_web_web/live/reader_live.ex`
- Create: `apps/readaloud_web/assets/js/hooks/floating_pill.js`
- Create: `apps/readaloud_web/assets/js/hooks/reader_settings.js`
- Create: `apps/readaloud_web/assets/js/hooks/keyboard_shortcuts.js`

- [ ] **Step 1: Update router — remove /listen, add redirect**

In `apps/readaloud_web/lib/readaloud_web_web/router.ex`:

Remove the line:
```elixir
live "/books/:id/listen/:chapter_id", PlayerLive
```

Add a 301 redirect in the existing `AudioController` (simplest approach — no new modules):
```elixir
# In apps/readaloud_web/lib/readaloud_web_web/controllers/audio_controller.ex, add:
def listen_redirect(conn, %{"id" => id, "chapter_id" => chapter_id}) do
  conn
  |> put_status(301)
  |> redirect(to: ~p"/books/#{id}/read/#{chapter_id}")
end
```

In `router.ex`, add in the browser scope (before live routes):
```elixir
get "/books/:id/listen/:chapter_id", AudioController, :listen_redirect
```

- [ ] **Step 2: Delete PlayerLive**

```bash
rm apps/readaloud_web/lib/readaloud_web_web/live/player_live.ex
```

- [ ] **Step 3: Create floating_pill.js hook**

```javascript
// apps/readaloud_web/assets/js/hooks/floating_pill.js
const FloatingPillHook = {
  mounted() {
    this.pill = this.el;
    this.hideTimeout = null;
    this.visible = false;
    const isMobile = window.innerWidth < 640;

    if (isMobile) {
      // Mobile: tap top 80px to toggle
      document.addEventListener("click", (e) => {
        if (e.clientY < 80 && !this.pill.contains(e.target)) {
          this.toggle();
        }
      });
      // Auto-hide after 5s
      this.pill.addEventListener("click", () => this.resetTimer(5000));
    } else {
      // Desktop: show on mouse movement, hide after 3s
      document.addEventListener("mousemove", () => {
        this.show();
        this.resetTimer(3000);
      });
      // Keep visible while interacting with pill
      this.pill.addEventListener("mouseenter", () => clearTimeout(this.hideTimeout));
      this.pill.addEventListener("mouseleave", () => this.resetTimer(3000));
    }

    // Start hidden
    this.hide();
  },

  show() {
    this.pill.classList.remove("opacity-0", "pointer-events-none");
    this.pill.classList.add("opacity-100");
    this.visible = true;
  },

  hide() {
    this.pill.classList.add("opacity-0", "pointer-events-none");
    this.pill.classList.remove("opacity-100");
    this.visible = false;
  },

  toggle() {
    this.visible ? this.hide() : this.show();
    if (this.visible) this.resetTimer(5000);
  },

  resetTimer(ms) {
    clearTimeout(this.hideTimeout);
    this.hideTimeout = setTimeout(() => this.hide(), ms);
  }
};

export default FloatingPillHook;
```

- [ ] **Step 4: Create reader_settings.js hook**

```javascript
// apps/readaloud_web/assets/js/hooks/reader_settings.js
const SETTINGS_KEY = "readaloud-reader-settings";

const defaults = {
  fontFamily: "serif",
  fontSize: 18,
  lineHeight: 1.8,
  maxWidth: 700,
  autoScroll: true,
  autoNextChapter: false
};

const ReaderSettingsHook = {
  mounted() {
    this.settings = { ...defaults, ...JSON.parse(localStorage.getItem(SETTINGS_KEY) || "{}") };
    this.applySettings();

    this.handleEvent("update_reader_setting", ({ key, value }) => {
      this.settings[key] = value;
      localStorage.setItem(SETTINGS_KEY, JSON.stringify(this.settings));
      this.applySettings();
    });
  },

  applySettings() {
    const content = document.getElementById("reader-content");
    if (!content) return;

    const fonts = { serif: "Georgia, serif", sans: "'Inter', sans-serif", mono: "ui-monospace, monospace" };
    content.style.fontFamily = fonts[this.settings.fontFamily] || fonts.serif;
    content.style.fontSize = this.settings.fontSize + "px";
    content.style.lineHeight = this.settings.lineHeight;
    content.style.maxWidth = this.settings.maxWidth + "px";
  }
};

export default ReaderSettingsHook;
```

- [ ] **Step 5: Create keyboard_shortcuts.js hook**

```javascript
// apps/readaloud_web/assets/js/hooks/keyboard_shortcuts.js
const SPEEDS = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

const KeyboardShortcutsHook = {
  mounted() {
    this.handleKeydown = (e) => {
      // Skip if typing in an input
      if (e.target.tagName === "INPUT" || e.target.tagName === "TEXTAREA" || e.target.isContentEditable) return;

      switch (e.key) {
        case " ":
          e.preventDefault();
          this.pushEvent("toggle_playback");
          break;
        case "ArrowLeft":
          e.preventDefault();
          this.pushEvent("prev_chapter");
          break;
        case "ArrowRight":
          e.preventDefault();
          this.pushEvent("next_chapter");
          break;
        case "+": case "=":
          e.preventDefault();
          this.pushEvent("change_speed", { direction: "up" });
          break;
        case "-":
          e.preventDefault();
          this.pushEvent("change_speed", { direction: "down" });
          break;
        case "Escape":
          e.preventDefault();
          this.pushEvent("toggle_pill");
          break;
        case "m":
          e.preventDefault();
          this.pushEvent("toggle_mute");
          break;
      }
    };

    window.addEventListener("keydown", this.handleKeydown);
  },

  destroyed() {
    window.removeEventListener("keydown", this.handleKeydown);
  }
};

export default KeyboardShortcutsHook;
```

- [ ] **Step 6: Rewrite ReaderLive — merged reader + player**

Full rewrite of `apps/readaloud_web/lib/readaloud_web_web/live/reader_live.ex`. This is the largest single change. Key structure:

```elixir
defmodule ReadaloudWebWeb.ReaderLive do
  use ReadaloudWebWeb, :live_view

  @impl true
  def mount(%{"id" => book_id, "chapter_id" => chapter_id}, _session, socket) do
    book = ReadaloudLibrary.get_book!(book_id)
    chapter = ReadaloudLibrary.get_chapter!(chapter_id)
    chapters = ReadaloudLibrary.list_chapters(book_id)
    content = ReadaloudLibrary.get_chapter_content(chapter)
    progress = ReadaloudReader.get_progress(book_id)
    audio = ReadaloudAudiobook.get_chapter_audio(chapter_id)
    models = ReadaloudTTS.list_models_and_voices() |> elem(1) |> then(& &1 || [])

    # Determine audio state
    audio_state = determine_audio_state(chapter_id, audio)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(ReadaloudLibrary.PubSub, "tasks:audiobook:#{book_id}")
      # Update progress to current chapter
      ReadaloudReader.upsert_progress(%{book_id: book_id, current_chapter_id: chapter_id})
    end

    {:ok,
     socket
     |> assign(
       # No sidebar in reader — immersive mode
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
       page_title: "#{chapter.title} — #{book.title}"
     )}
  end

  # Audio states: :none, :generating, :ready
  defp determine_audio_state(chapter_id, audio) do
    cond do
      audio != nil -> :ready
      has_active_task?(chapter_id) -> :generating
      true -> :none
    end
  end

  # Event handlers for keyboard shortcuts
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

    {:noreply, assign(socket, audio_state: :generating)}
  end

  @impl true
  def handle_event("cancel_generation", _params, socket) do
    cancel_active_tasks(socket.assigns.chapter.id)
    {:noreply, assign(socket, audio_state: :none)}
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

  # PubSub handler: audio generation completed
  @impl true
  def handle_info({:task_updated, task}, socket) do
    if task.chapter_id == socket.assigns.chapter.id and task.status == "completed" do
      audio = ReadaloudAudiobook.get_chapter_audio(socket.assigns.chapter.id)
      {:noreply, assign(socket, audio: audio, audio_state: :ready)}
    else
      {:noreply, socket}
    end
  end

  # Private helpers

  defp prev_chapter(current, chapters) do
    idx = Enum.find_index(chapters, & &1.id == current.id)
    if idx && idx > 0, do: Enum.at(chapters, idx - 1), else: nil
  end

  defp next_chapter(current, chapters) do
    idx = Enum.find_index(chapters, & &1.id == current.id)
    if idx && idx < length(chapters) - 1, do: Enum.at(chapters, idx + 1), else: nil
  end

  defp has_active_task?(chapter_id) do
    ReadaloudAudiobook.list_tasks()
    |> Enum.any?(& &1.chapter_id == chapter_id && &1.status in ["pending", "processing"])
  end

  defp cancel_active_tasks(chapter_id) do
    ReadaloudAudiobook.list_tasks()
    |> Enum.filter(& &1.chapter_id == chapter_id && &1.status in ["pending", "processing"])
    |> Enum.each(fn task ->
      # Find and cancel the associated Oban job
      import Ecto.Query
      case ReadaloudLibrary.Repo.one(from j in Oban.Job, where: fragment("?->>'task_id' = ?", j.args, ^to_string(task.id)), where: j.state in ["available", "executing"], limit: 1) do
        nil -> :ok
        job -> Oban.cancel_job(job.id)
      end
    end)
  end

  defp chapter_index(chapter, chapters) do
    Enum.find_index(chapters, & &1.id == chapter.id) || 0
  end

  defp chapter_progress_pct(chapter, chapters, audio_state, audio) do
    # When audio playing: audio position / duration. Otherwise: scroll position.
    # Scroll position comes from the assign; audio position from the JS hook.
    # This is a rough server-side approximation; the pill JS can show real-time client-side.
    idx = chapter_index(chapter, chapters)
    "#{round((idx + 1) / max(length(chapters), 1) * 100)}%"
  end
end
```

The `render/1` template structure (inline `render/1` function):

```heex
<div id="reader-root" phx-hook="KeyboardShortcutsHook" class="min-h-screen bg-base-100">
  <%!-- 1. Floating pill (immersive nav) --%>
  <div id="floating-pill" phx-hook="FloatingPillHook"
    class="fixed top-4 left-1/2 -translate-x-1/2 z-50 flex items-center gap-3
           bg-base-200/90 backdrop-blur-xl rounded-full px-4 py-2 shadow-lg border border-base-content/6
           opacity-0 pointer-events-none transition-opacity duration-200">
    <.link navigate={~p"/"} class="btn btn-ghost btn-xs btn-circle"><.icon name="hero-arrow-left" class="w-4 h-4" /></.link>
    <.link navigate={~p"/"} class="btn btn-ghost btn-xs btn-circle"><.icon name="hero-book-open" class="w-4 h-4" /></.link>
    <span class="text-xs text-base-content/60">
      Ch <%= chapter_index(@chapter, @chapters) + 1 %> / <%= length(@chapters) %>
    </span>
    <button phx-click={JS.toggle(to: "#reader-settings")} class="btn btn-ghost btn-xs btn-circle">
      <.icon name="hero-cog-6-tooth" class="w-4 h-4" />
    </button>
  </div>

  <%!-- Reader settings popover --%>
  <div id="reader-settings" class="fixed top-16 right-4 z-50 hidden
       bg-base-200 rounded-xl shadow-xl border border-base-content/10 p-4 w-72">
    <%!-- Font family, size, line height, width sliders, auto-scroll toggle, auto-next toggle --%>
    <%!-- Each control uses phx-change to push "update_reader_setting" events --%>
  </div>

  <%!-- 2. Reading area --%>
  <div id="reader-content" phx-hook="ReaderSettingsHook"
    class="max-w-[700px] mx-auto px-4 pt-16 pb-32"
    phx-hook="ScrollTracker" data-audio-playing={@audio_state == :ready}>

    <%!-- Loading skeleton (shown before content arrives) --%>
    <div :if={!@content} class="space-y-4 animate-pulse">
      <div :for={_ <- 1..8} class="skeleton-shimmer h-4 rounded" style={"width: #{Enum.random(60..95)}%"} />
    </div>

    <%!-- Chapter title --%>
    <div :if={@content} class="text-xs uppercase tracking-widest text-base-content/40 mb-6"><%= @chapter.title %></div>

    <%!-- Chapter content: with word spans when audio ready, plain HTML otherwise --%>
    <article :if={@content && @audio_state == :ready} class="prose prose-lg">
      <%= raw(prepare_text_with_spans(@content, @audio)) %>
    </article>
    <article :if={@content && @audio_state != :ready} class="prose prose-lg">
      <%= raw(@content) %>
    </article>
  </div>

  <%!-- Re-sync button (shown when user manually scrolls during playback) --%>
  <button id="resync-btn" class="fixed bottom-24 right-4 z-40 btn btn-sm btn-primary shadow-lg hidden">
    <.icon name="hero-arrow-down" class="w-4 h-4" /> Re-sync
  </button>

  <%!-- 3. Bottom bar: three states --%>
  <%!-- State 1: No audio --%>
  <div :if={@audio_state == :none}
    class="fixed bottom-0 inset-x-0 z-40 bg-base-200/95 backdrop-blur-xl border-t border-base-content/6 px-4 py-3">
    <div class="max-w-4xl mx-auto flex items-center gap-4">
      <.icon name="hero-headphones" class="w-6 h-6 text-base-content/40" />
      <div class="flex-1">
        <div class="text-sm font-medium">Listen to Audiobook</div>
        <div class="text-xs text-base-content/50">Generate an audiobook version of this chapter</div>
      </div>
      <%!-- Desktop: inline dropdowns. Mobile: "Voice Settings" button opens bottom sheet --%>
      <div class="hidden sm:flex items-center gap-2">
        <select phx-change="select_model" class="select select-xs select-bordered">
          <option :for={m <- @models} value={m.id} selected={m.id == @selected_model}><%= m.id %></option>
        </select>
        <select phx-change="select_voice" class="select select-xs select-bordered">
          <%!-- voices for selected model --%>
        </select>
      </div>
      <button phx-click="generate_audio" class="btn btn-primary btn-sm">Generate Audio</button>
    </div>
  </div>

  <%!-- State 2: Generating --%>
  <div :if={@audio_state == :generating}
    class="fixed bottom-0 inset-x-0 z-40 bg-base-200/95 backdrop-blur-xl border-t border-base-content/6 px-4 py-3">
    <div class="max-w-4xl mx-auto flex items-center gap-4">
      <.icon name="hero-arrow-path" class="w-6 h-6 animate-spin text-primary" />
      <div class="flex-1">
        <div class="text-sm font-medium">Generating Audio...</div>
        <div class="text-xs text-base-content/50">You can keep reading while this runs</div>
        <progress class="progress progress-primary w-full mt-1" value={@generation_progress || 0} max="100" />
      </div>
      <button phx-click="cancel_generation" class="btn btn-ghost btn-sm">Cancel</button>
    </div>
  </div>

  <%!-- State 3: Audio ready — full player --%>
  <div :if={@audio_state == :ready} id="audio-player" phx-hook="AudioPlayer"
    data-audio-url={"/api/chapters/#{@chapter.id}/audio"}
    data-timings-url={"/api/chapters/#{@chapter.id}/timings"}
    class="fixed bottom-0 inset-x-0 z-40 bg-base-200/95 backdrop-blur-xl border-t border-base-content/6">
    <%!-- Scrubber, controls, time, volume, speed — rendered by AudioPlayer hook --%>
    <%!-- Collapsed state: thin 36px bar with play/pause + progress + time --%>
    <%!-- Expanded state: full controls with skip, volume, speed dropdown --%>
  </div>
</div>
```

Port the `prepare_text_with_spans/2` function from `PlayerLive` (wraps each word in `<span data-word-index="N" class="word">`) before deleting that file.

**Missing spec features addressed in the template:**
- **Loading skeleton:** placeholder bars shown via `:if={!@content}`
- **Click-to-seek:** handled in `audio_player.js` — each `.word` span gets a click listener that seeks to `data-word-index`'s timestamp
- **Auto-advance:** handled in `audio_player.js` — on `audio.ended`, push `"next_chapter"` event if auto-next is enabled in settings
- **Skip back/forward 10s:** handled in `audio_player.js` — buttons call `audio.currentTime += 10` / `-= 10`

- [ ] **Step 7: Register all new hooks in app.js**

```javascript
import FloatingPillHook from "./hooks/floating_pill"
import ReaderSettingsHook from "./hooks/reader_settings"
import KeyboardShortcutsHook from "./hooks/keyboard_shortcuts"

let Hooks = {
  ScrollTracker, AudioPlayer, ThemeHook, SidebarHook,
  DragDropHook, FloatingPillHook, ReaderSettingsHook, KeyboardShortcutsHook
}
```

- [ ] **Step 8: Verify merged reader**

Run: `cd /home/noah/projects/readaloud && mix compile --warnings-as-errors && mix phx.server`
Navigate to a chapter. Verify:
- No sidebar (immersive mode)
- Floating pill appears on mouse movement, hides after 3s
- Chapter content renders
- Bottom bar shows correct state (generate/generating/player)
- Keyboard shortcuts work (Space, arrows, Escape)
- Settings popover opens from gear icon
- Font/size/width changes apply immediately

- [ ] **Step 9: Commit**

```bash
cd /home/noah/projects/readaloud
git add -A
git commit -m "feat: merge reader and player into single immersive view with floating controls"
```

---

### Task 9: Audio Player Enhancements (Collapsible, Re-sync, Persistence)

**Files:**
- Modify: `apps/readaloud_web/assets/js/hooks/audio_player.js`
- Modify: `apps/readaloud_web/assets/js/hooks/scroll_tracker.js`

- [ ] **Step 1: Rewrite audio_player.js**

Major rewrite of `apps/readaloud_web/assets/js/hooks/audio_player.js`. Key additions:

- **Collapsible state**: read/write `readaloud-player-collapsed` in localStorage. On mobile, default to collapsed. Chevron toggle expands/collapses the controls.
- **Speed persistence**: read/write `readaloud-playback-speed` in localStorage. Apply on mount. Speed dropdown popover with 7 preset values.
- **Volume persistence**: read/write `readaloud-volume` in localStorage. Apply on mount.
- **Touch support**: progress scrubber handles `touchstart`/`touchmove`/`touchend` alongside mouse events.
- **Re-sync button**: when user scrolls manually during playback, set `autoScrollPaused = true`. Show a "Re-sync" button (pushed as a LiveView event or DOM manipulation). Clicking re-syncs. Auto re-enables when highlighted word scrolls into viewport (use `IntersectionObserver`).
- **Word highlighting**: use `.word-active` and `.word-spoken` CSS classes instead of `.active`. Apply to all words before and including current index.

The hook structure:

```javascript
const SPEEDS = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

const AudioPlayerHook = {
  mounted() {
    this.audio = new Audio(this.el.dataset.audioUrl);
    this.collapsed = localStorage.getItem("readaloud-player-collapsed") === "true";
    this.audio.playbackRate = parseFloat(localStorage.getItem("readaloud-playback-speed") || "1.0");
    this.audio.volume = parseFloat(localStorage.getItem("readaloud-volume") || "1.0");
    this.autoScrollPaused = false;
    this.timings = [];
    this.currentWordIndex = -1;

    // Fetch word timings
    if (this.el.dataset.timingsUrl) {
      fetch(this.el.dataset.timingsUrl)
        .then(r => r.json())
        .then(data => { this.timings = data.timings || []; });
    }

    // Apply initial collapsed state
    if (this.collapsed) this.el.classList.add("collapsed");

    // --- Timeupdate: word highlighting + progress reporting ---
    this.audio.addEventListener("timeupdate", () => {
      const ms = this.audio.currentTime * 1000;
      this.pushEvent("audio_position", { position_ms: Math.round(ms) });
      this.highlightWord(ms);
    });

    // --- Binary search for current word (existing algorithm) ---
    // Uses this.timings array of {start_ms, end_ms} per word index.
    // Applies .word-active to current word, .word-spoken to prior words.

    // --- Click-to-seek on word spans ---
    document.querySelectorAll("[data-word-index]").forEach(el => {
      el.addEventListener("click", () => {
        const idx = parseInt(el.dataset.wordIndex);
        if (this.timings[idx]) {
          this.audio.currentTime = this.timings[idx].start_ms / 1000;
          if (this.audio.paused) this.audio.play();
        }
      });
    });

    // --- Auto-advance to next chapter on audio end ---
    this.audio.addEventListener("ended", () => {
      const settings = JSON.parse(localStorage.getItem("readaloud-reader-settings") || "{}");
      if (settings.autoNextChapter) {
        this.pushEvent("next_chapter", {});
      }
    });

    // --- Re-sync with IntersectionObserver ---
    this.resyncObserver = null;
    window.addEventListener("manual-scroll", () => {
      if (!this.audio.paused) {
        this.autoScrollPaused = true;
        document.getElementById("resync-btn")?.classList.remove("hidden");
      }
    });
    document.getElementById("resync-btn")?.addEventListener("click", () => {
      this.autoScrollPaused = false;
      document.getElementById("resync-btn")?.classList.add("hidden");
      this.scrollToCurrentWord();
    });

    // --- Collapsible toggle ---
    this.el.querySelector("[data-collapse-toggle]")?.addEventListener("click", () => {
      this.collapsed = !this.collapsed;
      this.el.classList.toggle("collapsed", this.collapsed);
      localStorage.setItem("readaloud-player-collapsed", this.collapsed);
    });

    // --- Speed dropdown ---
    this.el.querySelectorAll("[data-speed]").forEach(btn => {
      btn.addEventListener("click", () => {
        this.audio.playbackRate = parseFloat(btn.dataset.speed);
        localStorage.setItem("readaloud-playback-speed", btn.dataset.speed);
      });
    });

    // --- Volume slider ---
    this.el.querySelector("[data-volume-slider]")?.addEventListener("input", (e) => {
      this.audio.volume = e.target.value;
      localStorage.setItem("readaloud-volume", e.target.value);
    });

    // --- Skip back/forward 10s ---
    this.el.querySelector("[data-skip-back]")?.addEventListener("click", () => {
      this.audio.currentTime = Math.max(0, this.audio.currentTime - 10);
    });
    this.el.querySelector("[data-skip-forward]")?.addEventListener("click", () => {
      this.audio.currentTime = Math.min(this.audio.duration, this.audio.currentTime + 10);
    });

    // --- Touch support on scrubber ---
    const scrubber = this.el.querySelector("[data-scrubber]");
    if (scrubber) {
      const seek = (e) => {
        const rect = scrubber.getBoundingClientRect();
        const clientX = e.touches ? e.touches[0].clientX : e.clientX;
        const pct = Math.max(0, Math.min(1, (clientX - rect.left) / rect.width));
        this.audio.currentTime = pct * this.audio.duration;
      };
      scrubber.addEventListener("mousedown", (e) => { seek(e); document.addEventListener("mousemove", seek); });
      scrubber.addEventListener("touchstart", (e) => { seek(e); document.addEventListener("touchmove", seek); }, { passive: true });
      document.addEventListener("mouseup", () => document.removeEventListener("mousemove", seek));
      document.addEventListener("touchend", () => document.removeEventListener("touchmove", seek));
    }

    // --- LiveView event handlers ---
    this.handleEvent("toggle_audio", () => {
      this.audio.paused ? this.audio.play() : this.audio.pause();
    });
    this.handleEvent("toggle_mute", () => {
      this.audio.muted = !this.audio.muted;
    });
    this.handleEvent("change_speed", ({ direction }) => {
      const current = SPEEDS.indexOf(this.audio.playbackRate);
      const next = direction === "up" ? Math.min(current + 1, SPEEDS.length - 1) : Math.max(current - 1, 0);
      this.audio.playbackRate = SPEEDS[next];
      localStorage.setItem("readaloud-playback-speed", SPEEDS[next]);
    });
    this.handleEvent("toggle_pill", () => {
      // Delegated to FloatingPillHook via CustomEvent
      window.dispatchEvent(new CustomEvent("toggle-pill"));
    });
  },

  highlightWord(ms) {
    // Binary search for the word index at the given timestamp
    // (port existing logic from current audio_player.js)
    let lo = 0, hi = this.timings.length - 1, idx = -1;
    while (lo <= hi) {
      const mid = (lo + hi) >> 1;
      if (this.timings[mid].start_ms <= ms) { idx = mid; lo = mid + 1; }
      else { hi = mid - 1; }
    }
    if (idx === this.currentWordIndex) return;
    this.currentWordIndex = idx;

    document.querySelectorAll("[data-word-index]").forEach(el => {
      const i = parseInt(el.dataset.wordIndex);
      el.classList.toggle("word-active", i === idx);
      el.classList.toggle("word-spoken", i < idx);
    });

    if (!this.autoScrollPaused) this.scrollToCurrentWord();
  },

  scrollToCurrentWord() {
    const active = document.querySelector(".word-active");
    if (active) {
      window.dispatchEvent(new CustomEvent("auto-scroll-start"));
      active.scrollIntoView({ behavior: "smooth", block: "center" });
      setTimeout(() => window.dispatchEvent(new CustomEvent("auto-scroll-end")), 500);
    }
  },

  destroyed() {
    this.audio.pause();
    this.audio = null;
  }
};
```

- [ ] **Step 2: Update scroll_tracker.js for re-sync**

**Additive changes** to the existing `scroll_tracker.js` — preserve all existing scroll position persistence logic and add these lines inside the existing `mounted()`:

```javascript
// Add to existing ScrollTrackerHook.mounted() — DO NOT replace existing scroll persistence logic

// Detect manual scroll during audio playback
let isAutoScrolling = false;

this.el.addEventListener("scroll", () => {
  if (!isAutoScrolling && this.el.dataset.audioPlaying === "true") {
    // User scrolled manually — notify audio player to pause auto-scroll
    window.dispatchEvent(new CustomEvent("manual-scroll"));
  }
}, { passive: true });

// Allow audio player to flag auto-scroll operations so we don't false-positive
window.addEventListener("auto-scroll-start", () => { isAutoScrolling = true; });
window.addEventListener("auto-scroll-end", () => { isAutoScrolling = false; });
```

- [ ] **Step 3: Verify audio player**

Run: `cd /home/noah/projects/readaloud && mix phx.server`
Navigate to a chapter with audio. Verify:
- Player renders with all controls
- Collapse toggle works (thin bar ↔ full controls)
- Speed dropdown shows 7 options, persists to localStorage
- Volume slider persists
- Word highlighting uses theme colors
- Manual scroll pauses auto-scroll, "Re-sync" button appears
- Touch scrubbing works on mobile

- [ ] **Step 4: Commit**

```bash
cd /home/noah/projects/readaloud
git add apps/readaloud_web/assets/js/hooks/
git commit -m "feat: enhance audio player with collapse, speed/volume persistence, and scroll re-sync"
```

---

## Chunk 4: Tasks Page & PWA

### Task 10: Tasks Page Rewrite

**Files:**
- Modify: `apps/readaloud_web/lib/readaloud_web_web/live/tasks_live.ex`

- [ ] **Step 1: Rewrite TasksLive**

Full rewrite of `apps/readaloud_web/lib/readaloud_web_web/live/tasks_live.ex`:

```elixir
defmodule ReadaloudWebWeb.TasksLive do
  use ReadaloudWebWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(ReadaloudLibrary.PubSub, "tasks:import")
      Phoenix.PubSub.subscribe(ReadaloudLibrary.PubSub, "tasks:audiobook")
    end

    import_tasks = ReadaloudImporter.list_tasks()
    audio_tasks = ReadaloudAudiobook.list_tasks()

    active = Enum.filter(import_tasks ++ audio_tasks, & &1.status in ["pending", "processing"])
    completed = Enum.filter(import_tasks ++ audio_tasks, & &1.status in ["completed", "failed"])
      |> Enum.sort_by(& &1.updated_at, {:desc, DateTime})

    {:ok,
     socket
     |> assign(
       active_nav: :tasks,
       task_count: length(active),
       active_tasks: active,
       completed_tasks: completed,
       page_title: "Tasks"
     )}
  end

  def handle_event("cancel_task", %{"task-id" => task_id, "type" => type}, socket) do
    # Find the Oban job for this task and cancel it
    case type do
      "import" ->
        task = ReadaloudImporter.get_task(String.to_integer(task_id))
        if task, do: cancel_oban_job_for_task(task)

      "audiobook" ->
        task = ReadaloudAudiobook.get_task(String.to_integer(task_id))
        if task, do: cancel_oban_job_for_task(task)
    end

    {:noreply, refresh_tasks(socket)}
  end

  def handle_event("clear_completed", _params, socket) do
    # Hard delete completed/failed tasks
    ReadaloudImporter.clear_completed_tasks()
    ReadaloudAudiobook.clear_completed_tasks()
    {:noreply, assign(socket, completed_tasks: [])}
  end

  def handle_event("retry_task", %{"task-id" => task_id, "type" => type}, socket) do
    case type do
      "audiobook" ->
        task = ReadaloudAudiobook.get_task(String.to_integer(task_id))
        if task do
          ReadaloudAudiobook.generate_for_chapter(task.book_id, task.chapter_id,
            model: task.model, voice: task.voice)
        end

      "import" ->
        task = ReadaloudImporter.get_task(String.to_integer(task_id))
        if task, do: ReadaloudImporter.import_file(task.file_path, task.file_type)
    end

    {:noreply, refresh_tasks(socket)}
  end

  # Theme is handled globally via root layout inline script + push_event.
  # Each LiveView that receives "set_theme" events needs this handler:
  @impl true
  def handle_event("set_theme", %{"theme" => theme}, socket) do
    {:noreply, push_event(socket, "set_theme", %{theme: theme})}
  end

  # PubSub handlers
  @impl true
  def handle_info(_, socket), do: {:noreply, refresh_tasks(socket)}

  defp refresh_tasks(socket) do
    import_tasks = ReadaloudImporter.list_tasks()
    audio_tasks = ReadaloudAudiobook.list_tasks()

    active = Enum.filter(import_tasks ++ audio_tasks, & &1.status in ["pending", "processing"])
    completed = Enum.filter(import_tasks ++ audio_tasks, & &1.status in ["completed", "failed"])
      |> Enum.sort_by(& &1.updated_at, {:desc, DateTime})

    assign(socket, active_tasks: active, completed_tasks: completed, task_count: length(active))
  end

  defp cancel_oban_job_for_task(task) do
    import Ecto.Query
    # Oban stores job args as JSON. Find the job matching this task_id.
    case ReadaloudLibrary.Repo.one(
      from j in Oban.Job,
        where: fragment("?->>'task_id' = ?", j.args, ^to_string(task.id)),
        where: j.state in ["available", "executing", "scheduled"],
        limit: 1
    ) do
      nil -> :ok
      job -> Oban.cancel_job(job.id)
    end
  end

  # Render function
  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto">
      <h1 class="text-2xl font-bold tracking-tight mb-6">Tasks</h1>

      <%!-- Active tasks --%>
      <div class="mb-8">
        <div class="flex items-center gap-2 mb-3">
          <h2 class="text-lg font-semibold">Active</h2>
          <span :if={length(@active_tasks) > 0} class="badge badge-primary badge-sm"><%= length(@active_tasks) %></span>
        </div>
        <div :if={@active_tasks == []} class="text-sm text-base-content/50">No active tasks</div>
        <div :for={task <- @active_tasks} class="card bg-base-200 p-4 mb-2">
          <div class="flex items-center gap-3">
            <.icon name="hero-arrow-path" class="w-5 h-5 animate-spin text-primary" />
            <div class="flex-1">
              <div class="text-sm font-medium"><%= task_description(task) %></div>
              <div class="text-xs text-base-content/50"><%= task_book_name(task) %></div>
              <progress class="progress progress-primary w-full mt-1" value={task.progress * 100} max="100" />
            </div>
            <button phx-click="cancel_task" phx-value-task-id={task.id} phx-value-type={task_type(task)}
              class="btn btn-ghost btn-xs text-error">Cancel</button>
          </div>
        </div>
      </div>

      <%!-- Completed tasks --%>
      <div>
        <div class="flex items-center justify-between mb-3">
          <h2 class="text-lg font-semibold">Completed</h2>
          <button :if={@completed_tasks != []} phx-click="clear_completed" class="btn btn-ghost btn-xs">
            Clear Completed
          </button>
        </div>
        <div :if={@completed_tasks == []} class="text-sm text-base-content/50">No completed tasks</div>
        <div :for={task <- @completed_tasks} class="flex items-center gap-3 py-2 border-b border-base-content/5 last:border-0">
          <.icon :if={task.status == "completed"} name="hero-check-circle" class="w-4 h-4 text-success" />
          <.icon :if={task.status == "failed"} name="hero-exclamation-circle" class="w-4 h-4 text-error" />
          <div class="flex-1 text-sm"><%= task_description(task) %> — <%= task_book_name(task) %></div>
          <span class="text-xs text-base-content/40"><%= relative_time(task.updated_at) %></span>
          <button :if={task.status == "failed"} phx-click="retry_task" phx-value-task-id={task.id} phx-value-type={task_type(task)}
            class="text-xs text-primary hover:underline">Retry</button>
        </div>
      </div>
    </div>
    """
  end

  defp task_type(%ReadaloudAudiobook.AudiobookTask{}), do: "audiobook"
  defp task_type(_), do: "import"

  defp task_description(%ReadaloudAudiobook.AudiobookTask{} = t), do: "Generating audio — Ch #{t.chapter_id}"
  defp task_description(t), do: "Importing #{Map.get(t, :file_name, "file")}"

  defp task_book_name(task) do
    case ReadaloudLibrary.get_book(task.book_id) do
      nil -> ""
      book -> book.title
    end
  end

  defp relative_time(datetime) do
    diff = DateTime.diff(DateTime.utc_now(), datetime, :second)
    cond do
      diff < 60 -> "#{diff}s ago"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86400 -> "#{div(diff, 3600)}h ago"
      true -> "#{div(diff, 86400)}d ago"
    end
  end
end
```

Note: `clear_completed_tasks/0` needs to be added to both `ReadaloudImporter` and `ReadaloudAudiobook` context modules:

```elixir
# In apps/readaloud_audiobook/lib/readaloud_audiobook.ex:
def clear_completed_tasks do
  from(t in AudiobookTask, where: t.status in ["completed", "failed"])
  |> Repo.delete_all()
end

# In apps/readaloud_importer/lib/readaloud_importer.ex:
# (use the actual import task schema name from the importer app)
def clear_completed_tasks do
  from(t in ImportTask, where: t.status in ["completed", "failed"])
  |> Repo.delete_all()
end
```

Note: Verify the actual schema module name in `readaloud_importer` — it may be `ReadaloudImporter.ImportTask` or similar.

Template renders:
- "Active" section with count badge, task cards with spinner/progress/cancel
- "Completed" section with "Clear Completed" button, compact rows with status/retry

- [ ] **Step 2: Add clear_completed_tasks to contexts**

Add `clear_completed_tasks/0` to both:
- `apps/readaloud_importer/lib/readaloud_importer.ex`
- `apps/readaloud_audiobook/lib/readaloud_audiobook.ex`

- [ ] **Step 3: Verify tasks page**

Run: `cd /home/noah/projects/readaloud && mix phx.server`
Navigate to `/tasks`. Verify:
- Active tasks show with spinner and progress
- Cancel button works
- Completed tasks show with timestamps
- Clear completed removes all finished tasks
- Retry link re-queues failed tasks

- [ ] **Step 4: Commit**

```bash
cd /home/noah/projects/readaloud
git add apps/readaloud_web/lib/ apps/readaloud_importer/lib/ apps/readaloud_audiobook/lib/
git commit -m "feat: rewrite tasks page with cancel, clear completed, and retry"
```

---

### Task 11: PWA Support

**Files:**
- Create: `apps/readaloud_web/priv/static/manifest.json`
- Create: `apps/readaloud_web/priv/static/sw.js`
- Create: `apps/readaloud_web/priv/static/images/icon-192.png`
- Create: `apps/readaloud_web/priv/static/images/icon-512.png`

- [ ] **Step 1: Create manifest.json**

```json
{
  "name": "Readaloud",
  "short_name": "Readaloud",
  "start_url": "/",
  "display": "standalone",
  "background_color": "#13171c",
  "theme_color": "#6366f1",
  "icons": [
    {
      "src": "/images/icon-192.png",
      "sizes": "192x192",
      "type": "image/png"
    },
    {
      "src": "/images/icon-512.png",
      "sizes": "512x512",
      "type": "image/png"
    }
  ]
}
```

- [ ] **Step 2: Create service worker**

```javascript
// apps/readaloud_web/priv/static/sw.js
const CACHE_NAME = "readaloud-v1";
const STATIC_ASSETS = ["/assets/app.css", "/assets/app.js", "/fonts/Inter-Variable.woff2"];

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.addAll(STATIC_ASSETS))
  );
  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((k) => k !== CACHE_NAME).map((k) => caches.delete(k)))
    )
  );
  self.clients.claim();
});

self.addEventListener("fetch", (event) => {
  const url = new URL(event.request.url);

  // Never cache WebSocket upgrades
  if (event.request.headers.get("upgrade") === "websocket") return;

  // Network-first for HTML and API
  if (event.request.mode === "navigate" || url.pathname.startsWith("/api/") || url.pathname.startsWith("/live/")) {
    event.respondWith(
      fetch(event.request).catch(() => caches.match(event.request))
    );
    return;
  }

  // Cache-first for static assets
  if (url.pathname.startsWith("/assets/") || url.pathname.startsWith("/fonts/") || url.pathname.startsWith("/images/")) {
    event.respondWith(
      caches.match(event.request).then((cached) => {
        return cached || fetch(event.request).then((response) => {
          const clone = response.clone();
          caches.open(CACHE_NAME).then((cache) => cache.put(event.request, clone));
          return response;
        });
      })
    );
    return;
  }

  // Default: network-first
  event.respondWith(fetch(event.request).catch(() => caches.match(event.request)));
});
```

- [ ] **Step 3: Generate PWA icons**

The icons need to be the headphones gradient logo. For now, create placeholder PNGs. A proper icon can be designed later:

```bash
# Create placeholder icons using ImageMagick (if available) or just create empty PNGs
cd /home/noah/projects/readaloud/apps/readaloud_web/priv/static/images
convert -size 192x192 -define gradient:vector=0,0,192,192 gradient:'#6366f1-#8b5cf6' icon-192.png 2>/dev/null || echo "Create icon-192.png manually"
convert -size 512x512 -define gradient:vector=0,0,512,512 gradient:'#6366f1-#8b5cf6' icon-512.png 2>/dev/null || echo "Create icon-512.png manually"
```

If ImageMagick isn't available, create simple gradient PNGs with any tool or use placeholder images temporarily.

- [ ] **Step 4: Register service worker**

In the root layout (`root.html.heex`), add before `</body>`:

```html
<script>
  if ("serviceWorker" in navigator) {
    navigator.serviceWorker.register("/sw.js");
  }
</script>
```

- [ ] **Step 5: Verify PWA**

Run: `cd /home/noah/projects/readaloud && mix phx.server`
Open `http://localhost:4000` in Chrome. Verify:
- No console errors
- Application → Manifest shows "Readaloud" with icons
- Application → Service Workers shows registered worker
- Lighthouse → PWA audit shows installable (if icons are valid PNGs)

- [ ] **Step 6: Commit**

```bash
cd /home/noah/projects/readaloud
git add apps/readaloud_web/priv/static/ apps/readaloud_web/lib/readaloud_web_web/components/layouts/root.html.heex
git commit -m "feat: add PWA support with manifest, service worker, and app icons"
```

---

## Final Verification

- [ ] **Full compilation check**: `cd /home/noah/projects/readaloud && mix compile --warnings-as-errors`
- [ ] **Run all tests**: `cd /home/noah/projects/readaloud && mix test`
- [ ] **Manual smoke test**: Navigate through all pages (Library → Book Detail → Reader → Tasks), verify theme switching, audio generation, word highlighting, and keyboard shortcuts
- [ ] **Mobile test**: Open on a phone (via tailscale) or use browser dev tools responsive mode. Verify hamburger menu, tap controls, collapsible player, bottom sheet for voice settings
- [ ] **PWA install test**: Install from Chrome on mobile, verify standalone mode works
