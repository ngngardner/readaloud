defmodule ReadaloudTTS.LocalAIProviderTest do
  use ExUnit.Case, async: true

  alias ReadaloudTTS.WordTiming

  # Verbatim from upstream LocalAI (localai/localai:latest-gpu-nvidia-cuda-12),
  # POST /v1/audio/transcriptions with response_format=verbose_json and
  # timestamp_granularities[]=word. Note the word field is "text", not "word" —
  # the old ngngardner/LocalAI fork used "word", and reading the wrong key
  # yields blank words that align against nothing.
  @word_level %{
    "text" => " The quick brown fox.",
    "segments" => [
      %{
        "id" => 0,
        "start" => 0,
        "end" => 4.04,
        "text" => " The quick brown fox.",
        "words" => [
          %{"start" => 0, "end" => 0.34, "text" => " The"},
          %{"start" => 0.34, "end" => 0.48, "text" => " quick"},
          %{"start" => 0.48, "end" => 0.74, "text" => " brown"},
          %{"start" => 0.74, "end" => 1.08, "text" => " fox."}
        ]
      }
    ]
  }

  # Same request without timestamp_granularities: no "words" key at all.
  @segment_only %{
    "text" => " The quick brown fox.",
    "segments" => [
      %{"id" => 0, "start" => 0, "end" => 4.22, "text" => " The quick brown fox."}
    ]
  }

  defp extract(body), do: ReadaloudTTS.LocalAIProvider.extract_word_timings(body)

  describe "word-level timings" do
    test "reads upstream's \"text\" word field with distinct per-word spans" do
      assert [
               %WordTiming{word: "The", start_ms: 0, end_ms: 340},
               %WordTiming{word: "quick", start_ms: 340, end_ms: 480},
               %WordTiming{word: "brown", start_ms: 480, end_ms: 740},
               %WordTiming{word: "fox.", start_ms: 740, end_ms: 1080}
             ] = extract(@word_level)
    end

    test "words are not smeared to a single span" do
      timings = extract(@word_level)
      spans = Enum.map(timings, &{&1.start_ms, &1.end_ms})
      assert length(Enum.uniq(spans)) == length(spans)
    end
  end

  describe "segment-level fallback" do
    test "emits telemetry so a silent downgrade is visible" do
      ref =
        :telemetry_test.attach_event_handlers(self(), [
          [:readaloud, :tts, :segment_level_timings]
        ])

      timings = extract(@segment_only)

      assert_received {[:readaloud, :tts, :segment_level_timings], ^ref, %{count: 1}, _}
      assert Enum.map(timings, & &1.word) == ["The", "quick", "brown", "fox."]
      assert Enum.all?(timings, &(&1.start_ms == 0 and &1.end_ms == 4220))
    end
  end
end
