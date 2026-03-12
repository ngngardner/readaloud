# Readaloud UI Redesign

Comprehensive UI overhaul of the Readaloud self-hosted audiobook reader, drawing inspiration from the ln-reader (web-ln) design language. Full page rewrites using Phoenix LiveView + DaisyUI + Heroicons.

## Context

Readaloud is an Elixir/Phoenix LiveView app (umbrella project) that imports EPUB/PDF files, generates audiobooks via LocalAI TTS, and provides word-level highlighted reading. The current UI is functional but visually basic. This redesign prepares it for sharing with others.

**Tech stack (unchanged):** Elixir 1.17+, Phoenix 1.8 + LiveView 1.1, SQLite, DaisyUI, Tailwind CSS 4, Heroicons, esbuild.

**Inspiration:** web-ln (React/TypeScript ln-reader) — same DaisyUI foundation but with significantly more visual polish, theming, and reader customization.

## 1. Global Chrome & Theme System

### Navigation: Hybrid Sidebar + Immersive Reader

Two navigation modes based on context:

**Library/Tasks/Book Detail pages — Collapsible Sidebar:**
- Icon rail on the left (56px collapsed), expands to 200px on hover to show labels
- Gradient logo badge (indigo→violet) with headphones Heroicon
- Nav items: Library, Tasks (with active count badge when tasks running)
- Bottom items: Theme (opens theme selector modal)
- Active state: subtle filled background (`bg-primary/15`) with primary color icon. Determined by matching the current `@live_action` / socket path against each nav item's target route.
- Semi-transparent background with backdrop blur, 1px right border at `base-content/6`
- Mobile: hidden behind hamburger icon (top-left), slides out as overlay with backdrop

**Reader page — Fully Immersive:**
- Sidebar disappears completely, full-bleed content
- Floating top pill bar behavior:
  - **Desktop:** appears on mouse movement anywhere on page, fades out after 3 seconds of no mouse movement. Timer resets on any interaction within the pill itself.
  - **Mobile:** tap the top 80px of the viewport to toggle pill visibility. Tapping within the text body triggers click-to-seek (no conflict). The pill stays visible until tapped again or after 5 seconds.
  - Contents: Back arrow, Library icon, "Ch 3 / 12" chapter indicator, chapter progress percentage ("47%"), settings gear
  - Semi-transparent with backdrop blur, rounded pill shape, subtle border + shadow

### Theme System

Port the full ln-reader theme engine:

- DaisyUI `data-theme` attribute on root element
- localStorage persistence using existing key `phx:theme` (maintaining backward compatibility with current user preferences)
- Enable all standard DaisyUI themes by changing the current `themes: false` plugin configuration. In DaisyUI 5 / Tailwind CSS 4, this requires updating the `@plugin` directive in `app.css` to include the built-in theme set.
- The existing custom dark and light themes defined via `@plugin "../vendor/daisyui-theme"` will be replaced by the new custom themes below.
- The existing `@custom-variant dark` (hardcoded to `data-theme=dark`) must be removed or refactored. With multiple dark themes, rely on DaisyUI's built-in `color-scheme: "dark"` per-theme instead of a single dark variant selector.
- Custom themes defined in `app.css` using OKLCH color space:
  - **Vampire** (dark): near-black base, orange/amber accents — blue light filter friendly
  - **Blood** (dark): dark red-brown base, vivid red accents — high contrast
- Both custom themes listed under the Dark Themes category in the selector
- Theme selector opens as a modal overlay, grid of theme buttons grouped by Dark and Light categories
- Each theme button shows a **color swatch preview**: a small bar with 4 colored circles representing `base-100`, `primary`, `secondary`, and `accent` for that theme. Allows visual comparison without trial-and-error.
- All icons from Heroicons (bundled with Phoenix) — no emojis anywhere in the UI

### Typography

- Inter font self-hosted in `priv/static/fonts/` (more resilient for self-hosted/tailscale deployments than Google Fonts CDN)
- Variable weight 100-900
- `antialiased` rendering globally
- `tracking-tight` for headings

### Keyboard Shortcuts

Global keyboard shortcuts via `phx-window-keydown` handler on the root layout:

