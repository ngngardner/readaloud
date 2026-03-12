defmodule ReadaloudTTS.Provider do
  @type timing :: %{word: String.t(), start_ms: non_neg_integer(), end_ms: non_neg_integer()}

  @callback synthesize(text :: String.t(), opts :: keyword()) ::
              {:ok, %{audio: binary()}} | {:error, term()}

  @callback transcribe(audio :: binary(), opts :: keyword()) ::
              {:ok, [timing()]} | {:error, term()}

  @callback list_voices() :: {:ok, [map()]} | {:error, term()}
end
