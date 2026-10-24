defmodule ReadaloudAudiobook.Planner.Names do
  @moduledoc """
  Pinyin names respelled in English letters so the narrator voice says them close
  to standard Mandarin ("Feng Jiu Ge" → "Fung Jyo Guhh"), and the substitution of
  those respellings, plus word fixes, into the text the voice reads.

  The spellings were chosen by ear-proxy in tools/voice-refs (`names-probe`): the
  voice reads each candidate and Whisper must hear it as meant.
  """

  @initials %{
    "zh" => "j",
    "ch" => "ch",
    "sh" => "sh",
    "b" => "b",
    "p" => "p",
    "m" => "m",
    "f" => "f",
    "d" => "d",
    "t" => "t",
    "n" => "n",
    "l" => "l",
    "g" => "g",
    "k" => "k",
    "h" => "h",
    "j" => "j",
    "q" => "ch",
    "x" => "sh",
    "r" => "r",
    "z" => "dz",
    "c" => "ts",
    "s" => "s"
  }
  @initials_longest_first Enum.sort_by(Map.keys(@initials), &(-String.length(&1)))

  @finals %{
    "a" => "ah",
    "o" => "aw",
    "e" => "uh",
    "ai" => "ye",
    "ei" => "ay",
    "ao" => "ow",
    "ou" => "oh",
    "an" => "ahn",
    "en" => "un",
    "ang" => "ahng",
    "eng" => "ung",
    "ong" => "ong",
    "i" => "ee",
    "ia" => "yah",
    "ie" => "yeh",
    "iao" => "yow",
    "iu" => "yo",
    "ian" => "yen",
    "in" => "een",
    "iang" => "yahng",
    "ing" => "ing",
    "iong" => "yong",
    "u" => "oo",
    "ua" => "wah",
    "uo" => "waw",
    "uai" => "wye",
    "ui" => "way",
    "uan" => "wahn",
    "un" => "wun",
    "uang" => "wahng",
    "ue" => "yweh",
    "ü" => "yoo",
    "üe" => "yweh",
    "üan" => "yoo-en",
    "ün" => "yoon"
  }
  # After j/q/x a written "u" is ü.
  @jqx_finals %{"u" => "yoo", "ue" => "weh", "uan" => "wen", "un" => "yoon"}
  # "-i" after these initials is the buzzing apical vowel, not "ee".
  @apical %{
    "zh" => "r",
    "ch" => "r",
    "sh" => "r",
    "r" => "r",
    "z" => "uh",
    "c" => "uh",
    "s" => "uh"
  }
  @whole %{
    "ya" => "yah",
    "ye" => "yeh",
    "yao" => "yow",
    "you" => "yoh",
    "yan" => "yen",
    "yin" => "yeen",
    "yang" => "yahng",
    "ying" => "ying",
    "yong" => "yong",
    "yu" => "yoo",
    "yue" => "yweh",
    "yuan" => "yoo-en",
    "yun" => "yoon",
    "yi" => "ee",
    "wa" => "wah",
    "wo" => "waw",
    "wai" => "wye",
    "wei" => "way",
    "wan" => "wahn",
    "wen" => "wun",
    "wang" => "wahng",
    "weng" => "wung",
    "wu" => "woo",
    "a" => "ah",
    "o" => "aw",
    "e" => "uh",
    "ai" => "eye",
    "ei" => "ay",
    "ao" => "ow",
    "ou" => "oh",
    "an" => "ahn",
    "en" => "un",
    "ang" => "ahng",
    "eng" => "ung",
    "er" => "ar"
  }

  @doc "English respelling of a pinyin name, or nil if any word is not pinyin."
  @spec respell(String.t()) :: String.t() | nil
  def respell(name) do
    words =
      name
      |> String.downcase()
      |> String.replace("v", "ü")
      |> String.split()

    spelled =
      Enum.map(words, fn word ->
        case parse(String.graphemes(word)) do
          nil -> nil
          syllables -> syllables |> Enum.map_join(&syllable/1) |> capitalize()
        end
      end)

    if spelled == [] or Enum.any?(spelled, &is_nil/1), do: nil, else: Enum.join(spelled, " ")
  end

  @doc """
  Respellings for pinyin names of two or more words not already known. Learned
  names apply to the whole book, and a one-word name ("Long", "Men") is too often
  an English word: respelling it would change ordinary prose.
  """
  @spec new_names([String.t()], String.t(), map()) :: %{String.t() => String.t()}
  def new_names(found, text, known) do
    for name <- Enum.map(found, &String.trim/1),
        String.contains?(name, " "),
        not Map.has_key?(known, name),
        String.contains?(text, name),
        spelled = respell(name),
        spelled != nil,
        into: %{},
        do: {name, spelled}
  end

  @doc """
  Substitutes `mapping` into `text`, longest keys first. Capitalised keys are names
  and match exactly; lowercase keys are word fixes ("feathermen" → "feather men")
  that match in any case and keep a leading capital.
  """
  @spec apply(String.t(), map()) :: String.t()
  def apply(text, mapping) when map_size(mapping) == 0, do: text

  def apply(text, mapping) do
    alternatives =
      mapping
      |> Map.keys()
      |> Enum.sort_by(&(-String.length(&1)))
      |> Enum.map_join("|", fn key ->
        if key == String.downcase(key),
          do: "(?i:#{Regex.escape(key)})",
          else: Regex.escape(key)
      end)

    pattern = Regex.compile!("\\b(" <> alternatives <> ")\\b", "u")

    Regex.replace(pattern, text, fn found, _ ->
      case Map.fetch(mapping, found) do
        {:ok, replacement} ->
          replacement

        :error ->
          fix = Map.fetch!(mapping, String.downcase(found))
          if upper?(String.first(found)), do: capitalize(fix), else: fix
      end
    end)
  end

  # Longest syllable first, backtracking when the rest of the word will not parse.
  defp parse([]), do: []

  defp parse(graphemes) do
    min(6, length(graphemes))..1//-1
    |> Enum.find_value(fn n ->
      {head, rest} = Enum.split(graphemes, n)
      head = Enum.join(head)

      with spelled when spelled != nil <- syllable(head),
           parsed when parsed != nil <- parse(rest) do
        [head | parsed]
      else
        _ -> nil
      end
    end)
  end

  defp syllable(syl) do
    case Map.fetch(@whole, syl) do
      {:ok, spelled} -> spelled
      :error -> initial_final(syl)
    end
  end

  defp initial_final(syl) do
    case Enum.find(@initials_longest_first, &String.starts_with?(syl, &1)) do
      nil ->
        nil

      ini ->
        fin = String.replace_prefix(syl, ini, "")

        cond do
          fin == "i" and Map.has_key?(@apical, ini) ->
            @initials[ini] <> @apical[ini]

          ini in ["j", "q", "x"] and Map.has_key?(@jqx_finals, fin) ->
            @initials[ini] <> @jqx_finals[fin]

          Map.has_key?(@finals, fin) ->
            @initials[ini] <> @finals[fin]

          true ->
            nil
        end
    end
  end

  defp capitalize(word) do
    {first, rest} = String.split_at(word, 1)
    String.upcase(first) <> rest
  end

  defp upper?(nil), do: false
  defp upper?(char), do: char != String.downcase(char)
end
