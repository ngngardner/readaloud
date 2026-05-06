defmodule ReadaloudTTS.LocalAIProvider do
  @moduledoc false
  @behaviour ReadaloudTTS.Provider

  alias ReadaloudTTS.{Catalog, Config, Voice, WordTiming}

  require Logger

  @response_format "wav"

  @known_voices %{
    "kokoro" => [
      "af_heart",
      "af_nicole",
      "af_sarah",
      "af_sky",
      "am_adam",
      "am_michael",
      "bf_emma",
      "bf_isabella",
      "bm_george",
      "bm_lewis"
    ]
  }

  @impl true
  def synthesize(text, %Voice{} = voice, opts \\ []) do
    config = Keyword.get(opts, :config, Config.from_env())

    case Req.post("#{config.base_url}/v1/audio/speech",
           json: %{
             model: voice.model,
             input: text,
             voice: voice.voice,
             speed: voice.speed,
             response_format: @response_format
           },
           receive_timeout: 300_000,
           retry: :transient,
           retry_delay: &retry_delay/1,
           max_retries: 8
         ) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

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
             file: {audio, filename: "audio.wav", content_type: "audio/wav"},
             model: config.stt_model,
             response_format: "verbose_json"
           ],
           receive_timeout: 300_000,
           retry: :transient,
           retry_delay: &retry_delay/1,
           max_retries: 8
         ) do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        {:ok, extract_word_timings(body)}

      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        Logger.warning(
          "LocalAI returned string body for transcription; Req failed to auto-decode"
        )

        case Jason.decode(body) do
          {:ok, parsed} -> {:ok, extract_word_timings(parsed)}
          {:error, _} -> {:error, "Failed to parse transcription response"}
        end

      {:ok, %{status: status, body: body}} ->
        {:error, "Transcription failed with status #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def catalog(opts \\ []) do
    config = Keyword.get(opts, :config, Config.from_env())

    case Req.get("#{config.base_url}/v1/models") do
      {:ok, %{status: 200, body: %{"data" => models}}} ->
        entries =
          models
          |> Enum.filter(&tts_model?/1)
          |> Enum.map(fn m ->
            %Catalog.Entry{
              model: m["id"],
              voices: Map.get(@known_voices, m["id"], [])
            }
          end)
          |> Enum.reject(&(&1.voices == []))

        {:ok, entries}

      {:ok, %{status: status}} ->
        {:error, "LocalAI returned #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp tts_model?(%{"id" => id}) when is_binary(id),
    do: String.contains?(id, ["tts", "kokoro", "piper"])

  defp tts_model?(_), do: false

  defp retry_delay(attempt), do: min(1_000 * Integer.pow(2, attempt), 30_000)

  defp extract_word_timings(%{"segments" => segments}) when is_list(segments) do
    Enum.flat_map(segments, &segment_timings/1)
  end

  defp extract_word_timings(_), do: []

  defp segment_timings(%{"words" => words}) when is_list(words) do
    Enum.map(words, fn w ->
      %WordTiming{
        word: w["word"] |> to_string() |> String.trim(),
        start_ms: round((w["start"] || 0) * 1000),
        end_ms: round((w["end"] || 0) * 1000)
      }
    end)
  end

  defp segment_timings(%{"start" => start_s, "end" => end_s, "text" => text}) do
    text
    |> String.split(~r/\s+/, trim: true)
    |> Enum.map(fn word ->
      %WordTiming{
        word: word,
        start_ms: round(start_s * 1000),
        end_ms: round(end_s * 1000)
      }
    end)
  end

  defp segment_timings(_), do: []
end
