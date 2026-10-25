defmodule ReadaloudAudiobook.Planner.PassagesTest do
  use ExUnit.Case, async: true

  alias ReadaloudAudiobook.Planner.Passages

  @narr %{kind: "narration", speaker: "narrator", sex: "unknown", mood: "calm"}
  @her %{kind: "dialogue", speaker: "Hei Lou Lan", sex: "female", mood: "intense"}
  @n %{voice: "/models/voices/n0.wav", text: "N0."}
  @f %{voice: "/models/voices/f0.wav", text: "F0."}

  defp unit(para, text), do: %{para: para, text: text, quoted: false}

  describe "build/2" do
    test "one passage per speaker turn; calm narration across paragraphs merges" do
      units = [
        unit(0, "He walked in. "),
        unit(0, "“Leave,”"),
        unit(0, " she said."),
        unit(1, "The hall was cold.")
      ]

      passages = Passages.build(units, [@narr, @her, @narr, @narr])

      assert Enum.map(passages, & &1.text) == [
               "He walked in. ",
               "“Leave,”",
               " she said.\nThe hall was cold."
             ]
    end

    test "narration stops merging at 800 characters" do
      long = String.duplicate("a", 500)
      passages = Passages.build([unit(0, long), unit(1, long)], [@narr, @narr])
      assert length(passages) == 2
    end
  end

  describe "narrate_around_quotes/2" do
    test "the words around a quote are the narrator's, whoever the model says speaks them" do
      units = [
        unit(0, "Fairy Bai Qing smiled bitterly: "),
        %{para: 0, text: "“Why would I have these things?”", quoted: true}
      ]

      tags = Passages.narrate_around_quotes(units, [@her, @her])

      assert tags == [%{@narr | mood: "intense"}, @her]

      assert Enum.map(Passages.build(units, tags), & &1.text) == [
               "Fairy Bai Qing smiled bitterly: ",
               "“Why would I have these things?”"
             ]
    end

    test "a paragraph with no quote keeps its tag (a book quoting with ‘ ’ has none)" do
      units = [unit(0, "‘Leave,’ she said.")]
      assert Passages.narrate_around_quotes(units, [@her]) == [@her]
    end
  end

  describe "chunks/2" do
    test "each chunk has the book's text, the spoken text and its clip" do
      chunks = Passages.chunks([{"Feng Jiu Ge smiled.", @n}], %{"Feng Jiu Ge" => "Fung Jyo Guhh"})

      assert chunks == [
               %{
                 "text" => "Feng Jiu Ge smiled.",
                 "spoken" => "Fung Jyo Guhh smiled.",
                 "voice" => @n.voice,
                 "reference_text" => "N0."
               }
             ]
    end

    test "neighbours with the same clip share a request up to 400 characters" do
      chunks =
        Passages.chunks(
          [
            {"He walked in.", @n},
            {"The hall was cold.", @n},
            {"“Leave.”", @f},
            {"She turned.", @n}
          ],
          %{}
        )

      assert Enum.map(chunks, & &1["text"]) == [
               "He walked in.\nThe hall was cold.",
               "“Leave.”",
               "She turned."
             ]
    end

    test "long passages are cut at 400 characters and nothing is lost" do
      text = String.trim(String.duplicate("Fang Yuan nodded slowly. ", 40))
      chunks = Passages.chunks([{text, @n}], %{})
      assert length(chunks) > 1
      assert Enum.all?(chunks, &(String.length(&1["spoken"]) <= 400))
      assert Enum.map_join(chunks, " ", & &1["text"]) == text
    end

    test "a piece with no words joins its neighbour (Breeze can fail on it)" do
      chunks = Passages.chunks([{"“Leave.”", @f}, {"***", @n}, {"“Now.”", @f}], %{})
      assert Enum.map(chunks, & &1["text"]) == ["“Leave.”\n***", "“Now.”"]

      chunks = Passages.chunks([{"……", @n}, {"“Leave.”", @f}], %{})
      assert Enum.map(chunks, & &1["text"]) == ["……\n“Leave.”"]
    end
  end
end
