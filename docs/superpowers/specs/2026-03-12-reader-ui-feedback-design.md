# Reader UI Feedback & Missing Features — Design Spec

**Date:** 2026-03-12
**Status:** Draft
**Scope:** Floating pill redesign, speed display, theme in settings, auto-next-chapter fix, accidental navigation popup

## Overview

Addresses user feedback on the readaloud reader UI and ports missing features from ln-reader (web-ln). Six changes total: one bug fix, four UI improvements, one new feature.

## 1. Floating Pill Redesign

### Current State

```
[hero-arrow-left → BookLive] [hero-book-open → LibraryLive] "Ch 3 / 12" [hero-cog-6-tooth]
```

Problems:
- No way to navigate chapters from the pill
- Two navigation buttons (back arrow → book detail, book icon → library) are confusing

### Design

Replace with:

```
[hero-home → LibraryLive] [hero-chevron-left] "Ch 3 / 12" [hero-chevron-right] [hero-cog-6-tooth]
```

- **Single home button** (`hero-home`) navigates to library. Removes the confusing back/library split.
- **Prev/next arrows** (`hero-chevron-left` / `hero-chevron-right`) navigate chapters. Disabled (reduced opacity) at boundaries.
- **Chapter indicator** ("Ch 3 / 12") is tappable — toggles the slide-down chapter bar.

### Slide-Down Chapter Bar

Tapping the chapter indicator slides down a panel below the pill containing two rows:

**Row 1 — Progress scrubber:**
- Thin horizontal bar representing the entire book
- Filled portion shows progress (current chapter position / total chapters)
- Draggable thumb positioned at current chapter
- On drag: tooltip shows chapter number and title (if available). On touch devices, tooltip appears during drag gesture and disappears on release. No hover behavior on mobile.
- Tap anywhere on the bar to jump to that chapter
- Chapter boundary tick marks (subtle, for orientation)

**Row 2 — Nearby chapter strip:**
- Horizontal scrollable row of compact chapter pills (numbers)
- Centered on the current chapter, which is highlighted (primary color background)
- Tap a pill to navigate to that chapter
- Scroll/swipe to see more chapters
- Current chapter pill is visually distinct (filled vs outline)

**Behavior:**
- Tap chapter label → slide down with 200ms ease transition
- Tap chapter label again, tap outside, or navigate → collapse
- When the floating pill auto-hides (timeout), the chapter bar also collapses. If the pill reappears, the chapter bar starts collapsed (user must tap label again to open).
- Scrubber drag updates the strip's scroll position to stay synced
- Pill tap navigates immediately (subject to accidental navigation check — see section 6)

### Files Affected

- `reader_live.ex` — floating pill template (lines 196-216), new chapter bar markup, new event handlers (`toggle_chapter_bar`, `jump_to_chapter`)
- `floating_pill.js` — chapter bar toggle logic, scrubber drag handling, strip scroll sync
- `app.css` — chapter bar styles, scrubber track/thumb, chapter pill styles

## 2. Speed Display Fix

### Current State

Speed is a dropdown button that only shows the current speed value when clicked open.

### Design

Replace with a **persistent speed badge** that always displays the current speed (e.g., "1.5x").

- Default display: compact badge showing "1x", "1.5x", etc.
- Tap to cycle through speeds: 0.5 → 0.75 → 1.0 → 1.25 → 1.5 → 1.75 → 2.0 → 0.5 (wraps)
- Badge uses `tabular-nums` font variant for stable width
- Visual: `btn btn-ghost btn-xs` with the speed text, same style as other pill/player controls

Speed cycling is purely client-side (localStorage only, no server persistence). The +/- keyboard shortcuts keep their current increment/decrement behavior — only the badge tap cycles forward.

### Files Affected

- `reader_live.ex` — replace speed dropdown markup with speed badge button (click handler is JS, not a LiveView event)
- `audio_player.js` — add click handler to cycle speed forward on badge tap, initialize badge text from localStorage on `mounted()`, update badge text on any speed change

## 3. Theme Selector in Reader Settings Popover

### Current State

Theme selection only available in the sidebar (bottom button). Not accessible from the immersive reader settings popover.

### Design

Add a **Theme** section at the bottom of the reader settings popover (below the Width slider).

- Section label: "Theme"
- Grid of theme swatches, grouped into Light and Dark rows
- Each swatch is a small colored circle or rounded rectangle showing the theme's primary/base colors
- Active theme is highlighted (ring or checkmark)
- Tapping a swatch applies the theme by setting `document.documentElement.setAttribute("data-theme", theme)` and persisting to `localStorage.setItem("phx:theme", theme)` directly via JS — no server round-trip needed.
- Theme list: reuse the existing `@dark_themes` and `@light_themes` module attributes from `ThemeSelector` component (`theme_selector.ex`) rather than hardcoding a separate list.
- Settings popover needs `max-h-[calc(100vh-5rem)] overflow-y-auto` to handle the added theme grid on small screens.

**Note on existing theme mechanism:** The current `push_event("set_theme", ...)` approach in the sidebar dispatches a non-bubbling CustomEvent on the hook element, which may not reach the `window.addEventListener` in `root.html.heex`. The reader settings implementation should apply themes directly via JS (setting `data-theme` + localStorage) rather than going through `push_event`, avoiding this issue entirely. The ThemeHook should be updated to also use this direct approach.

