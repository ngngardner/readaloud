defmodule ReadaloudTTS.WordTiming do
  @derive Jason.Encoder
  @enforce_keys [:word, :start_ms, :end_ms]
  defstruct [:word, :start_ms, :end_ms]

  @type t :: %__MODULE__{
          word: String.t(),
          start_ms: non_neg_integer(),
          end_ms: non_neg_integer()
        }
end
