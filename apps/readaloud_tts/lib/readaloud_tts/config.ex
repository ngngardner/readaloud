defmodule ReadaloudTTS.Config do
  @moduledoc false

  defstruct base_url: "http://localai:8080",
            stt_model: "whisper-large"

  @type t :: %__MODULE__{
          base_url: String.t(),
          stt_model: String.t()
        }

  def from_env do
    %__MODULE__{
      base_url: System.get_env("LOCALAI_URL", "http://localai:8080"),
      stt_model: System.get_env("STT_MODEL", "whisper-large")
    }
  end
end
