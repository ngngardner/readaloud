defmodule ReadaloudTTS.LocalAIProvider do
  @behaviour ReadaloudTTS.Provider

  alias ReadaloudTTS.Config

  @impl true
  def synthesize(text, opts \\ []) do
    config = Keyword.get(opts, :config, Config.from_env())

    case Req.post("#{config.base_url}/v1/audio/speech",
           json: %{
             model: config.tts_model,
             input: text,
             voice: config.voice,
             speed: config.speed,
             response_format: config.response_format
           }
         ) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, %{audio: body}}

      {:ok, %{status: status, body: body}} ->
        {:error, "TTS failed with status #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def transcribe(audio, opts \\ []) do
    config = Keyword.get(opts, :config, Config.from_env())

    case Req.post("#{config.base_url}/v1/audio/transcriptions",
           form_multipart: [
             file: {"audio.wav", audio, content_type: "audio/wav"},
             model: config.stt_model,
             response_format: "verbose_json",
             timestamp_granularities: "word"
           ]
         ) do
      {:ok, %{status: 200, body: %{"words" => words}}} ->
        timings =
          Enum.map(words, fn w ->
            %{
              word: w["word"],
              start_ms: round(w["start"] * 1000),
              end_ms: round(w["end"] * 1000)
            }
          end)

        {:ok, timings}

      {:ok, %{status: status, body: body}} ->
        {:error, "Transcription failed with status #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def list_voices do
    config = Config.from_env()

    case Req.get("#{config.base_url}/v1/models") do
      {:ok, %{status: 200, body: %{"data" => models}}} ->
        {:ok, models}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
