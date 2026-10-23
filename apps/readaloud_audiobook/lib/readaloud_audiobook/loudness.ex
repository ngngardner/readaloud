defmodule ReadaloudAudiobook.Loudness do
  @moduledoc """
  Evens out loudness between synthesized chunks before they are stitched.

  Each chunk is a separate TTS request, and models that clone a voice pick a
  fresh delivery per request: on Breeze the speech level of neighbouring
  chunks varied by up to 6 dB, which is heard as a volume jump at every join.
  Scaling each chunk so its *speech* sits at the same level removes the jump
  without touching anything else. Pauses are left out of the measurement, so
  a chunk with a long silence is not boosted for it.

  Works on 16-bit mono PCM WAV, the format LocalAI returns.
  """

  # Speech RMS every chunk is brought to, in dBFS. Leaves ~10 dB of headroom
  # for peaks, so the gain rarely has anything to clip.
  @target_dbfs -20.0
  # 20 ms frames at 24 kHz.
  @frame_samples 480
  # Frames more than this far below the loudest frame are pauses.
  @speech_floor_db 35.0
  # Chunks that are nearly all silence are left alone rather than amplified.
  @min_speech_frames 10

  @doc """
  Returns the WAV with its PCM scaled so speech sits at #{@target_dbfs} dBFS.
  Anything that is not a 16-bit PCM WAV is returned unchanged.
  """
  @spec level(binary(), float()) :: binary()
  def level(wav, target_dbfs \\ @target_dbfs) do
    with {:ok, header, pcm} <- split_pcm16(wav),
         {:ok, speech_dbfs} <- speech_level(pcm) do
      gain = :math.pow(10, (target_dbfs - speech_dbfs) / 20)
      header <> scale(pcm, gain)
    else
      :error -> wav
    end
  end

  @doc "Speech level of 16-bit little-endian PCM in dBFS, ignoring pauses."
  @spec speech_level(binary()) :: {:ok, float()} | :error
  def speech_level(pcm) do
    energies = frame_energies(pcm)
    loudest = Enum.max(energies, fn -> 0.0 end)

    if loudest <= 0.0 do
      :error
    else
      floor = loudest * :math.pow(10, -@speech_floor_db / 10)
      speech = Enum.filter(energies, &(&1 >= floor))

      if length(speech) < @min_speech_frames do
        :error
      else
        mean_square = Enum.sum(speech) / length(speech)
        {:ok, 10 * :math.log10(mean_square / (32_768 * 32_768))}
      end
    end
  end

  # Mean squared sample value of each whole frame.
  defp frame_energies(pcm) do
    frame_bytes = @frame_samples * 2
    for <<frame::binary-size(frame_bytes) <- pcm>>, do: mean_square(frame)
  end

  defp mean_square(frame) do
    sum = for <<s::little-signed-16 <- frame>>, reduce: 0, do: (acc -> acc + s * s)
    sum / @frame_samples
  end

  defp scale(pcm, gain) do
    for <<s::little-signed-16 <- pcm>>, into: <<>> do
      <<(s * gain) |> round() |> max(-32_768) |> min(32_767)::little-signed-16>>
    end
  end

  # Splits a WAV into everything up to and including the data chunk header,
  # and the PCM after it. Only 16-bit PCM is handled.
  defp split_pcm16(<<"RIFF", _::little-32, "WAVE", rest::binary>> = wav) do
    find_data(wav, rest, 12, nil)
  end

  defp split_pcm16(_), do: :error

  defp find_data(
         wav,
         <<"fmt ", size::little-32, fmt::binary-size(size), rest::binary>>,
         offset,
         _
       ) do
    <<format::little-16, _channels::little-16, _rate::little-32, _byte_rate::little-32,
      _align::little-16, bits::little-16, _::binary>> = fmt

    find_data(wav, rest, offset + 8 + size, format == 1 and bits == 16)
  end

  defp find_data(wav, <<"data", _size::little-32, pcm::binary>>, offset, true) do
    {:ok, binary_part(wav, 0, offset + 8), pcm}
  end

  defp find_data(wav, <<_id::binary-size(4), size::little-32, rest::binary>>, offset, pcm16)
       when byte_size(rest) >= size do
    <<_::binary-size(size), rest::binary>> = rest
    find_data(wav, rest, offset + 8 + size, pcm16)
  end

  defp find_data(_wav, _rest, _offset, _pcm16), do: :error
end
