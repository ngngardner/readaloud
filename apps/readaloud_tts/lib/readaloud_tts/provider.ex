defmodule ReadaloudTTS.Provider do
  alias ReadaloudTTS.{Catalog, Voice, WordTiming}

  @callback synthesize(text :: String.t(), voice :: Voice.t(), opts :: keyword()) ::
              {:ok, binary()} | {:error, term()}

  @callback transcribe(audio :: binary(), opts :: keyword()) ::
              {:ok, [WordTiming.t()]} | {:error, term()}

  @callback catalog(opts :: keyword()) ::
              {:ok, [Catalog.Entry.t()]} | {:error, term()}
end