| Key | Action | Context |
|-----|--------|---------|
| `Space` | Play/pause audio | Reader (when audio available) |
| `ArrowLeft` | Previous chapter | Reader |
| `ArrowRight` | Next chapter | Reader |
| `+` / `=` | Increase playback speed (cycles to next value in dropdown: 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0) | Reader (when audio playing) |
| `-` | Decrease playback speed (cycles to previous value in dropdown) | Reader (when audio playing) |
| `Escape` | Toggle floating pill visibility | Reader |
| `m` | Mute/unmute | Reader (when audio available) |
| `/` | Focus library search input | Library only (no-op on other pages) |

Shortcuts are disabled when a text input or textarea has focus. All shortcuts respect `prefers-reduced-motion` for any associated animations.

### Accessibility

- All hover animations, auto-scroll, and fade transitions respect `prefers-reduced-motion: reduce`. When enabled: no scale transforms on cards, no smooth scroll (instant jump), no fade transitions on the floating pill (instant show/hide).
- Semantic HTML: `<nav>` for sidebar, `<article>` for reader content, `<header>` for page headers
- ARIA labels on icon-only buttons

## 2. Library Page

### Search and Sort

- Search input in the library header: filters books by title and author as you type (client-side filter via LiveView `phx-change` with debounce)
- Sort dropdown next to search: options are "Recently Read" (default, by last progress update — books with no progress sort to the end, ordered by import date), "Title A-Z", "Author A-Z", "Recently Added" (by import date)
- Sort preference persisted to localStorage (key: `readaloud-library-sort`)

### Book Cards

Rich cards replacing the current text-only cards:

- 3:4 aspect ratio (portrait book cover orientation)
- Cover image fills the card, gradient overlay at bottom (`linear-gradient(to top, rgba(0,0,0,0.85), transparent)`)
- Title and author text over the gradient
- Hover: scale up slightly + deeper shadow (`transition: transform 0.3s, box-shadow 0.3s`)
- **Quick-resume on click:** clicking a card goes directly to the reader at the last-read chapter position. No intermediate Book Detail step for the most common action.
- **Detail link:** small info icon (Heroicon `information-circle`) in the bottom-right corner of the card. On desktop: visible on hover. On mobile: always visible (no hover state exists). Opens the Book Detail page for metadata, chapter list, and management actions.
- Responsive grid: 2 cols mobile, 3 tablet, 4-5 desktop, 6 on xl screens
- Gap: 12px

### Card Badges

Positioned in card corners with blurred dark backgrounds:

- **Top-left — Audio available:** Headphones icon + "Audio" label (always shown if any chapters have audio)
- **Top-right — Status badge** (mutually exclusive, priority order):
  1. **DONE** (green background) — shown when all chapters are read (progress == total)
  2. **NEW** (indigo background) — shown when book has zero reading progress and was imported within the last 7 days
  3. **Progress count** ("3/9", dark background) — shown in all other cases when progress > 0
  4. Nothing — book with no progress and not new
- **Bottom — Progress bar:** 3px bar showing reading percentage, primary color fill. Only shown when progress > 0 and < 100%.

### Loading States

- **Initial load:** Skeleton card placeholders matching the 3:4 aspect ratio with a subtle shimmer animation. Show the same number of skeletons as the grid column count.
- **Cover images:** Each card renders immediately with the gradient placeholder; the actual cover image lazy-loads (`loading="lazy"`) and fades in over 200ms when ready. No layout shift.

### Cover Image Pipeline

Four-tier fallback for book covers, resolved asynchronously:

1. **EPUB extraction:** Parse OPF metadata for cover item ID, extract image. Fallback: scan all image items for filename containing "cover". Runs synchronously during import (fast, local file operation).
2. **PDF first page:** Render page 1 as 300px-wide thumbnail using `pdftoppm` (from `poppler-utils`, must be available in the Docker image — add to Dockerfile if not present). Target: 300x400px JPEG at 72dpi. Runs synchronously during import.
3. **Open Library API:** Query `https://openlibrary.org/search.json?title=X&author=Y`, use cover ID to fetch from `https://covers.openlibrary.org/b/id/{id}-M.jpg`. **Runs as a background Oban job** with 10-second timeout — does not block import. On success, updates the book's `cover_path`. On failure, falls through to tier 4.
4. **Gradient placeholder:** Generate deterministic gradient from title hash — ensures every book has a unique visual identity even without a cover. Available immediately, no async needed.

