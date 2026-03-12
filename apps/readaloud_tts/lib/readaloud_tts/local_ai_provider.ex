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
             response_format: "vtt"
           ]
         ) do
      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        {:ok, parse_vtt_timings(body)}

      {:ok, %{status: status, body: body}} ->
        {:error, "Transcription failed with status #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_vtt_timings(vtt) do
    vtt
    |> String.split("\n\n")
    |> Enum.flat_map(fn block ->
      case Regex.run(~r/(\d{2}:\d{2}:\d{2}\.\d{3}) --> (\d{2}:\d{2}:\d{2}\.\d{3})\n(.+)/s, block) do
        [_, start_ts, end_ts, text] ->
          text
          |> String.split(~r/\s+/)
          |> Enum.reject(&(&1 == ""))
          |> Enum.map(fn word ->
            %{word: word, start_ms: parse_ts(start_ts), end_ms: parse_ts(end_ts)}
          end)

        _ ->
          []
      end
    end)
  end

  defp parse_ts(ts) do
    [h, m, rest] = String.split(ts, ":")
    [s, ms] = String.split(rest, ".")
    String.to_integer(h) * 3_600_000 + String.to_integer(m) * 60_000 +
      String.to_integer(s) * 1_000 + String.to_integer(ms)
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
