defmodule ReadaloudAudiobook.GenerateJob do
  use Oban.Worker, queue: :tts, max_attempts: 3

  alias ReadaloudLibrary.Repo
  alias ReadaloudAudiobook.{AudiobookTask, ChapterAudio}
  alias ReadaloudTTS.TextChunker

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"task_id" => task_id}}) do
    task = Repo.get!(AudiobookTask, task_id)
    update_task(task, %{status: "processing"})

    chapter = ReadaloudLibrary.get_chapter!(task.chapter_id)

    with {:ok, text} <- ReadaloudLibrary.get_chapter_content(chapter),
         clean_text = strip_html(text),
         chunks = TextChunker.chunk(clean_text),
         {:ok, audio, timings} <- synthesize_chunks(chunks, task) do
      audio_path = audio_storage_path(chapter)
      File.mkdir_p!(Path.dirname(audio_path))
      File.write!(audio_path, audio)

      %ChapterAudio{}
      |> ChapterAudio.changeset(%{
        chapter_id: chapter.id,
        audio_path: audio_path,
        duration_seconds: calculate_duration(audio),
        word_timings: Jason.encode!(timings)
      })
      |> Repo.insert!(on_conflict: :replace_all, conflict_target: :chapter_id)

      update_task(task, %{status: "completed", progress: 1.0})
      :ok
    else
      {:error, reason} ->
        update_task(task, %{status: "failed", error_message: "#{inspect(reason)}"})
        {:error, reason}
    end
  end

  defp synthesize_chunks(chunks, task) do
    total = length(chunks)
    Logger.info("Synthesizing #{total} chunks for task #{task.id}")

    chunks
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, <<>>, [], 0}, fn {chunk, idx}, {:ok, audio_acc, timings_acc, offset_ms} ->
      Logger.info("Chunk #{idx}/#{total}: #{String.length(chunk)} chars")

      case ReadaloudTTS.synthesize(chunk, voice: task.voice, speed: task.speed) do
        {:ok, %{audio: chunk_audio}} ->
          chunk_duration_ms = round(calculate_duration(chunk_audio) * 1000)

          # Transcribe this chunk for timings
          chunk_timings =
            case ReadaloudTTS.transcribe(chunk_audio) do
              {:ok, t} ->
                # Offset timings by accumulated audio duration
                Enum.map(t, fn w ->
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
      <<"RIFF", _old_size::little-32, rest::binary>> ->
        new_size = byte_size(rest)
        <<"RIFF", new_size::little-32, rest::binary>>

      _ ->
        wav
    end
  end

  defp strip_html(html) do
    html
    |> String.replace(~r/<[^>]+>/, " ")
    |> String.replace(~r/&[^;]+;/, " ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp update_task(task, attrs) do
    task |> AudiobookTask.changeset(attrs) |> Repo.update!()
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
