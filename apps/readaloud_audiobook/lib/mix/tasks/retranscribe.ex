defmodule Mix.Tasks.Readaloud.Retranscribe do
  @moduledoc """
  Re-transcribe existing chapter audio to fix word timings.

  Splits the audio into time-based chunks, transcribes each via Whisper STT
  to get word-level timings, accumulates with offsets, then aligns against
  the full source text.

  ## Usage

      mix readaloud.retranscribe --book 3           # all chapters in book 3
      mix readaloud.retranscribe --chapter 29       # single chapter by ID
      mix readaloud.retranscribe --book 3 --dry-run # preview without writing
  """
  use Mix.Task

  alias ReadaloudAudiobook.{ChapterAudio, TimingAligner}
  alias ReadaloudLibrary.Repo

  import Ecto.Query

  require Logger

  # 24kHz, 16-bit, mono = 48000 bytes/sec
  @bytes_per_second 48_000
  # 30 seconds per chunk keeps us well under the 50MB gRPC limit
  @chunk_seconds 30
  @wav_header_size 44

  @impl Mix.Task
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [book: :integer, chapter: :integer, dry_run: :boolean]
      )

    Mix.Task.run("app.start")

    chapter_audios = load_chapter_audios(opts)

    if Enum.empty?(chapter_audios) do
      Mix.shell().info("No chapter audios found matching criteria.")
      System.halt(0)
    end

    Mix.shell().info("Found #{length(chapter_audios)} chapter(s) to retranscribe")

    for ca <- chapter_audios do
      retranscribe_chapter(ca, opts)
    end
  end

  defp retranscribe_chapter(ca, opts) do
    chapter = ReadaloudLibrary.get_chapter!(ca.chapter_id)
    Mix.shell().info("\n--- Chapter #{chapter.number}: #{chapter.title} ---")
    Mix.shell().info("Audio: #{ca.audio_path} (#{Float.round(ca.duration_seconds, 1)}s)")

    with {:ok, text} <- ReadaloudLibrary.get_chapter_content(chapter),
         clean_text = strip_html(text),
         {:ok, audio} <- File.read(ca.audio_path) do
      pcm_data = binary_part(audio, @wav_header_size, byte_size(audio) - @wav_header_size)
      chunk_bytes = @chunk_seconds * @bytes_per_second
      total_chunks = ceil(byte_size(pcm_data) / chunk_bytes)

      Mix.shell().info("Splitting into #{total_chunks} chunks of #{@chunk_seconds}s each")

      # Transcribe each audio chunk
      {all_timings, _} =
        0..(total_chunks - 1)
        |> Enum.reduce({[], 0}, fn chunk_idx, {timings_acc, offset_ms} ->
          start_byte = chunk_idx * chunk_bytes
          end_byte = min(start_byte + chunk_bytes, byte_size(pcm_data))
          chunk_pcm = binary_part(pcm_data, start_byte, end_byte - start_byte)
          chunk_wav = build_wav(chunk_pcm)
          chunk_duration_ms = round(byte_size(chunk_pcm) / @bytes_per_second * 1000)

          Mix.shell().info(
            "  Chunk #{chunk_idx + 1}/#{total_chunks}: " <>
              "#{Float.round(offset_ms / 1000, 1)}s - " <>
              "#{Float.round((offset_ms + chunk_duration_ms) / 1000, 1)}s"
          )

          case ReadaloudTTS.transcribe(chunk_wav) do
            {:ok, chunk_timings} ->
              # Offset timings by accumulated position
              offset_timings =
                Enum.map(chunk_timings, fn t ->
                  %{t | start_ms: t.start_ms + offset_ms, end_ms: t.end_ms + offset_ms}
                end)

              Mix.shell().info("    #{length(chunk_timings)} words")
              {timings_acc ++ offset_timings, offset_ms + chunk_duration_ms}

            {:error, reason} ->
              Mix.shell().error("    Transcription failed: #{inspect(reason)}")
              {timings_acc, offset_ms + chunk_duration_ms}
          end
        end)

      Mix.shell().info("Total STT words: #{length(all_timings)}")

      # Align against full source text
      aligned = TimingAligner.align(all_timings, clean_text)
      Mix.shell().info("Aligned to #{length(aligned)} source words")

      if length(aligned) > 0 do
        first = hd(aligned)
        last = List.last(aligned)

        Mix.shell().info(
          "  Range: #{first.start_ms}ms - #{last.end_ms}ms " <>
            "(audio: #{round(ca.duration_seconds * 1000)}ms)"
        )

        if opts[:dry_run] do
          Mix.shell().info("  [DRY RUN] Would update word_timings")
        else
          ca
          |> ChapterAudio.changeset(%{word_timings: Jason.encode!(aligned)})
          |> Repo.update!()

          Mix.shell().info("  Updated word_timings successfully")
        end
      else
        Mix.shell().error("  No aligned timings produced!")
      end
    else
      {:error, reason} ->
        Mix.shell().error("  Failed: #{inspect(reason)}")
    end
  end

  defp build_wav(pcm_data) do
    data_size = byte_size(pcm_data)

    <<
      "RIFF",
      36 + data_size::little-32,
      "WAVE",
      "fmt ",
      16::little-32,
      1::little-16,
      1::little-16,
      24_000::little-32,
      48_000::little-32,
      2::little-16,
      16::little-16,
      "data",
      data_size::little-32,
      pcm_data::binary
    >>
  end

  defp load_chapter_audios(opts) do
    query =
      from(ca in ChapterAudio,
        join: c in ReadaloudLibrary.Chapter,
        on: c.id == ca.chapter_id,
        order_by: [asc: c.number]
      )

    query =
      case opts[:book] do
        nil -> query
        book_id -> from([ca, c] in query, where: c.book_id == ^book_id)
      end

    query =
      case opts[:chapter] do
        nil -> query
        chapter_id -> from([ca, c] in query, where: ca.chapter_id == ^chapter_id)
      end

    Repo.all(query)
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
end
