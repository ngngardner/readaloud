defmodule ReadaloudTTS.Config do
  defstruct base_url: "http://localai:8080",
            tts_model: "kokoro",
            voice: "af_heart",
            speed: 1.0,
            stt_model: "whisper-large-v3",
            response_format: "wav"

  def from_env do
    %__MODULE__{
      base_url: System.get_env("LOCALAI_URL", "http://localai:8080"),
      tts_model: System.get_env("TTS_MODEL", "kokoro"),
      voice: System.get_env("TTS_VOICE", "af_heart"),
      speed: System.get_env("TTS_SPEED", "1.0") |> String.to_float(),
      stt_model: System.get_env("STT_MODEL", "whisper-large-v3")
    }
  end
end
