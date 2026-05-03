defmodule ReadaloudLibrary.TtsProfile do
  @moduledoc """
  Typed audio preferences for a `Book`: which TTS model and voice to use.

  Stored as JSON map at the DB boundary (`%{"model" => ..., "voice" => ...}`)
  but exposed in-memory as a struct so call sites can read `profile.model`
  / `profile.voice` instead of poking string keys into a raw map.

  Use `empty?/1` to test whether a profile carries any actual selection — a
  freshly-cast `%{}` produces a struct with both fields `nil`, which is
  semantically "no audio configured yet."
  """

  use Ecto.Type

  defstruct [:model, :voice]

  @type t :: %__MODULE__{model: String.t() | nil, voice: String.t() | nil}

  @doc "Returns true when the profile carries no model and no voice."
  @spec empty?(t() | nil) :: boolean()
  def empty?(nil), do: true
  def empty?(%__MODULE__{model: nil, voice: nil}), do: true
  def empty?(%__MODULE__{}), do: false

  # Ecto.Type callbacks

  @impl true
  def type, do: :map

  @impl true
  def cast(%__MODULE__{} = profile), do: {:ok, profile}

  def cast(map) when is_map(map) do
    {:ok, %__MODULE__{model: get(map, :model), voice: get(map, :voice)}}
  end

  def cast(nil), do: {:ok, nil}
  def cast(_), do: :error

  @impl true
  def load(map) when is_map(map) do
    {:ok, %__MODULE__{model: map["model"], voice: map["voice"]}}
  end

  def load(nil), do: {:ok, nil}
  def load(_), do: :error

  @impl true
  def dump(%__MODULE__{model: model, voice: voice}) do
    {:ok, %{"model" => model, "voice" => voice}}
  end

  def dump(nil), do: {:ok, nil}
  def dump(_), do: :error

  defp get(map, key) when is_atom(key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end
end
