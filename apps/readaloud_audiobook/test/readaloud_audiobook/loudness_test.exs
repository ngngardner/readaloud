defmodule ReadaloudAudiobook.LoudnessTest do
  use ExUnit.Case, async: true

  alias ReadaloudAudiobook.Loudness

  @rate 24_000

  # A 440 Hz tone at the given peak amplitude, as 16-bit PCM.
  defp tone(seconds, amplitude) do
    n = round(seconds * @rate)

    for i <- 0..(n - 1), into: <<>> do
      <<round(amplitude * :math.sin(2 * :math.pi() * 440 * i / @rate))::little-signed-16>>
    end
  end

  defp silence(seconds), do: :binary.copy(<<0::16>>, round(seconds * @rate))

  defp wav(pcm) do
    size = byte_size(pcm)

    <<"RIFF", 36 + size::little-32, "WAVE", "fmt ", 16::little-32, 1::little-16, 1::little-16,
      @rate::little-32, @rate * 2::little-32, 2::little-16, 16::little-16, "data",
      size::little-32, pcm::binary>>
  end

  defp pcm(<<_header::binary-size(44), pcm::binary>>), do: pcm

  defp level_of(wav) do
    {:ok, db} = wav |> pcm() |> Loudness.speech_level()
    db
  end

  test "chunks recorded at different levels come out at the same level" do
    quiet = Loudness.level(wav(tone(1.0, 1_500)))
    loud = Loudness.level(wav(tone(1.0, 12_000)))

    assert_in_delta level_of(quiet), -20.0, 0.1
    assert_in_delta level_of(loud), -20.0, 0.1
  end

  test "pauses do not count toward the level" do
    plain = Loudness.level(wav(tone(1.0, 3_000)))
    paused = Loudness.level(wav(tone(1.0, 3_000) <> silence(3.0)))

    # Same speech, so the same gain, even with three times as much silence.
    assert binary_part(pcm(plain), 0, 4_800) == binary_part(pcm(paused), 0, 4_800)
  end

  test "keeps the header and length" do
    input = wav(tone(0.5, 2_000))
    output = Loudness.level(input)

    assert byte_size(output) == byte_size(input)
    assert binary_part(output, 0, 44) == binary_part(input, 0, 44)
  end

  test "clamps instead of wrapping when the gain would overflow" do
    # Mostly quiet with one full-scale burst: the burst is louder than the
    # target allows, so it must saturate at the 16-bit limits.
    burst = :binary.copy(<<32_000::little-signed-16, -32_000::little-signed-16>>, 240)
    output = Loudness.level(wav(tone(2.0, 200) <> burst), -6.0)

    samples = for <<s::little-signed-16 <- pcm(output)>>, do: s
    assert Enum.max(samples) <= 32_767
    assert Enum.min(samples) >= -32_768
  end

  test "leaves silence and non-PCM input alone" do
    silent = wav(silence(1.0))
    assert Loudness.level(silent) == silent
    assert Loudness.level("not a wav") == "not a wav"
  end
end
