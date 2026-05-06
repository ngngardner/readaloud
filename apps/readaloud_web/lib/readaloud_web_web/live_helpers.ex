defmodule ReadaloudWebWeb.LiveHelpers do
  @moduledoc "Shared helpers for all LiveViews."

  # Cross-runtime contract: every word in chapter text is wrapped in a span
  # carrying this attribute. The TS side reads it via wordSelector(i) in
  # assets/js/lib/types.ts — keep the string in sync if you rename it.
  @word_index_attr "data-word-index"

  def word_index_attr, do: @word_index_attr

  def word_span(text, index) do
    ~s(<span class="word" #{@word_index_attr}="#{index}">#{text}</span>)
  end

  def active_task_count do
    alias ReadaloudLibrary.Tasks.Query, as: TaskQuery

    TaskQuery.active_count(ReadaloudImporter.ImportTask) +
      TaskQuery.active_count(ReadaloudAudiobook.AudiobookTask)
  end

  def fetch_catalog do
    case ReadaloudTTS.catalog() do
      {:ok, entries} -> entries
      {:error, _} -> []
    end
  end

  def default_model(book, catalog) do
    prefs = book.audio_preferences || %ReadaloudLibrary.TtsProfile{}
    first = List.first(catalog)
    prefs.model || (first && first.model)
  end

  def default_voice(book, catalog) do
    prefs = book.audio_preferences || %ReadaloudLibrary.TtsProfile{}
    first = List.first(catalog)
    model_id = prefs.model || (first && first.model)
    entry = Enum.find(catalog, &(&1.model == model_id))

    prefs.voice || (entry && List.first(entry.voices))
  end
end
