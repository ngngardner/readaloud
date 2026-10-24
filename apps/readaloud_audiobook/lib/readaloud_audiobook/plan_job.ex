defmodule ReadaloudAudiobook.PlanJob do
  @moduledoc """
  Plans a chapter's voice (`ReadaloudAudiobook.Planner`) ahead of its generation
  job, on its own queue: planning waits on the language model, so doing it here
  keeps the TTS queue reading while the next chapters are planned. A generation job
  that gets there first plans the chapter itself.
  """

  use Oban.Worker,
    queue: :plan,
    max_attempts: 2,
    unique: [
      keys: [:chapter_id, :model, :voice],
      states: [:available, :scheduled, :executing, :retryable]
    ]

  alias ReadaloudAudiobook.{Planner, VoicePlan}
  alias ReadaloudTTS.Voice

  require Logger

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(30)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"chapter_id" => chapter_id, "model" => model, "voice" => voice}}) do
    chapter = ReadaloudLibrary.get_chapter!(chapter_id)
    voice = %Voice{model: model, voice: voice}

    case chapter |> VoicePlan.load() |> VoicePlan.for_voice(voice) do
      {:ok, _plan} ->
        :ok

      _ ->
        case Planner.plan_chapter(
               chapter,
               voice,
               Application.get_env(:readaloud_audiobook, :planner_opts, [])
             ) do
          {:ok, _plan} ->
            :ok

          :none ->
            :ok

          {:error, {:transient, reason}} ->
            Logger.warning(
              "Planning chapter #{chapter.number} waits for the model: #{inspect(reason)}"
            )

            {:snooze, 300}

          # Nothing to plan (an empty chapter); its generation job reports it.
          {:error, _reason} ->
            :ok
        end
    end
  end
end
