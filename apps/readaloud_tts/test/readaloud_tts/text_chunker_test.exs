defmodule ReadaloudTTS.TextChunkerTest do
  use ExUnit.Case, async: true

  alias ReadaloudTTS.TextChunker

  describe "chunk/2 empty-input handling" do
    # Empty/whitespace chapters used to bubble through as `[""]`, get sent to
    # the LocalAI TTS, and trigger an upstream 500 (`torch.cat()` on empty
    # tensor list) that Oban then retried for ~minutes per task.
    test "returns [] for empty string" do
      assert TextChunker.chunk("") == []
    end

    test "returns [] for whitespace-only string" do
      assert TextChunker.chunk("   \n\t  ") == []
    end
  end

  describe "chunk/2 normal input" do
    test "returns single chunk under limit" do
      assert TextChunker.chunk("Hello world.") == ["Hello world."]
    end

    test "trims surrounding whitespace" do
      assert TextChunker.chunk("  Hi.  ") == ["Hi."]
    end

    test "splits long input at sentence boundaries" do
      sentence = String.duplicate("Sentence one. ", 200)
      chunks = TextChunker.chunk(sentence, 100)

      assert length(chunks) > 1
      assert Enum.all?(chunks, &(String.length(&1) <= 100))
    end
  end
end
