defmodule ReadaloudAudiobook.Planner.Library do
  @moduledoc """
  A cloned narrator's voices: the registers he reads in (narration, women's and
  men's voices of several temperaments), each with the clip of him it is read from.

  Found by clustering his audiobook in tools/voice-refs and exported to
  `priv/voice_libraries/<model>--<voice>.json` (`voicerefs export-library`). A
  voice with no library is read from its single clip, as before.
  """

  require Logger

  @enforce_keys [:model, :voice, :voices, :fallback]
  defstruct [:model, :voice, :temperature, :fallback, :voices]

  @type clip :: %{voice: String.t(), text: String.t()}
  @type t :: %__MODULE__{
          model: String.t(),
          voice: String.t(),
          temperature: float() | nil,
          fallback: clip(),
          voices: %{String.t() => map()}
        }

  @spec for_voice(ReadaloudTTS.Voice.t()) :: {:ok, t()} | :none
  def for_voice(%ReadaloudTTS.Voice{model: model, voice: voice}) do
    path =
      Path.join([
        :code.priv_dir(:readaloud_audiobook),
        "voice_libraries",
        "#{model}--#{voice}.json"
      ])

    with {:ok, json} <- File.read(path),
         {:ok, map} <- Jason.decode(json) do
      {:ok, from_json(map)}
    else
      {:error, :enoent} ->
        :none

      {:error, reason} ->
        Logger.error(
          "Voice library #{path} unreadable, reading from the voice's own clip: #{inspect(reason)}"
        )

        :none
    end
  end

  defp from_json(map) do
    %__MODULE__{
      model: map["model"],
      voice: map["voice"],
      temperature: map["temperature"],
      fallback: clip_from(map["fallback"]),
      voices:
        Map.new(map["voices"], fn {id, v} ->
          {id,
           %{
             label: v["label"],
             sex: v["sex"],
             description: v["description"],
             group: v["group"],
             size: v["size"],
             clip: clip_from(v["clip"])
           }}
        end)
    }
  end

  defp clip_from(%{"voice" => voice, "text" => text}), do: %{voice: voice, text: text}

  @doc "What the model is told about each voice when choosing one per line."
  def menu(%__MODULE__{voices: voices}) do
    Map.new(voices, fn {id, v} -> {id, "#{v.label} (#{v.sex}): #{v.description}"} end)
  end

  @doc "The clip a passage is read from; no pick reads from the voice's own clip."
  def clip(%__MODULE__{voices: voices, fallback: fallback}, id) do
    case Map.fetch(voices, id || "") do
      {:ok, v} -> v.clip
      :error -> fallback
    end
  end

  @doc """
  A passage's voice must come from its own group: a woman's line never gets a man's
  voice, and dialogue never a narration voice. A wrong pick becomes the group's
  largest voice; speakers of unknown sex (Gu worms) all get the largest male voice.
  """
  def enforce_group(%__MODULE__{voices: voices}, tags, picks) do
    Enum.zip_with(tags, picks, fn tag, pick ->
      want =
        cond do
          tag.kind == "narration" -> "narration"
          tag.sex == "female" -> "female"
          true -> "male"
        end

      unknown_sex? = tag.kind == "dialogue" and tag.sex not in ["female", "male"]

      if pick != nil and get_in(voices, [pick, :group]) == want and not unknown_sex? do
        pick
      else
        voices
        |> Enum.filter(fn {_, v} -> v.group == want end)
        |> Enum.max_by(fn {_, v} -> v.size end, fn -> {nil, nil} end)
        |> elem(0)
      end
    end)
  end

  @doc "Each character keeps the voice picked most often for them in the chapter."
  def one_voice_per_speaker(tags, picks) do
    votes =
      Enum.zip(tags, picks)
      |> Enum.filter(fn {t, p} -> t.kind == "dialogue" and p != nil end)
      |> Enum.group_by(fn {t, _} -> t.speaker end, fn {_, p} -> p end)
      |> Map.new(fn {speaker, ps} ->
        # Ties go to the voice picked first, as Python's Counter.most_common does.
        freq = Enum.frequencies(ps)
        {speaker, Enum.max_by(Enum.uniq(ps), &freq[&1])}
      end)

    Enum.zip_with(tags, picks, fn t, p ->
      if t.kind == "dialogue", do: Map.get(votes, t.speaker, p), else: p
    end)
  end

  @doc """
  Characters keep the voice they were first given, across chapters, while it is of
  the right group. Returns the picks and the updated speaker => voice memory.
  """
  def remember_speakers(%__MODULE__{voices: voices}, tags, picks, memory) do
    Enum.zip(tags, picks)
    |> Enum.map_reduce(memory, fn {tag, pick}, memory ->
      kept = Map.get(memory, tag.speaker)

      cond do
        tag.kind != "dialogue" or pick == nil ->
          {pick, memory}

        kept != nil and get_in(voices, [kept, :group]) == get_in(voices, [pick, :group]) ->
          {kept, memory}

        true ->
          {pick, Map.put(memory, tag.speaker, pick)}
      end
    end)
  end
end
