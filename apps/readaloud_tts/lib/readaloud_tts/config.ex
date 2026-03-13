defmodule ReadaloudTTS.Config do
  defstruct base_url: "http://localai:8080",
            tts_model: "kokoro",
            voice: "af_heart",
            speed: 1.0,
            stt_model: "whisper-large",
            response_format: "wav"

  @known_voices %{
    "kokoro" => [
      "af_heart",
      "af_nicole",
      "af_sarah",
      "af_sky",
      "am_adam",
      "am_michael",
      "bf_emma",
      "bf_isabella",
      "bm_george",
      "bm_lewis"
    ]
  }

  def known_voices, do: @known_voices

  def from_env do
    %__MODULE__{
      base_url: System.get_env("LOCALAI_URL", "http://localai:8080"),
      tts_model: System.get_env("TTS_MODEL", "kokoro"),
      voice: System.get_env("TTS_VOICE", "af_heart"),
      speed: System.get_env("TTS_SPEED", "1.0") |> String.to_float(),
      stt_model: System.get_env("STT_MODEL", "whisper-large")
    }
  end
end