Covers stored in `STORAGE_PATH/covers/{book_id}.jpg`.

### Import Flow

- Upload button in library header area (plus icon)
- Drag-and-drop overlay zone: dashed indigo border, upload icon, "Drop files here" text, "EPUB and PDF supported, up to 100MB", "Browse Files" primary button
- After drop/select: show inline toast notification with progress ("Importing..."), auto-refresh library grid on completion. No page redirect.
- **On failure:** show an error toast with the filename and failure reason (e.g., "Failed to import dune.epub: unsupported format"). Toast stays visible until dismissed (no auto-timeout for errors).

### Book Management

- Delete book: accessible from Book Detail page (Section 3), not from library cards
- Confirmation dialog before delete ("This will remove the book and all generated audio")

## 3. Book Detail Page

Accessed via the info icon on a book card in the library.

### Layout

- Sidebar visible (collapsed icon rail)
- Back link: arrow + "Back to Library" at top
- Book header: cover image (100px wide) + title, author, metadata badges, action buttons
- Metadata badges: chapter count, reading progress ("3/9 read"), audio progress ("5/9 audio")
- Primary action: "Continue Reading" button (resumes at last position)
- Secondary action: "Generate Audio" button with batch chapter selection (see below)
- Danger action: "Delete Book" button (ghost style, red text, with confirmation dialog)

### Batch Audio Generation

Instead of a simple "Generate All Audio" button, provide batch selection:

- "Generate Audio" button opens a chapter selection panel
- Selection modes: "All chapters", "From current chapter onward", or individual chapter toggles (checkboxes)
- Chapters that already have audio are shown as disabled/checked with a checkmark
- Model and voice dropdowns in the selection panel (same as reader State 1)
- "Generate Selected" button to queue the batch
- Uses the book's `audio_preferences` for defaults, falls back to env vars

### Chapter List

- Vertical list below header
- Each row: chapter number, title, word count (e.g., "~2,400 words"), estimated reading time (based on 250 WPM), status icons (audio available, read checkmark)
- Current chapter highlighted with subtle primary background + "CURRENT" label
- Click any chapter to open reader at that chapter
- Failed audio generation: chapter row shows a red warning icon with "Retry" action inline — no need to navigate to Tasks page

## 4. Reader + Integrated Audio Player

### Route Merging

The current separate routes are merged:
- `/books/:id/read/:chapter_id` and `/books/:id/listen/:chapter_id` → single route `/books/:id/read/:chapter_id`
- `PlayerLive` is deleted; its audio playback logic (JS hook, timings API, word highlighting) is folded into `ReaderLive`
- The `/listen/` route is removed from the router. Any existing links or bookmarks to `/listen/` should 301 redirect to the equivalent `/read/` URL.
- The existing `ReadingProgress` schema with `audio_position_ms` continues to work unchanged — the merged view reads and writes it the same way `PlayerLive` did.

### Loading State

- While chapter HTML loads: show a skeleton with 8-10 text-width placeholder bars at default dimensions (18px font, 1.8 line height). A JS hook adjusts skeleton dimensions to match user settings from localStorage on mount, before content arrives. Fade in content when ready.

### Immersive Reading Area

- Full-bleed content, centered with configurable max-width (default 700px)
- Chapter title as subtle uppercase label above content
- Body text font selectable from 3 presets: **Serif** (Georgia, default), **Sans** (Inter), **Mono** (monospace system stack). Selected in reader settings popover.
- Configurable font size (12-24px, default 18px), line height (1.4-2.2, default 1.8)
- Scroll position tracked and persisted (existing functionality)

### Audio Player — Three States

