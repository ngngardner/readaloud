defmodule ReadaloudAudiobook.TimingAlignerTest do
  use ExUnit.Case, async: true

  alias ReadaloudAudiobook.TimingAligner

  describe "align/2 — exact match" do
    test "passes through timings when words match exactly" do
      source = "Hello world"

      timings = [
        %{word: "Hello", start_ms: 0, end_ms: 300},
        %{word: "world", start_ms: 300, end_ms: 600}
      ]

      result = TimingAligner.align(timings, source)

      assert length(result) == 2
      assert Enum.at(result, 0).word == "Hello"
      assert Enum.at(result, 0).start_ms == 0
      assert Enum.at(result, 1).word == "world"
      assert Enum.at(result, 1).start_ms == 300
    end
  end

  describe "align/2 — Whisper splits a word" do
    test "merges split word timings (slidin + G → sliding)" do
      source = "reaching up and sliding her chalk"

      timings = [
        %{word: "reaching", start_ms: 0, end_ms: 400},
        %{word: "up", start_ms: 400, end_ms: 600},
        %{word: "and", start_ms: 600, end_ms: 800},
        %{word: "slidin", start_ms: 800, end_ms: 1100},
        %{word: "G", start_ms: 1100, end_ms: 1200},
        %{word: "her", start_ms: 1200, end_ms: 1400},
        %{word: "chalk", start_ms: 1400, end_ms: 1700}
      ]

      result = TimingAligner.align(timings, source)

      assert length(result) == 6
      words = Enum.map(result, & &1.word)
      assert words == ["reaching", "up", "and", "sliding", "her", "chalk"]

      # "sliding" should span from "slidin" start to "G" end
      sliding = Enum.at(result, 3)
      assert sliding.start_ms == 800
      assert sliding.end_ms == 1200

      # Words after the merge should still be correct
      assert Enum.at(result, 4).word == "her"
      assert Enum.at(result, 4).start_ms == 1200
    end
  end

  describe "align/2 — Whisper merges words" do
    test "handles Whisper merging two source words into one" do
      source = "good bye friend"

      timings = [
        %{word: "goodbye", start_ms: 0, end_ms: 500},
        %{word: "friend", start_ms: 500, end_ms: 800}
      ]

      result = TimingAligner.align(timings, source)

      assert length(result) == 3
      words = Enum.map(result, & &1.word)
      assert words == ["good", "bye", "friend"]

      # "good" and "bye" should split the "goodbye" timing proportionally
      good = Enum.at(result, 0)
      bye = Enum.at(result, 1)
      assert good.start_ms == 0
      assert good.end_ms == bye.start_ms
      assert bye.end_ms <= 500
    end
  end

  describe "align/2 — Whisper skips a word" do
    test "interpolates timing for word Whisper missed" do
      source = "the quick brown fox"

      timings = [
        %{word: "the", start_ms: 0, end_ms: 200},
        %{word: "quick", start_ms: 200, end_ms: 500},
        # "brown" missing
        %{word: "fox", start_ms: 700, end_ms: 1000}
      ]

      result = TimingAligner.align(timings, source)

      assert length(result) == 4
      words = Enum.map(result, & &1.word)
      assert words == ["the", "quick", "brown", "fox"]

      brown = Enum.at(result, 2)
      assert brown.start_ms >= 500
      assert brown.end_ms <= 700
    end
  end

  describe "align/2 — Whisper adds extra words" do
    test "ignores extra Whisper words not in source" do
      source = "hello world"

      timings = [
        %{word: "uh", start_ms: 0, end_ms: 100},
        %{word: "hello", start_ms: 100, end_ms: 400},
        %{word: "world", start_ms: 400, end_ms: 700}
      ]

      result = TimingAligner.align(timings, source)

      assert length(result) == 2
      words = Enum.map(result, & &1.word)
      assert words == ["hello", "world"]
    end
  end

  describe "align/2 — punctuation normalization" do
    test "matches words ignoring punctuation differences" do
      source = "Hello, world! How's it going?"

      timings = [
        %{word: "Hello", start_ms: 0, end_ms: 300},
        %{word: "world", start_ms: 300, end_ms: 600},
        %{word: "How's", start_ms: 600, end_ms: 900},
        %{word: "it", start_ms: 900, end_ms: 1050},
        %{word: "going", start_ms: 1050, end_ms: 1300}
      ]

      result = TimingAligner.align(timings, source)

      assert length(result) == 5
      # Source words preserve original punctuation
      assert Enum.at(result, 0).word == "Hello,"
      assert Enum.at(result, 1).word == "world!"
    end
  end

  describe "align/2 — em/en-dash splitting" do
    test "splits words around em-dashes to match Whisper" do
      source = "ours\u2014a long time"

      timings = [
        %{word: "ours", start_ms: 0, end_ms: 300},
        %{word: "a", start_ms: 300, end_ms: 400},
        %{word: "long", start_ms: 400, end_ms: 600},
        %{word: "time", start_ms: 600, end_ms: 900}
      ]

      result = TimingAligner.align(timings, source)

      assert length(result) == 4
      words = Enum.map(result, & &1.word)
      assert words == ["ours", "a", "long", "time"]
    end
  end

  describe "align/2 — edge cases" do
    test "returns empty list for empty source" do
      assert TimingAligner.align([%{word: "hi", start_ms: 0, end_ms: 100}], "") == []
    end

    test "returns empty list for empty timings" do
      assert TimingAligner.align([], "hello world") == []
    end

    test "handles single word" do
      result = TimingAligner.align([%{word: "hello", start_ms: 0, end_ms: 500}], "hello")
      assert length(result) == 1
      assert hd(result).word == "hello"
    end
  end
end
