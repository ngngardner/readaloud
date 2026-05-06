defmodule ReadaloudTTS do
  @moduledoc """
  Text-to-speech and transcription API.

  Consumers work with three value types:

    * `ReadaloudTTS.Voice` — the (model, voice, speed) bundle used for synthesis
    * `ReadaloudTTS.WordTiming` — a word with its start/end offset in the audio
    * `ReadaloudTTS.Catalog.Entry` — a TTS model and the voices it supports

  Example:

      voice = %ReadaloudTTS.Voice{model: "kokoro", voice: "af_heart"}

      with {:ok, audio}   <- ReadaloudTTS.synthesize("Hello world", voice),
           {:ok, timings} <- ReadaloudTTS.transcribe(audio) do
        # audio   :: binary (WAV)
        # timings :: [%ReadaloudTTS.WordTiming{}]
      end

  Provider selection is a test seam. Pass `provider: SomeModule` in the opts
  of any API call to dispatch through a `ReadaloudTTS.Provider` implementation
  other than the default (`ReadaloudTTS.LocalAIProvider`).
  """

  alias ReadaloudTTS.{Catalog, LocalAIProvider, Voice, WordTiming}

  @type result(t) :: {:ok, t} | {:error, term()}

  @spec synthesize(String.t(), Voice.t(), keyword()) :: result(binary())
  def synthesize(text, %Voice{model: model, voice: voice_id} = voice, opts \\ [])
      when is_binary(text) and is_binary(model) and is_binary(voice_id) do
    provider(opts).synthesize(text, voice, opts)
  end

  @spec transcribe(binary(), keyword()) :: result([WordTiming.t()])
  def transcribe(audio, opts \\ []) when is_binary(audio) do
    provider(opts).transcribe(audio, opts)
  end

  @spec catalog(keyword()) :: result([Catalog.Entry.t()])
  def catalog(opts \\ []) do
    provider(opts).catalog(opts)
  end

  defp provider(opts), do: Keyword.get(opts, :provider, LocalAIProvider)
end
