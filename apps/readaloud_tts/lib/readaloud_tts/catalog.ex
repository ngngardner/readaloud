defmodule ReadaloudTTS.Catalog do
  defmodule Entry do
    @enforce_keys [:model, :voices]
    defstruct [:model, :voices]

    @type t :: %__MODULE__{
            model: String.t(),
            voices: [String.t()]
          }
  end
end
