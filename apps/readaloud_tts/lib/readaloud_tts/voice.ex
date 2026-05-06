defmodule ReadaloudTTS.Voice do
  @enforce_keys [:model, :voice]
  defstruct [:model, :voice, speed: 1.0]

  @type t :: %__MODULE__{
          model: String.t(),
          voice: String.t(),
          speed: float()
        }
end
