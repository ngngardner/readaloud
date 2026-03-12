defmodule ReadaloudWebWeb.LiveHelpers do
  @moduledoc "Shared helpers for all LiveViews."

  def active_task_count do
    import_count = ReadaloudImporter.list_tasks() |> Enum.count(&(&1.status in ["pending", "processing"]))
    audio_count = ReadaloudAudiobook.list_tasks() |> Enum.count(&(&1.status in ["pending", "processing"]))
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
    model = Enum.find(models, &(&1[:id] == model_id)) || %{}
    prefs["voice"] || get_in(model, [:voices]) |> List.wrap() |> List.first() || ReadaloudTTS.Config.from_env().voice
  end
end
