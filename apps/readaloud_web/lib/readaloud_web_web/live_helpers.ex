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

  def fetch_models do
    case ReadaloudTTS.list_models_and_voices() do
      {:ok, models} -> models
      {:error, _} -> []
    end
  end

  def default_model(book, models) do
    prefs = book.audio_preferences || %ReadaloudLibrary.TtsProfile{}
    prefs.model || List.first(models)[:id] || ReadaloudTTS.Config.from_env().tts_model
  end

  def default_voice(book, models) do
    prefs = book.audio_preferences || %ReadaloudLibrary.TtsProfile{}
    model_id = prefs.model || List.first(models)[:id]
    model = Enum.find(models, &(&1[:id] == model_id)) || %{}

    prefs.voice || get_in(model, [:voices]) |> List.wrap() |> List.first() ||
      ReadaloudTTS.Config.from_env().voice
  end
end
