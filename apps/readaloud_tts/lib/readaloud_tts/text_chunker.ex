defmodule ReadaloudTTS.TextChunker do
  @moduledoc """
  Splits long text into chunks at natural boundaries for TTS processing.

  Ported from monorepo ep-tts TextChunker. Tries split points in order:
  sentence end > semicolon/colon > comma > whitespace.
  """

  @default_max_chars 1500

  @split_patterns [
    ~r/[.!?]["'\x{201d}\x{2019})\]]*\s+/u,
    ~r/[;:]\s+/,
    ~r/,\s+/,
    ~r/\s+/
  ]

  def chunk(text, max_chars \\ @default_max_chars) do
    text = String.trim(text)

    if String.length(text) <= max_chars do
      [text]
    else
      do_chunk(text, max_chars, [])
    end
  end

  defp do_chunk("", _max_chars, acc), do: Enum.reverse(acc)

  defp do_chunk(remaining, max_chars, acc) do
    remaining = String.trim(remaining)

    if String.length(remaining) <= max_chars do
      Enum.reverse([remaining | acc])
    else
      window = String.slice(remaining, 0, max_chars)

      case find_split_point(window) do
        nil ->
          # No split point at all (no whitespace) — force split at limit
          do_chunk(
            String.slice(remaining, max_chars, String.length(remaining)) |> String.trim(),
            max_chars,
            [String.trim(window) | acc]
          )

        split_pos ->
          chunk = String.slice(remaining, 0, split_pos) |> String.trim()
          rest = String.slice(remaining, split_pos, String.length(remaining)) |> String.trim()
          do_chunk(rest, max_chars, [chunk | acc])
      end
    end
  end

  defp find_split_point(text) do
    Enum.find_value(@split_patterns, fn pattern ->
      case Regex.scan(pattern, text, return: :index) do
        [] ->
          nil

        matches ->
          # Take the last match (furthest into the text = largest chunk)
          [{byte_start, byte_len}] = List.last(matches)
          byte_pos = byte_start + byte_len
          # Convert byte offset to grapheme count (Regex returns byte indices,
          # but String.slice uses grapheme indices)
          binary_part(text, 0, byte_pos) |> String.length()
      end
    end)
  end
end
