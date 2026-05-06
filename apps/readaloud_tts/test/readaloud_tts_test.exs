defmodule ReadaloudTTSTest do
  use ExUnit.Case, async: true
  import Mox

  alias ReadaloudTTS.{Catalog, Voice, WordTiming}

  setup :verify_on_exit!

  describe "synthesize/3" do
    test "dispatches to provider with voice and returns audio binary" do
      voice = %Voice{model: "kokoro", voice: "af_heart"}

      ReadaloudTTS.MockProvider
      |> expect(:synthesize, fn "Hello world", ^voice, _opts ->
        {:ok, <<0, 1, 2, 3>>}
      end)

      assert {:ok, <<0, 1, 2, 3>>} =
               ReadaloudTTS.synthesize("Hello world", voice, provider: ReadaloudTTS.MockProvider)
    end

    test "raises FunctionClauseError when Voice has nil model" do
      voice = %Voice{model: nil, voice: "af_heart"}

      assert_raise FunctionClauseError, fn ->
        ReadaloudTTS.synthesize("hi", voice, provider: ReadaloudTTS.MockProvider)
      end
    end
  end

  describe "transcribe/2" do
    test "dispatches to provider and returns word timings" do
      timings = [
        %WordTiming{word: "Hello", start_ms: 0, end_ms: 500},
        %WordTiming{word: "world", start_ms: 500, end_ms: 1000}
      ]

      ReadaloudTTS.MockProvider
      |> expect(:transcribe, fn _audio, _opts -> {:ok, timings} end)

      assert {:ok, ^timings} =
               ReadaloudTTS.transcribe(<<0, 1, 2>>, provider: ReadaloudTTS.MockProvider)
    end
  end

  describe "catalog/1" do
    test "dispatches to provider and returns catalog entries" do
      entries = [
        %Catalog.Entry{model: "kokoro", voices: ["af_heart", "am_adam"]}
      ]

      ReadaloudTTS.MockProvider
      |> expect(:catalog, fn _opts -> {:ok, entries} end)

      assert {:ok, ^entries} = ReadaloudTTS.catalog(provider: ReadaloudTTS.MockProvider)
    end
  end
end
