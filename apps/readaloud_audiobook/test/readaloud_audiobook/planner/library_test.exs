defmodule ReadaloudAudiobook.Planner.LibraryTest do
  use ExUnit.Case, async: true

  alias ReadaloudAudiobook.Planner.Library

  @lib %Library{
    model: "breeze-tts-2",
    voice: "heath-miller",
    temperature: 0.6,
    fallback: %{voice: "/models/voices/heath-miller.wav", text: "The walls were black."},
    voices: %{
      "female-0" => %{
        group: "female",
        size: 48,
        label: "female, warm",
        sex: "female",
        description: "Warm.",
        clip: %{voice: "/models/voices/f0.wav", text: "F0."}
      },
      "female-1" => %{
        group: "female",
        size: 46,
        label: "female, expressive",
        sex: "female",
        description: "Wide.",
        clip: %{voice: "/models/voices/f1.wav", text: "F1."}
      },
      "male-0" => %{
        group: "male",
        size: 235,
        label: "male, casual",
        sex: "male",
        description: "Casual.",
        clip: %{voice: "/models/voices/m0.wav", text: "M0."}
      },
      "male-2" => %{
        group: "male",
        size: 167,
        label: "male, serious",
        sex: "male",
        description: "Serious.",
        clip: %{voice: "/models/voices/m2.wav", text: "M2."}
      },
      "narration-0" => %{
        group: "narration",
        size: 401,
        label: "narration, calm",
        sex: "male",
        description: "Calm.",
        clip: %{voice: "/models/voices/n0.wav", text: "N0."}
      }
    }
  }

  defp dialogue(speaker, sex), do: %{kind: "dialogue", speaker: speaker, sex: sex, mood: "calm"}
  @narration %{kind: "narration", speaker: "narrator", sex: "unknown", mood: "calm"}

  test "the shipped library for the cloned narrator loads" do
    assert {:ok, lib} =
             Library.for_voice(%ReadaloudTTS.Voice{model: "breeze-tts-2", voice: "heath-miller"})

    assert lib.temperature == 0.6
    assert Enum.any?(lib.voices, fn {_, v} -> v.group == "female" end)
    assert Library.for_voice(%ReadaloudTTS.Voice{model: "kokoro", voice: "af_heart"}) == :none
  end

  test "the menu describes each voice for the model" do
    assert Library.menu(@lib)["female-0"] == "female, warm (female): Warm."
  end

  describe "enforce_group/3" do
    test "a woman's line never gets a man's voice, and dialogue never a narration voice" do
      tags = [dialogue("Hei Lou Lan", "female"), dialogue("Fang Yuan", "male"), @narration]
      picks = Library.enforce_group(@lib, tags, ["male-0", "narration-0", "female-0"])
      # Wrong group: the group's largest voice instead.
      assert picks == ["female-0", "male-0", "narration-0"]
    end

    test "speakers of unknown sex all get the default male voice" do
      assert Library.enforce_group(@lib, [dialogue("Self Gu", "unknown")], ["male-2"]) == [
               "male-0"
             ]
    end

    test "a right-group pick stands" do
      assert Library.enforce_group(@lib, [dialogue("Mother", "female")], ["female-1"]) == [
               "female-1"
             ]
    end
  end

  test "one voice per speaker: the voice picked most often for them" do
    tags = [
      dialogue("Fang Yuan", "male"),
      dialogue("Fang Yuan", "male"),
      dialogue("Fang Yuan", "male"),
      @narration
    ]

    assert Library.one_voice_per_speaker(tags, ["male-0", "male-2", "male-2", "narration-0"]) ==
             ["male-2", "male-2", "male-2", "narration-0"]
  end

  describe "remember_speakers/4" do
    test "characters keep their voice across chapters" do
      tags = [dialogue("Fang Yuan", "male"), dialogue("Bai Ning Bing", "male"), @narration]

      {picks, memory} =
        Library.remember_speakers(@lib, tags, ["male-0", "male-0", "narration-0"], %{
          "Fang Yuan" => "male-2"
        })

      assert picks == ["male-2", "male-0", "narration-0"]
      assert memory == %{"Fang Yuan" => "male-2", "Bai Ning Bing" => "male-0"}
    end

    test "a remembered voice of the wrong group is replaced" do
      {picks, memory} =
        Library.remember_speakers(@lib, [dialogue("Gu", "female")], ["female-0"], %{
          "Gu" => "male-0"
        })

      assert picks == ["female-0"]
      assert memory == %{"Gu" => "female-0"}
    end
  end

  test "clip/2 falls back to the voice's own clip for no pick" do
    assert Library.clip(@lib, "female-0") == %{voice: "/models/voices/f0.wav", text: "F0."}
    assert Library.clip(@lib, nil) == @lib.fallback
  end
end
