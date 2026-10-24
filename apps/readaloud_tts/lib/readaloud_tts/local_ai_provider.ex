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
    ],
    "breeze-tts-2" => ["heath-miller"]
  }

  # Voices cloned from a reference clip rather than picked from a model's
  # presets. LocalAI's audio-cpp backend treats `voice` as a clone reference
  # when it names a WAV that exists inside the LocalAI container, and Breeze
  # also wants that clip's transcript. The clips live in LocalAI's models dir
  # (/internalmedia/localai-models/voices on phanteks).
  @cloned_voices %{
    {"breeze-tts-2", "heath-miller"} => %{
      # He Who Fights with Monsters book 1, ch. 10: plain narration, no
      # character voices, so the clone picks up his narrating register.
      voice: "/models/voices/heath-miller.wav",
      text:
        "The walls were black, like some long, dormant magma chamber. But even " <>
          "starting from a natural cavern, it would have been a monumental labor " <>
          "to bring it to its current state."
    }
  }

  # Breeze samples each request's delivery fresh, so long requests drift in
  # pitch and pace within themselves. ~400 characters is what it was
  # evaluated at; everything else keeps the TextChunker default.
  @max_chunk_chars %{"breeze-tts-2" => 400}

  @impl true
  def synthesize(text, %Voice{} = voice, opts \\ []) do
    config = Keyword.get(opts, :config, Config.from_env())

    case Req.post("#{config.base_url}/v1/audio/speech",
           json: speech_body(text, voice, opts),
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
  def max_chunk_chars(%Voice{model: model}), do: Map.get(@max_chunk_chars, model)

  @doc false
  # Public so the request contract with LocalAI can be tested without a server.
  #
  # A cloned voice can be given another clip of the same narrator for one
  # request (`reference: %{voice: container_path, text: transcript}`) and a
  # sampling `temperature`; a voice plan uses these to read each passage from
  # a clip of him in the matching register. Preset voices have no clip, so
  # both are ignored for them.
  def speech_body(text, %Voice{} = voice, opts \\ []) do
    case Map.get(@cloned_voices, {voice.model, voice.voice}) do
      nil ->
        %{
          model: voice.model,
          input: text,
          voice: voice.voice,
          speed: voice.speed,
          response_format: @response_format
        }

      default_clone ->
        clone = Keyword.get(opts, :reference, default_clone)
        # No `speed`: LocalAI forwards it to the backend as a request option,
        # and Breeze refuses any option it does not know. Likewise the
        # transcript goes as `reference_text`, Breeze's own name for it, not
        # LocalAI's `ref_text` alias. A fixed seed keeps the delivery steady
        # from chunk to chunk and makes a regenerated chapter come out the same.
        %{
          model: voice.model,
          input: text,
          voice: clone.voice,
          response_format: @response_format,
          params:
            %{
              reference_text: clone.text,
              seed: "42",
              # Readaloud already chunks; stop the backend re-splitting a chunk.
              text_chunk_size: "2000"
            }
            |> put_temperature(Keyword.get(opts, :temperature))
        }
    end
  end

  # Breeze takes every option as a string.
  defp put_temperature(params, nil), do: params
  defp put_temperature(params, t), do: Map.put(params, :temperature, to_string(t))

  @impl true
  def transcribe(audio, opts \\ []) do
    config = Keyword.get(opts, :config, Config.from_env())

    case Req.post("#{config.base_url}/v1/audio/transcriptions",
           form_multipart: [
             file: {audio, filename: "audio.wav", content_type: "audio/wav"},
             model: config.stt_model,
             response_format: "verbose_json",
             # Upstream LocalAI gates faster-whisper's word alignment on this
             # field (`word_timestamps = "word" in request.timestamp_granularities`).
             # The old ngngardner/LocalAI fork emitted words unconditionally, so
             # this was unnecessary until we moved to the upstream image and
             # silently started getting segment-level timings instead.
             "timestamp_granularities[]": "word"
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

    # No retry: the catalog populates a voices dropdown, and callers
    # (BookLive/ReaderLive handle_info) run it inside the LV process —
    # Req's default 1s+2s+4s backoff would block the view for 7s
    # whenever LocalAI is down. Fail fast and render an empty catalog.
    case Req.get("#{config.base_url}/v1/models", retry: false) do
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

  @doc false
  # Public only so the response-shape contract with LocalAI can be tested
  # directly; the shape has changed underneath us once already.
  def extract_word_timings(%{"segments" => segments}) when is_list(segments) do
    Enum.flat_map(segments, &segment_timings/1)
  end

  def extract_word_timings(_), do: []

  # Upstream LocalAI names the word field "text"; the old fork named it "word".
  defp segment_timings(%{"words" => words}) when is_list(words) do
    Enum.map(words, fn w ->
      %WordTiming{
        word: (w["text"] || w["word"]) |> to_string() |> String.trim(),
        start_ms: round((w["start"] || 0) * 1000),
        end_ms: round((w["end"] || 0) * 1000)
      }
    end)
  end

  # Segment-level fallback: every word in the segment gets the segment's own
  # start/end, which reads as "highlighting works" while being far too coarse
  # to follow. That is a misconfiguration (word alignment was not requested or
  # not honoured), not a normal response, so say so loudly rather than emitting
  # smeared timings in silence.
  defp segment_timings(%{"start" => start_s, "end" => end_s, "text" => text}) do
    Logger.warning(
      "Transcription segment has no word-level timings; falling back to " <>
        "segment-level. Check that LocalAI honours timestamp_granularities[]=word."
    )

    :telemetry.execute([:readaloud, :tts, :segment_level_timings], %{count: 1}, %{})

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
