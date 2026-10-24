defmodule ReadaloudAudiobook.Planner.Text do
  @moduledoc """
  Chapter HTML to paragraphs, and paragraphs to quote-level units: a quotation
  is its own unit, so the narration around it and the speech in it can be read
  from different clips.
  """

  # Their bodies are code, not prose (an ad <script> was once read aloud).
  @opaque_blocks ~r/<(script|style|iframe)\b[^>]*>.*?<\/\1\s*>/is
  @breaks ~r/<\s*br\s*\/?>|<\/\s*(p|div|h\d|li)\s*>/i
  @header ~r/^\s*(Translator|Editor|Proofreader)\s*:/i
  @entity ~r/&(#[xX][0-9a-fA-F]+|#\d+|[a-zA-Z]+);/

  @named %{
    "amp" => "&",
    "lt" => "<",
    "gt" => ">",
    "quot" => "\"",
    "apos" => "'",
    "nbsp" => " ",
    "lsquo" => "‘",
    "rsquo" => "’",
    "ldquo" => "“",
    "rdquo" => "”",
    "hellip" => "…",
    "mdash" => "—",
    "ndash" => "–",
    "middot" => "·",
    "bull" => "•",
    "laquo" => "«",
    "raquo" => "»"
  }

  @quote_close %{"“" => "”", "\"" => "\""}

  @doc "Non-empty paragraphs of a chapter, without translator/editor credit lines."
  @spec paragraphs(String.t()) :: [String.t()]
  def paragraphs(html) do
    html
    |> String.replace(@opaque_blocks, " ")
    |> String.replace(@breaks, "\n")
    |> String.replace(~r/<[^>]+>/, "")
    |> unescape()
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == "" or Regex.match?(@header, &1)))
  end

  @doc """
  Each paragraph cut into quoted and unquoted runs, in order; they rejoin to the
  paragraph exactly. An unclosed quote runs to the end of its paragraph.
  """
  @spec units([String.t()]) :: [%{para: non_neg_integer(), text: String.t(), quoted: boolean()}]
  def units(paragraphs) do
    paragraphs
    |> Enum.with_index()
    |> Enum.flat_map(fn {para, p} ->
      para
      |> split_quotes([])
      |> Enum.map(fn {text, quoted} -> %{para: p, text: text, quoted: quoted} end)
    end)
  end

  defp split_quotes("", acc), do: Enum.reverse(acc)

  defp split_quotes(rest, acc) do
    case :binary.match(rest, Map.keys(@quote_close)) do
      :nomatch ->
        Enum.reverse([{rest, false} | acc])

      {start, len} ->
        open = binary_part(rest, start, len)
        acc = if start > 0, do: [{binary_part(rest, 0, start), false} | acc], else: acc
        after_open = binary_part(rest, start + len, byte_size(rest) - start - len)

        {quoted, rest} =
          case :binary.match(after_open, @quote_close[open]) do
            :nomatch ->
              {open <> after_open, ""}

            {close, clen} ->
              {open <> binary_part(after_open, 0, close + clen),
               binary_part(after_open, close + clen, byte_size(after_open) - close - clen)}
          end

        split_quotes(rest, [{quoted, true} | acc])
    end
  end

  defp unescape(text) do
    Regex.replace(@entity, text, fn whole, entity ->
      case entity do
        "#x" <> hex -> codepoint(Integer.parse(hex, 16), whole)
        "#X" <> hex -> codepoint(Integer.parse(hex, 16), whole)
        "#" <> dec -> codepoint(Integer.parse(dec), whole)
        name -> Map.get(@named, name, whole)
      end
    end)
  end

  defp codepoint({cp, ""}, _whole) when cp in 1..0xD7FF or cp in 0xE000..0x10FFFF,
    do: <<cp::utf8>>

  defp codepoint(_, whole), do: whole
end