### Files Affected

- `reader_live.ex` — add theme grid section to settings popover template, import theme lists from `ThemeSelector`
- `reader_settings.js` — add theme-switching logic (direct DOM + localStorage, no server event needed)
- `theme.js` — update to apply themes directly rather than relying on push_event bubbling
- `app.css` — theme swatch grid styles (if not covered by DaisyUI utilities)

## 4. Font — No Change Needed

Both readaloud and ln-reader use Inter (self-hosted, variable weight 100-900). The serif/sans/mono font family selector in reader settings already maps to Georgia, Inter, and system monospace respectively. No work required.

## 5. Auto Next Chapter — Bug Fix

### Current State

The JavaScript wiring is complete and correct:
- `audio_player.js` line 168-173: `ended` event → checks `autoNextChapter` setting → pushes `next_chapter` event
- `reader_settings.js`: default `autoNextChapter: false` defined in defaults object
- `reader_live.ex` line 79-84: `next_chapter` handler navigates to next chapter

**The bug:** There is no UI toggle to enable the `autoNextChapter` setting. Users cannot turn it on.

### Design

Add an "Auto next chapter" toggle to the reader settings popover, below the existing controls.

- Toggle label: "Auto next chapter"
- DaisyUI `toggle toggle-sm` component
- Dispatches `update_reader_setting` with `key: "autoNextChapter"`, `value: true/false`
- `reader_settings.js` already handles arbitrary key/value updates to localStorage

**Toggle initial state:** Since `autoNextChapter` is stored in localStorage (client-side), the toggle's checked state cannot be set from server-rendered HEEx. The `ReaderSettingsHook` must initialize the toggle's checked attribute on `mounted()` by reading from localStorage, same as it already does for font/size/spacing settings.

### Files Affected

- `reader_live.ex` — add toggle markup to settings popover (after Width slider section, before closing div)
- `reader_settings.js` — initialize toggle checked state from localStorage on mount

## 6. Accidental Navigation Popup

### Current State

Not implemented. Users can accidentally navigate to an old chapter (e.g., stale phone tab) and overwrite their real reading progress.

### ln-reader Reference

`ProgressConflictModal.tsx` + `useReader.ts` lines 55-79: compares current chapter against server's last-read position. Triggers only when server position is ahead of the navigated-to chapter.

### Design

On mount in `ReaderLive`, compare the navigated-to chapter against `ReadingProgress.current_chapter_id`. **Critical: the conflict check must run before `upsert_progress` is called**, otherwise the last-read position is overwritten before comparison.

**Mount order:**
1. Load `progress = ReadaloudReader.get_progress(book_id)`
2. If `progress` exists and `progress.current_chapter_id != chapter_id`:
   - Find index of `progress.current_chapter_id` in chapter list → `last_read_index`
   - Find index of navigated-to `chapter_id` → `target_index`
   - If `last_read_index > target_index` (user is jumping backward):
     - Set assigns: `show_conflict_modal: true`, `conflict_chapter: last_read_chapter`
     - **Do NOT call `upsert_progress` yet** — defer until user resolves the conflict
3. Otherwise: no conflict, call `upsert_progress` as normal

**Popup content:**

> Your last reading position is **Chapter {last_read_chapter.title || last_read_chapter.number}**.
>
> `[Stay on Chapter {target.title || target.number}]`  `[Go to Chapter {last_read.title || last_read.number}]`

**Behavior:**
- "Stay" → dismiss popup, call `upsert_progress` with the current (target) chapter, proceed normally
- "Go to" → navigate to `last_read_chapter` via `push_navigate` (no progress update needed — the new mount will handle it)
- Popup is a DaisyUI modal (`modal modal-open`) with backdrop
- Does NOT trigger on:
  - Auto-advance (next chapter after audio ends)
  - Sequential forward navigation (prev/next buttons moving forward)
  - Same chapter reload
  - In-session navigation from chapter bar, prev/next buttons, or any internal `push_navigate`

**Distinguishing stale-tab from internal navigation:** Internal navigation (prev/next buttons, chapter bar jumps, auto-advance) passes a `?nav=internal` query param when calling `push_navigate`. The mount function checks for this param:
- If `nav=internal` is present: skip the conflict check entirely, call `upsert_progress` normally
- If absent (direct URL load, stale tab, bookmark): run the conflict check

This ensures the popup only fires for genuine stale-tab scenarios, not for deliberate in-session backward navigation.

### Files Affected

- `reader_live.ex` — restructure mount to defer `upsert_progress` when conflict detected, add `?nav=internal` param to all internal `push_navigate` calls, new assigns (`show_conflict_modal`, `conflict_chapter`), modal template, event handlers (`dismiss_conflict`, `go_to_conflict_chapter`)
- `floating_pill.js` — ensure chapter bar jump navigation includes `?nav=internal`
- No other JS changes needed — modal is pure LiveView server-rendered

## Summary of Changes

| # | Change | Type | Complexity |
|---|--------|------|------------|
| 1 | Floating pill redesign + chapter bar | UI overhaul | High |
| 2 | Speed display badge | UI tweak | Low |
| 3 | Theme selector in settings | UI addition | Medium |
| 4 | Font check | No change | None |
| 5 | Auto next chapter toggle | Bug fix | Low |
| 6 | Accidental navigation popup | New feature | Medium |
