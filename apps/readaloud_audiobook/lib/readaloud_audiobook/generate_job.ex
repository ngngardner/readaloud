defmodule ReadaloudAudiobook.GenerateJob do
  use Oban.Worker, queue: :tts, max_attempts: 3

  alias ReadaloudLibrary.Repo
  alias ReadaloudAudiobook.{AudiobookTask, ChapterAudio, TimingAligner}
  alias ReadaloudTTS.{Config, TextChunker}

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"task_id" => task_id}}) do
    task = Repo.get!(AudiobookTask, task_id)
    update_task(task, %{status: "processing"})

    chapter = ReadaloudLibrary.get_chapter!(task.chapter_id)

    config = Config.from_env()

    with {:ok, text} <- ReadaloudLibrary.get_chapter_content(chapter),
         clean_text = strip_html(text),
         chunks = TextChunker.chunk(clean_text),
         {:ok, audio, chunk_timings} <- synthesize_chunks(chunks, task, config) do
      audio_path = audio_storage_path(chapter)
      File.mkdir_p!(Path.dirname(audio_path))
      File.write!(audio_path, audio)

      # Final alignment pass: reconcile per-chunk timings with full source text
      timings = TimingAligner.align(chunk_timings, clean_text)

      %ChapterAudio{}
      |> ChapterAudio.changeset(%{
        chapter_id: chapter.id,
        audio_path: audio_path,
        duration_seconds: calculate_duration(audio),
        word_timings: Jason.encode!(timings)
      })
      |> Repo.insert!(on_conflict: :replace_all, conflict_target: :chapter_id)

      task = update_task(task, %{status: "completed", progress: 1.0})
      broadcast_task_update(task)
      :ok
    else
      {:error, reason} ->
        task = update_task(task, %{status: "failed", error_message: "#{inspect(reason)}"})
        broadcast_task_update(task)
        {:error, reason}
    end
  end

  defp synthesize_chunks(chunks, task, config) do
    total = length(chunks)
    Logger.info("Synthesizing #{total} chunks for task #{task.id}")

    tts_config = %{config |
      voice: task.voice || config.voice,
      speed: task.speed || config.speed,
      tts_model: task.model || config.tts_model
    }

    chunks
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, <<>>, [], 0}, fn {chunk, idx}, {:ok, audio_acc, timings_acc, offset_ms} ->
      Logger.info("Chunk #{idx}/#{total}: #{String.length(chunk)} chars")

      case ReadaloudTTS.synthesize(chunk, config: tts_config) do
        {:ok, %{audio: chunk_audio}} ->
          chunk_duration_ms = round(calculate_duration(chunk_audio) * 1000)

          # Transcribe and align to source text
          chunk_timings =
            case ReadaloudTTS.transcribe(chunk_audio) do
              {:ok, t} ->
                aligned = TimingAligner.align(t, chunk)
                # Offset timings by accumulated audio duration
                Enum.map(aligned, fn w ->
                  %{w | start_ms: w.start_ms + offset_ms, end_ms: w.end_ms + offset_ms}
                end)

              {:error, reason} ->
                Logger.warning("Transcription failed for chunk #{idx}: #{inspect(reason)}")
                []
            end

          # Strip WAV header from subsequent chunks before concatenation
          raw_audio =
            if audio_acc == <<>> do
              chunk_audio
            else
              strip_wav_header(chunk_audio)
            end

          new_audio = audio_acc <> raw_audio

          {:cont, {:ok, new_audio, timings_acc ++ chunk_timings, offset_ms + chunk_duration_ms}}

        {:error, reason} ->
          {:halt, {:error, "TTS failed on chunk #{idx}/#{total}: #{inspect(reason)}"}}
      end
    end)
    |> case do
      {:ok, audio, timings, _offset} ->
        # Fix the WAV header to reflect total size
        fixed_audio = fix_wav_header(audio)
        {:ok, fixed_audio, timings}

      {:error, _} = error ->
        error
    end
  end

  defp strip_wav_header(wav) do
    # Standard WAV header is 44 bytes
    case wav do
      <<"RIFF", _::binary-size(4), "WAVE", _rest::binary>> ->
        # Find "data" chunk
        find_data_chunk(wav, 12)

      _ ->
        wav
    end
  end

  defp find_data_chunk(wav, offset) when offset >= byte_size(wav), do: wav

  defp find_data_chunk(wav, offset) do
    case binary_part(wav, offset, min(4, byte_size(wav) - offset)) do
      "data" ->
        # Skip chunk ID (4) + chunk size (4) = 8 bytes
        data_start = offset + 8
        binary_part(wav, data_start, byte_size(wav) - data_start)

      _ ->
        # Skip chunk ID (4), read chunk size (4), skip to next chunk
        if offset + 8 <= byte_size(wav) do
          <<_::binary-size(offset), _id::binary-size(4), size::little-32, _::binary>> = wav
          find_data_chunk(wav, offset + 8 + size)
        else
          wav
        end
    end
  end

  defp fix_wav_header(wav) do
    case wav do
      <<"RIFF", _::little-32, "WAVE", after_wave::binary>> ->
        # Extract all PCM data after the "data" chunk header
        case extract_pcm_data(after_wave, 0) do
          {:ok, pcm_data} -> build_wav(pcm_data)
          :error -> wav
        end

      _ ->
        wav
    end
  end

  defp extract_pcm_data(binary, offset) when offset + 8 > byte_size(binary), do: :error

  defp extract_pcm_data(binary, offset) do
    <<_::binary-size(offset), chunk_id::binary-size(4), chunk_size::little-32, _::binary>> =
      binary

    if chunk_id == "data" do
      # All bytes after this header are PCM (including appended chunks)
      data_start = offset + 8
      {:ok, binary_part(binary, data_start, byte_size(binary) - data_start)}
    else
      extract_pcm_data(binary, offset + 8 + chunk_size)
    end
  end

  # Build a complete WAV file from raw PCM data (24kHz, 16-bit, mono)
  defp build_wav(pcm_data) do
    data_size = byte_size(pcm_data)

    <<
      "RIFF", (36 + data_size)::little-32, "WAVE",
      "fmt ", 16::little-32,
      1::little-16,
      1::little-16,
      24000::little-32,
      48000::little-32,
      2::little-16,
      16::little-16,
      "data", data_size::little-32,
      pcm_data::binary
    >>
  end

  defp strip_html(html) do
    html
    |> String.replace(~r/<[^>]+>/, " ")
    |> String.replace(~r/&[^;]+;/, " ")
    |> String.replace("\u2014", " ")
    |> String.replace("\u2013", " ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp update_task(task, attrs) do
    task |> AudiobookTask.changeset(attrs) |> Repo.update!()
  end

  defp broadcast_task_update(task) do
    Phoenix.PubSub.broadcast(ReadaloudWeb.PubSub, "tasks:audiobook:#{task.book_id}", {:task_updated, task})
    Phoenix.PubSub.broadcast(ReadaloudWeb.PubSub, "tasks:audiobook", {:task_updated, task})
  end

  defp audio_storage_path(chapter) do
    base = System.get_env("STORAGE_PATH", "priv/static/files")
    padded = String.pad_leading("#{chapter.number}", 3, "0")
    Path.join([base, "books", "#{chapter.book_id}", "chapters", "#{padded}.wav"])
  end

  defp calculate_duration(wav_bytes) do
    # 24kHz, 16-bit mono
    byte_size(wav_bytes) / (24000 * 2)
  end
end
