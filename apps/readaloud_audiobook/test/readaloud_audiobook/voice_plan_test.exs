defmodule ReadaloudAudiobook.VoicePlanTest do
  use ExUnit.Case, async: true

  alias ReadaloudAudiobook.VoicePlan
  alias ReadaloudAudiobook.VoicePlan.Chunk

  @chunk %{
    "text" => "Feng Jiu Ge smiled.",
    "spoken" => "Fung Jyo Guhh smiled.",
    "voice" => "/models/voices/hwfwm-male-0.wav",
    "reference_text" => "Well, that went better than expected."
  }

  @plan %{
    "model" => "breeze-tts-2",
    "voice" => "heath-miller",
    "temperature" => 0.6,
    "chunks" => [@chunk]
  }

  @chapter %{book_id: 12, number: 210}

  setup do
    base = Path.join(System.tmp_dir!(), "voice_plan_#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(base) end)
    %{base: base}
  end

  describe "parse/1" do
    test "reads chunks, the voice it was made for and the temperature" do
      assert {:ok, plan} = VoicePlan.parse(@plan)
      assert plan.model == "breeze-tts-2"
      assert plan.voice == "heath-miller"
      assert plan.temperature == 0.6

      assert [
               %Chunk{
                 text: "Feng Jiu Ge smiled.",
                 spoken: "Fung Jyo Guhh smiled.",
                 reference: %{voice: "/models/voices/hwfwm-male-0.wav", text: "Well" <> _}
               }
             ] = plan.chunks
    end

    test "rejects a plan with no chunks" do
      assert {:error, _} = VoicePlan.parse(%{@plan | "chunks" => []})
    end

    # Breeze can fail on a request with nothing to say, failing the chapter on every retry.
    test "rejects a chunk with no words to speak" do
      assert {:error, _} = VoicePlan.parse(%{@plan | "chunks" => [%{@chunk | "spoken" => "***"}]})

      assert {:error, _} =
               VoicePlan.parse(%{@plan | "chunks" => [%{@chunk | "spoken" => "“……”"}]})
    end

    test "rejects a chunk missing its spoken text" do
      assert {:error, _} = VoicePlan.parse(%{@plan | "chunks" => [Map.delete(@chunk, "spoken")]})
    end

    # The clip path goes straight to LocalAI as `voice`; only its voices
    # directory holds narrator clips.
    test "rejects a reference clip outside LocalAI's voices directory" do
      bad = %{@chunk | "voice" => "/etc/passwd"}
      assert {:error, _} = VoicePlan.parse(%{@plan | "chunks" => [bad]})

      sneaky = %{@chunk | "voice" => "/models/voices/../config.yaml"}
      assert {:error, _} = VoicePlan.parse(%{@plan | "chunks" => [sneaky]})
    end

    test "rejects a temperature Breeze would not take" do
      assert {:error, _} = VoicePlan.parse(%{@plan | "temperature" => 5})
      assert {:error, _} = VoicePlan.parse(%{@plan | "temperature" => "hot"})
    end

    test "temperature is optional" do
      assert {:ok, %VoicePlan{temperature: nil}} =
               VoicePlan.parse(Map.delete(@plan, "temperature"))
    end
  end

  describe "save/3 and load/2" do
    test "a saved plan loads back", %{base: base} do
      ch = @chapter
      assert {:ok, saved} = VoicePlan.save(ch, @plan, base)
      assert {:ok, ^saved} = VoicePlan.load(ch, base)
    end

    test "plans live beside the book's chapters, one file per chapter number", %{base: base} do
      assert VoicePlan.path(@chapter, base) ==
               Path.join([base, "books", "12", "voice-plans", "0210.json"])
    end

    test "a chapter without a plan loads as :none", %{base: base} do
      assert VoicePlan.load(@chapter, base) == :none
    end

    test "an invalid plan is not written", %{base: base} do
      ch = @chapter
      assert {:error, _} = VoicePlan.save(ch, %{@plan | "chunks" => []}, base)
      refute File.exists?(VoicePlan.path(ch, base))
    end
  end

  describe "for_voice/2" do
    test "a plan applies only to the voice it was made for" do
      {:ok, plan} = VoicePlan.parse(@plan)
      breeze = %ReadaloudTTS.Voice{model: "breeze-tts-2", voice: "heath-miller"}
      kokoro = %ReadaloudTTS.Voice{model: "kokoro", voice: "af_heart"}

      assert VoicePlan.for_voice({:ok, plan}, breeze) == {:ok, plan}
      assert VoicePlan.for_voice({:ok, plan}, kokoro) == :none
      assert VoicePlan.for_voice(:none, breeze) == :none
    end
  end
end
