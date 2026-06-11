defmodule ReadaloudWebWeb.ChapterNeighbors do
  @moduledoc """
  Single source of truth for chapter adjacency and the "neighbor with
  audio" rule.

  Two consumers must agree exactly on this logic or the player's chapter
  chain breaks:

    * `ReadaloudWebWeb.ReaderLive` — renders the neighbors into the
      audio-player hook's dataset (`data-next-*` / `data-prev-*`), the
      primary source, delivered over the LV WebSocket.
    * `ReadaloudWebWeb.AudioController.nav/2` — serves the same data as
      JSON over plain HTTP, fetched by the hook at prefetch time so the
      autoplay chain still knows "what comes after the chapter I'm about
      to swap to" when the WS is dead (the 2026-06-11 commute incident:
      a stale dataset made the ended-handler navigate to the chapter
      that had just finished).

  The rule: a neighbor is the strictly adjacent chapter by list order —
  if that chapter has no audio the neighbor is `nil`, never a farther
  chapter. Skipping would silently jump the listener over content.
  """

  @doc "Strictly adjacent next chapter in the ordered list, or nil."
  def next(chapters, chapter_id) do
    case Enum.find_index(chapters, &(&1.id == chapter_id)) do
      nil -> nil
      idx when idx < length(chapters) - 1 -> Enum.at(chapters, idx + 1)
      _ -> nil
    end
  end

  @doc "Strictly adjacent previous chapter in the ordered list, or nil."
  def prev(chapters, chapter_id) do
    case Enum.find_index(chapters, &(&1.id == chapter_id)) do
      nil -> nil
      idx when idx > 0 -> Enum.at(chapters, idx - 1)
      _ -> nil
    end
  end

  @doc "Adjacent next chapter only if it has generated audio, else nil."
  def next_with_audio(chapters, chapter_id),
    do: with_audio(next(chapters, chapter_id))

  @doc "Adjacent previous chapter only if it has generated audio, else nil."
  def prev_with_audio(chapters, chapter_id),
    do: with_audio(prev(chapters, chapter_id))

  @doc "The chapter title the reader UI renders (template fallback included)."
  def display_title(chapter), do: chapter.title || "Chapter #{chapter.number}"

  defp with_audio(nil), do: nil

  defp with_audio(chapter) do
    if ReadaloudAudiobook.get_chapter_audio(chapter.id), do: chapter, else: nil
  end
end
