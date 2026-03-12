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
           },
           receive_timeout: 300_000
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
             file: {audio, filename: "audio.wav", content_type: "audio/wav"},
             model: config.stt_model,
             response_format: "verbose_json"
           ],
           receive_timeout: 300_000
         ) do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        {:ok, extract_word_timings(body)}

      {:ok, %{status: 200, body: body}} when is_binary(body) ->
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

  defp extract_word_timings(%{"segments" => segments}) when is_list(segments) do
    segments
    |> Enum.flat_map(fn segment ->
      case segment do
        %{"words" => words} when is_list(words) ->
          Enum.map(words, fn w ->
            %{
              word: w["word"] |> to_string() |> String.trim(),
              start_ms: round((w["start"] || 0) * 1000),
              end_ms: round((w["end"] || 0) * 1000)
            }
          end)

        # Fallback: segment without word-level data
        %{"start" => start_s, "end" => end_s, "text" => text} ->
          text
          |> String.split(~r/\s+/, trim: true)
          |> Enum.map(fn word ->
            %{word: word, start_ms: round(start_s * 1000), end_ms: round(end_s * 1000)}
          end)

        _ ->
          []
      end
    end)
  end

  defp extract_word_timings(_), do: []

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

  def list_models_and_voices(opts \\ []) do
    config = Keyword.get(opts, :config, Config.from_env())

    case Req.get("#{config.base_url}/v1/models") do
      {:ok, %{status: 200, body: %{"data" => models}}} ->
        tts_models =
          models
          |> Enum.filter(fn m -> String.contains?(m["id"] || "", ["tts", "kokoro", "piper"]) end)
          |> Enum.map(fn m ->
            model_id = m["id"]
            voices = Map.get(Config.known_voices(), model_id, [])
            %{id: model_id, voices: voices}
          end)

        {:ok, tts_models}

      {:ok, %{status: status}} ->
        {:error, "LocalAI returned #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
