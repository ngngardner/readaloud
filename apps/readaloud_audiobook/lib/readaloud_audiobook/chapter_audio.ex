defmodule ReadaloudAudiobook.ChapterAudio do
  use Ecto.Schema
  import Ecto.Changeset

  schema "chapter_audios" do
    field :chapter_id, :integer
    field :audio_path, :string
    field :duration_seconds, :float
    field :word_timings, :string
    timestamps()
  end

  def changeset(audio, attrs) do
    audio
    |> cast(attrs, [:chapter_id, :audio_path, :duration_seconds, :word_timings])
    |> validate_required([:chapter_id, :audio_path])
    |> unique_constraint(:chapter_id)
  end

  def decoded_timings(%__MODULE__{word_timings: nil}), do: []
  def decoded_timings(%__MODULE__{word_timings: json}), do: Jason.decode!(json)
end
