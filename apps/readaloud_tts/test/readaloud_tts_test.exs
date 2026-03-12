defmodule ReadaloudTTSTest do
  use ExUnit.Case, async: true
  import Mox

  setup :verify_on_exit!

  describe "synthesize/2" do
    test "calls provider and returns audio binary" do
      ReadaloudTTS.MockProvider
      |> expect(:synthesize, fn "Hello world", _opts ->
        {:ok, %{audio: <<0, 1, 2, 3>>}}
      end)

      assert {:ok, %{audio: <<0, 1, 2, 3>>}} =
               ReadaloudTTS.synthesize("Hello world", provider: ReadaloudTTS.MockProvider)
    end
  end

  describe "transcribe/2" do
    test "calls provider and returns word timings" do
      timings = [
        %{word: "Hello", start_ms: 0, end_ms: 500},
        %{word: "world", start_ms: 500, end_ms: 1000}
      ]

      ReadaloudTTS.MockProvider
      |> expect(:transcribe, fn _audio, _opts -> {:ok, timings} end)

      assert {:ok, ^timings} =
               ReadaloudTTS.transcribe(<<0, 1, 2>>, provider: ReadaloudTTS.MockProvider)
    end
  end

  describe "list_voices/1" do
    test "calls provider and returns voices" do
      voices = [%{"id" => "af_heart", "name" => "Heart"}]

      ReadaloudTTS.MockProvider
      |> expect(:list_voices, fn -> {:ok, voices} end)

      assert {:ok, ^voices} = ReadaloudTTS.list_voices(provider: ReadaloudTTS.MockProvider)
    end
  end
end
