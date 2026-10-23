defmodule ReadaloudTTS.Provider do
  alias ReadaloudTTS.{Catalog, Voice, WordTiming}

  @callback synthesize(text :: String.t(), voice :: Voice.t(), opts :: keyword()) ::
              {:ok, binary()} | {:error, term()}

  @callback transcribe(audio :: binary(), opts :: keyword()) ::
              {:ok, [WordTiming.t()]} | {:error, term()}

  @callback catalog(opts :: keyword()) ::
              {:ok, [Catalog.Entry.t()]} | {:error, term()}

  @doc "Longest text, in characters, to send in one synthesis request; nil for no preference."
  @callback max_chunk_chars(voice :: Voice.t()) :: pos_integer() | nil
end