**State 1: No audio generated**
- Fixed bottom bar with semi-transparent backdrop blur background
- Left: Headphones icon
- Center: "Listen to Audiobook" title, "Generate an audiobook version of this chapter" subtitle
- Right: Model selector dropdown, voice selector dropdown, "Generate Audio" primary button
- **Mobile (< 640px):** model/voice selectors move to a full-screen bottom sheet, triggered by a "Voice Settings" button. The bottom bar shows only the headphones icon, title, and "Generate Audio" button.
- Model + voice follow the OpenAI TTS API standard (model parameter + voice parameter)
- **Backend work required:** Add a new function `ReadaloudTTS.list_models_and_voices/0` that queries LocalAI's `/v1/models` endpoint and returns available TTS models. Voice lists will be hardcoded per known model (e.g., Kokoro voices: `af_heart`, `af_nicole`, etc.) since LocalAI does not expose a voice enumeration endpoint. The function should cache results for 5 minutes.
- Model/voice selection persists per-book in a new `audio_preferences` field on the Book schema (JSON column: `{model, voice}`). Falls back to system defaults from env vars.
- **Schema migrations required:**
  - Add `audio_preferences` (JSON) column to `books` table
  - Add `model` (string) column to `audiobook_tasks` table — `GenerateJob.perform/1` must pass the selected model to `ReadaloudTTS.synthesize/2` instead of always using the env default

**State 2: Generating**
- Same bottom bar position
- Spinner icon, "Generating Audio..." title, "You can keep reading while this runs" subtitle
- Progress bar showing generation percentage
- **Cancel button:** "Cancel" text button next to the progress bar. Cancels the Oban job via `Oban.cancel_job/1` and reverts to State 1.
- Real-time updates via Phoenix PubSub (existing Oban integration)

**State 3: Audio ready — Full player**
- Fixed bottom bar with full audio controls:
  - Full-width progress scrubber with draggable handle (supports both mouse drag and touch slide)
  - Skip back (10s), Play/Pause (circle button, primary color), Skip forward (10s)
  - Time display: "2:14 / 6:32" with tabular-nums
  - Volume icon + slider
  - Speed control: tap to show dropdown popover with options: 0.5x, 0.75x, 1.0x, 1.25x, 1.5x, 1.75x, 2.0x (avoids tedious cycling through 16 discrete steps)
- **Collapsible:** Collapse/expand toggle (chevron icon) in the player bar. Collapsed state shows a thin bar (36px) with only: play/pause icon, progress bar, and time. Expand to restore full controls. Collapse state persisted to localStorage (key: `readaloud-player-collapsed`). **On mobile (< 640px):** player starts collapsed by default. Expand uses the same toggle (not a full-screen tray) — the full controls simply stack vertically within the bottom bar when expanded.
- Hard swap from State 1/2 to State 3 when audio becomes available

### Playback Preference Persistence

- **Speed:** Saved globally to localStorage (key: `readaloud-playback-speed`). Applies across all books/chapters.
- **Volume:** Saved globally to localStorage (key: `readaloud-volume`). Applies across all books/chapters.
- **Player collapsed state:** Saved globally to localStorage (key: `readaloud-player-collapsed`).
- **Model/voice:** Saved per-book in the `audio_preferences` DB field. Different books can use different voices.

### Word-Level Highlighting

- Each word wrapped in `<span>` with `data-word-index` attribute
- Colors use DaisyUI semantic tokens to adapt across all themes:
  - Current word: `text-base-content` on `bg-primary/20` background, 3px border-radius
  - Already spoken: `text-base-content/40` (dimmed)
  - Upcoming: `text-base-content` (normal brightness)
- **Auto-scroll behavior:**
  - When enabled: smoothly scrolls to keep highlighted word in upper third of viewport
  - **Manual scroll override:** if the user scrolls manually during playback, auto-scroll pauses. A small "Re-sync" floating button appears in the bottom-right (above the player bar): clicking it snaps back to the current word and re-enables auto-scroll. Auto-scroll also re-enables automatically when the highlighted word scrolls back into the viewport.
- Click-to-seek: clicking any word jumps audio to that word's timestamp
- Binary search on word timings array for efficient lookup (existing algorithm)

### Reader Settings Popover

Accessed via gear icon in the floating top pill. Appears as a popover panel (desktop) or full-screen panel (mobile).

