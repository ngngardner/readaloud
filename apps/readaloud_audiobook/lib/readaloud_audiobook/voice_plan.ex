defmodule ReadaloudAudiobook.VoicePlan do
  @moduledoc """
  How to read one chapter aloud with a cloned narrator: the chapter split into
  chunks, each with the text to speak and its own reference clip of the
  narrator.

  A plan is made outside readaloud by the voice-refs planner
  (`tools/voice-refs`), which tags who is speaking in each passage and picks a
  clip of the narrator in that register — his narrating voice, a woman's
  voice, a man's — and respells names so the voice says them right. Each
  chunk keeps the book's own `text` beside the `spoken` text, so word
  timings still line up with what the reader shows.

  A plan names the model and voice it was made for, and applies only to
  that voice: its clips are references for that clone and mean nothing to
  any other model.

  Plans are stored as JSON beside the book's chapters:
  `<storage>/books/<book_id>/voice-plans/<NNNN>.json`.
  """

  defmodule Chunk do
    @moduledoc false
    @enforce_keys [:text, :spoken, :reference]
    defstruct [:text, :spoken, :reference]

    @type t :: %__MODULE__{
            text: String.t(),
            spoken: String.t(),
            reference: %{voice: String.t(), text: String.t()}
          }
  end

  @enforce_keys [:model, :voice, :chunks]
  defstruct [:model, :voice, :temperature, :chunks]

  @type t :: %__MODULE__{
          model: String.t(),
          voice: String.t(),
          temperature: float() | nil,
          chunks: [Chunk.t()]
        }

  # LocalAI's models dir as the container sees it; clips anywhere else are
  # not narrator references.
  @voices_dir "/models/voices/"

  def path(chapter, base \\ storage_base()) do
    padded = String.pad_leading("#{chapter.number}", 4, "0")
    Path.join([base, "books", "#{chapter.book_id}", "voice-plans", "#{padded}.json"])
  end

  @spec load(map(), String.t()) :: {:ok, t()} | :none | {:error, term()}
  def load(chapter, base \\ storage_base()) do
    case File.read(path(chapter, base)) do
      {:ok, json} ->
        with {:ok, map} <- Jason.decode(json), do: parse(map)

      {:error, :enoent} ->
        :none

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Validates `map` and writes it as the chapter's plan."
  @spec save(map(), map(), String.t()) :: {:ok, t()} | {:error, term()}
  def save(chapter, map, base \\ storage_base()) do
    with {:ok, plan} <- parse(map) do
      dest = path(chapter, base)
      File.mkdir_p!(Path.dirname(dest))
      # Write-then-rename so a generation job never reads half a plan.
      tmp = dest <> ".tmp"
      File.write!(tmp, Jason.encode!(map))
      File.rename!(tmp, dest)
      {:ok, plan}
    end
  end

  @doc "The plan, if it was made for `voice`; otherwise `:none`."
  def for_voice({:ok, %__MODULE__{model: model, voice: id}} = loaded, %ReadaloudTTS.Voice{
        model: model,
        voice: id
      }),
      do: loaded

  def for_voice({:ok, _plan}, _voice), do: :none
  def for_voice(other, _voice), do: other

  @spec parse(map()) :: {:ok, t()} | {:error, String.t()}
  def parse(%{"model" => model, "voice" => voice, "chunks" => [_ | _] = chunks} = map)
      when is_binary(model) and is_binary(voice) do
    with {:ok, temperature} <- temperature(Map.get(map, "temperature")),
         {:ok, chunks} <- chunks(chunks) do
      {:ok, %__MODULE__{model: model, voice: voice, temperature: temperature, chunks: chunks}}
    end
  end

  def parse(_), do: {:error, "a plan needs model, voice and at least one chunk"}

  defp temperature(nil), do: {:ok, nil}
  defp temperature(t) when is_number(t) and t > 0 and t <= 2, do: {:ok, t * 1.0}
  defp temperature(t), do: {:error, "temperature must be a number in (0, 2], got #{inspect(t)}"}

  defp chunks(raw) do
    raw
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {c, i}, {:ok, acc} ->
      case chunk(c) do
        {:ok, chunk} -> {:cont, {:ok, [chunk | acc]}}
        {:error, reason} -> {:halt, {:error, "chunk #{i}: #{reason}"}}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      error -> error
    end
  end

  defp chunk(%{"text" => text, "spoken" => spoken, "voice" => clip, "reference_text" => ref})
       when is_binary(text) and is_binary(spoken) and is_binary(clip) and is_binary(ref) do
    cond do
      String.trim(spoken) == "" ->
        {:error, "empty spoken text"}

      not voice_clip?(clip) ->
        {:error, "reference clip must be a .wav in #{@voices_dir}, got #{inspect(clip)}"}

      true ->
        {:ok, %Chunk{text: text, spoken: spoken, reference: %{voice: clip, text: ref}}}
    end
  end

  defp chunk(_), do: {:error, "needs text, spoken, voice and reference_text strings"}

  defp voice_clip?(clip) do
    name = String.replace_prefix(clip, @voices_dir, "")

    String.starts_with?(clip, @voices_dir) and String.ends_with?(name, ".wav") and
      not String.contains?(name, ["/", ".."])
  end

  defp storage_base, do: System.get_env("STORAGE_PATH", "priv/static/files")
end
