defmodule ReadaloudAudiobook.TimingAligner do
  @moduledoc """
  Aligns Whisper STT word timings to source text using Myers diff.

  Whisper may tokenize words differently from the original text (e.g.,
  splitting "sliding" into "slidin" + "G", merging "good bye" into
  "goodbye", or inserting filler words like "uh"). This module diffs
  the normalized word sequences and maps timings accordingly, producing
  one timing entry per source word.

  Ported from monorepo ep-ln-audiobook AlignmentService.
  """

  @doc """
  Align STT word timings to source text.

  Returns a list of timing maps with `:word`, `:start_ms`, `:end_ms`,
  one per word in the source text.
  """
  def align(_timings, ""), do: []
  def align([], _source), do: []

  def align(timings, source) do
    source_words = tokenize(source)
    stt_words = Enum.map(timings, & &1.word)

    source_norm = Enum.map(source_words, &normalize/1)
    stt_norm = Enum.map(stt_words, &normalize/1)

    ops = List.myers_difference(source_norm, stt_norm)

    preliminary = build_preliminary(ops, source_words, timings)
    interpolate_missing(preliminary, timings)
  end

  # -- Tokenization --

  defp tokenize(text) do
    text
    |> String.replace(~r/[\x{2014}\x{2013}]/, " ")
    |> String.split(~r/\s+/, trim: true)
  end

  defp normalize(word) do
    word
    |> String.downcase()
    |> String.replace(~r/[^\w]/, "")
  end

  # -- Build preliminary mapping from diff ops --

  defp build_preliminary(ops, source_words, timings) do
    {result, _src_idx, _stt_idx} =
      Enum.reduce(ops, {[], 0, 0}, fn {tag, words}, {acc, src_i, stt_i} ->
        case tag do
          :eq ->
            count = length(words)

            entries =
              for i <- 0..(count - 1) do
                {Enum.at(source_words, src_i + i), Enum.at(timings, stt_i + i)}
              end

            {acc ++ entries, src_i + count, stt_i + count}

          :del ->
            # Source words not in STT — mark as unmatched
            count = length(words)

            entries =
              for i <- 0..(count - 1) do
                {Enum.at(source_words, src_i + i), nil}
              end

            {acc ++ entries, src_i + count, stt_i}

          :ins ->
            # Extra STT words — skip them (absorbed by neighbors)
            count = length(words)
            {acc, src_i, stt_i + count}
        end
      end)

    result
  end

  # -- Interpolate missing timings --

  defp interpolate_missing(preliminary, timings) do
    audio_start = if timings != [], do: hd(timings).start_ms, else: 0
    audio_end = if timings != [], do: List.last(timings).end_ms, else: 0

    do_interpolate(preliminary, 0, audio_start, audio_end)
  end

  defp do_interpolate(preliminary, idx, audio_start, audio_end) when idx >= length(preliminary),
    do: []

  defp do_interpolate(preliminary, idx, audio_start, audio_end) do
    {source_word, timing} = Enum.at(preliminary, idx)

    if timing do
      [
        %{word: source_word, start_ms: timing.start_ms, end_ms: timing.end_ms}
        | do_interpolate(preliminary, idx + 1, audio_start, audio_end)
      ]
    else
      # Collect run of unmatched words
      {run, run_len} = collect_unmatched(preliminary, idx)
      words = Enum.map(run, fn {w, _} -> w end)

      # Find bounding timestamps
      prev_end = find_prev_end(preliminary, idx, audio_start)
      next_start = find_next_start(preliminary, idx + run_len, audio_end)
      next_start = max(next_start, prev_end)

      distribute_time(words, prev_end, next_start) ++
        do_interpolate(preliminary, idx + run_len, audio_start, audio_end)
    end
  end

  defp collect_unmatched(preliminary, idx) do
    preliminary
    |> Enum.drop(idx)
    |> Enum.take_while(fn {_, timing} -> timing == nil end)
    |> then(fn run -> {run, length(run)} end)
  end

  defp find_prev_end(preliminary, idx, default) do
    if idx > 0 do
      case Enum.at(preliminary, idx - 1) do
        {_, %{end_ms: end_ms}} -> end_ms
        _ -> default
      end
    else
      default
    end
  end

  defp find_next_start(preliminary, idx, default) do
    preliminary
    |> Enum.drop(idx)
    |> Enum.find_value(fn
      {_, %{start_ms: start_ms}} -> start_ms
      _ -> nil
    end) || default
  end

  defp distribute_time(words, start_ms, end_ms) do
    total_chars = words |> Enum.map(&String.length/1) |> Enum.sum() |> max(1)
    available = end_ms - start_ms

    {entries, _} =
      Enum.map_reduce(words, start_ms, fn word, current ->
        char_count = max(String.length(word), 1)
        duration = available * char_count / total_chars
        entry = %{word: word, start_ms: current, end_ms: current + duration}
        {entry, current + duration}
      end)

    entries
  end
end
