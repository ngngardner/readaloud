defmodule ReadaloudTTS do
  alias ReadaloudTTS.LocalAIProvider

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
end
