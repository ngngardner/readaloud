defmodule ReadaloudAudiobook.Planner.Passages do
  @moduledoc """
  Tagged units to passages (one per speaker turn), and passages with their clips
  to the chunks of a voice plan.
  """

  alias ReadaloudAudiobook.Planner.Names
  alias ReadaloudTTS.TextChunker

  @max_narration 800
  @max_chars 400

  @doc """
  One passage per speaker turn: a unit joins the passage before it when the tag is
  the same and it is in the same paragraph, or it is calm-enough narration that the
  passage stays under #{@max_narration} characters.
  """
  def build(units, tags) do
    units
    |> Enum.zip(tags)
    |> Enum.reduce({[], nil}, fn {unit, tag}, {passages, last_para} ->
      merged =
        case passages do
          [%{tag: ^tag} = prev | rest] ->
            cond do
              unit.para == last_para ->
                [%{prev | text: prev.text <> unit.text} | rest]

              tag.kind == "narration" and
                  String.length(prev.text) + String.length(unit.text) + 1 <= @max_narration ->
                [%{prev | text: prev.text <> "\n" <> unit.text} | rest]

              true ->
                nil
            end

          _ ->
            nil
        end

      {merged || [%{text: unit.text, tag: tag} | passages], unit.para}
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  @doc """
  In a paragraph with a quotation, the unquoted words are the narrator's. The model
  tags an attribution like "Fairy Bai Qing smiled bitterly: " as her speech, which
  `build/2` would then merge into her quote and read in her voice. A paragraph with
  no quotation keeps its tags: the book may quote in a way `Text` doesn't cut.
  """
  def narrate_around_quotes(units, tags) do
    quoted_paras = for u <- units, u.quoted, into: MapSet.new(), do: u.para

    Enum.zip_with(units, tags, fn unit, tag ->
      if not unit.quoted and unit.para in quoted_paras,
        do: %{tag | kind: "narration", speaker: "narrator", sex: "unknown"},
        else: tag
    end)
  end

  @doc """
  Plan chunks from `{passage_text, clip}` pairs in reading order: neighbours with the
  same clip share one request up to #{@max_chars} characters, cut like readaloud
  cuts text, and a piece with no words joins a neighbour.
  """
  def chunks(passages, name_map) do
    passages
    |> Enum.map(fn {text, clip} -> {String.trim(text), clip} end)
    |> Enum.reject(fn {text, _} -> text == "" end)
    |> Enum.reduce([], fn {text, clip}, runs ->
      case runs do
        [{^clip, prev} | rest] ->
          if String.length(prev) + 1 + String.length(text) <= @max_chars,
            do: [{clip, prev <> "\n" <> text} | rest],
            else: [{clip, text} | runs]

        _ ->
          [{clip, text} | runs]
      end
    end)
    |> Enum.reverse()
    |> Enum.flat_map(fn {clip, text} ->
      Enum.map(TextChunker.chunk(text, @max_chars), &{clip, &1})
    end)
    |> fold_wordless()
    |> Enum.map(fn {clip, piece} ->
      %{
        "text" => piece,
        "spoken" => Names.apply(piece, name_map),
        "voice" => clip.voice,
        "reference_text" => clip.text
      }
    end)
  end

  # Breeze can fail on a request with nothing to say ("***", a silent "……").
  # A wordless piece with nothing after it to join is dropped: there is nothing to say.
  defp fold_wordless(pieces) do
    {out, _pending} =
      Enum.reduce(pieces, {[], ""}, fn {clip, text}, {out, pending} ->
        cond do
          # Letters or digits, as VoicePlan requires ("____" is \w but not speech).
          Regex.match?(~r/[\p{L}\p{N}]/u, text) -> {[{clip, pending <> text} | out], ""}
          out == [] -> {out, pending <> text <> "\n"}
          true -> {[{elem(hd(out), 0), elem(hd(out), 1) <> "\n" <> text} | tl(out)], pending}
        end
      end)

    Enum.reverse(out)
  end
end