- **Font Family:** Segmented control with 3 presets: Serif (Georgia), Sans (Inter), Mono (system)
- **Font Size:** Slider, 12-24px, shows current value
- **Line Height:** Slider, 1.4-2.2, shows current value
- **Content Width:** Slider, 500-1000px, shows current value
- **Auto-scroll with audio:** Toggle (default on)
- **Auto next chapter:** Toggle (default off)
- Settings persisted to localStorage (key: `readaloud-reader-settings`)
- Changes apply immediately (live preview)

### Chapter Navigation

- Previous/Next chapter via floating top pill arrows
- Auto-advance to next chapter when audio finishes (if toggle enabled)
- Chapter indicator in floating pill: "Ch 3 / 12 · 47%"
- Chapter progress percentage is calculated from: audio position / duration when audio is playing, otherwise scroll position (0-100% of page). Both are already tracked.

## 5. Tasks Page

Real-time monitoring of import and audiobook generation tasks.

### Layout

- Sidebar visible
- Two sections: Active (with count badge) and Completed
- "Clear Completed" button in Completed section header — hard deletes completed/failed task records from the DB. No value in keeping old task records; they aren't referenced elsewhere.

### Active Tasks

- Card per task with spinner, task description ("Generating audio — Ch 4"), book name, percentage, progress bar
- **Cancel button** on each active task: cancels the Oban job, removes from active list
- Import tasks: purple accent color
- Audio generation tasks: indigo accent color
- Real-time updates via Phoenix PubSub (existing)

### Completed Tasks

- Compact rows: checkmark/error icon, task description, book name, relative timestamp ("2m ago")
- Failed tasks: red error icon, "Retry" link
- Tasks sorted by most recent first

## 6. PWA Support

- `manifest.json`: `display: "standalone"`, name "Readaloud", theme color matching DaisyUI primary
- App icons: 192x192 and 512x512 PNG with the headphones gradient logo
- Service Worker:
  - Network-first for API calls and LiveView WebSocket connections (do not cache WebSocket upgrades)
  - Cache-first for static assets (CSS, JS, fonts, images)
  - Network-first for all HTML responses to ensure LiveView mounts fresh (prevents stale cached HTML when PWA resumes from background)
  - Cache versioning: include a version string derived from the app version or build hash; on deploy, the new service worker invalidates stale caches
- Phoenix serves the manifest and service worker from the static assets pipeline

## 7. Mobile Responsive Behavior

| Component | Mobile | Tablet | Desktop |
|-----------|--------|--------|---------|
| Sidebar | Hamburger → slide-out overlay | Collapsed icon rail | Collapsed, expand on hover |
| Library grid | 2 columns | 3-4 columns | 5-6 columns |
| Book detail | Cover + info stacked vertically | Side by side | Side by side |
| Reader | Full-width, 16px font default | Centered, 18px | Centered, 18px, max-width |
| Audio player (State 1) | Bottom sheet for model/voice | Full bar with dropdowns | Full bar with dropdowns |
| Audio player (State 3) | Compact bar, expand for full controls | Full controls | Full controls |
| Theme selector | Full-screen modal | Modal overlay | Modal overlay |
| Settings | Full-screen panel | Popover | Popover |
| Floating pill | Tap top 80px to toggle | Hover or tap | Mouse movement to show |

## Non-Goals

- Landing page (self-hosted, not needed)
- User accounts / multi-user support
- Online/public book discovery or search
- Full offline reading mode
- Custom font uploads (3 presets are sufficient)
- Multi-device progress sync / conflict resolution — the app is single-user self-hosted, so `ReadingProgress` is one row per book with no device tracking. If PWA is used on multiple devices simultaneously, last-write-wins. True sync would require timestamps and merge logic that isn't justified for the current use case.
- Dedicated settings page (theme is the only user setting; reader settings are in the reader popover)

## Dependencies

- **Open Library API** — cover image fallback (no API key required)
- **LocalAI** — TTS with OpenAI-compatible API (model + voice parameters)
- **Inter font** — self-hosted in `priv/static/fonts/`
- **Heroicons** — already bundled with Phoenix
- **poppler-utils** — `pdftoppm` for PDF cover thumbnail generation (add to Dockerfile if not present)
