defmodule ReadaloudTTS do
  alias ReadaloudTTS.LocalAIProvider

  @cache_ttl_ms :timer.minutes(5)

  def synthesize(text, opts \\ []) do
    provider = Keyword.get(opts, :provider, LocalAIProvider)
    provider.synthesize(text, opts)
  end

  def transcribe(audio, opts \\ []) do
    provider = Keyword.get(opts, :provider, LocalAIProvider)
    provider.transcribe(audio, opts)
  end

  def list_voices(opts \\ []) do
    provider = Keyword.get(opts, :provider, LocalAIProvider)
    provider.list_voices()
  end

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
end
