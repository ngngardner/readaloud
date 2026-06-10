defmodule ReadaloudWeb.PromEx.Plugins.Readaloud do
  @moduledoc """
  Domain metrics for readaloud. Consumes the `[:readaloud, ...]` telemetry
  events emitted across the umbrella and turns them into Prometheus series.

  Event sources (emitters):

    * `[:readaloud, :player, :event]` — `ReadaloudWebWeb.PlayerEvents.ingest/3`,
      one per client audio-player lifecycle event (play, pause, ended,
      visibility-hidden, swap-play-blocked, ...). Tagged by whitelisted event
      name and delivery transport (`ws` | `beacon`).
    * `[:readaloud, :reader, :chapter_advance]` — `ReadaloudWebWeb.ReaderLive`,
      tagged by direction (`next` | `prev`) and mode (`client_owned` |
      `server_patch` | `noop`).
    * `[:readaloud, :progress, :flush]` — progress-observation batches from
      both the LiveView channel and the HTTP beacon, with accepted/dropped
      counts.
    * `[:readaloud, :task, :transition]` — `ReadaloudLibrary.Tasks`, every
      task status transition, tagged by task kind and target status.
    * `[:readaloud, :tts, :chapter, :stop]` / `[:readaloud, :tts, :chunk, :stop]`
      — `ReadaloudAudiobook.GenerateJob` synthesis spans, tagged by outcome.
    * `[:readaloud, :tts, :transcription_failure]` — whisper alignment
      fallbacks (audio kept, timings lost for that chunk).

  Polling groups snapshot task counts by kind/status and library totals every
  `poll_rate` ms (default 10s).

  Label cardinality is deliberately bounded: event names are whitelisted at
  the ingest boundary and ids (book/chapter/task) stay out of labels — they
  live in the structured logs instead (Loki), where high cardinality is fine.
  """

  use PromEx.Plugin

  import Ecto.Query, only: [from: 2]

  @task_statuses [:pending, :processing, :completed, :failed]

  @impl true
  def event_metrics(_opts) do
    [
      Event.build(:readaloud_player_event_metrics, [
        counter("readaloud.player.event.count",
          event_name: [:readaloud, :player, :event],
          description:
            "Client audio-player lifecycle events, by whitelisted event name and transport.",
          tags: [:event, :transport]
        )
      ]),
      Event.build(:readaloud_reader_event_metrics, [
        counter("readaloud.reader.chapter_advance.count",
          event_name: [:readaloud, :reader, :chapter_advance],
          description: "Chapter advances in the reader, by direction and ownership mode.",
          tags: [:direction, :mode]
        )
      ]),
      Event.build(:readaloud_progress_event_metrics, [
        sum("readaloud.progress.flush.count",
          event_name: [:readaloud, :progress, :flush],
          measurement: :count,
          description: "Progress observations received, by transport.",
          tags: [:transport]
        ),
        sum("readaloud.progress.flush.dropped",
          event_name: [:readaloud, :progress, :flush],
          measurement: :dropped,
          description: "Malformed progress observations dropped, by transport.",
          tags: [:transport]
        )
      ]),
      Event.build(:readaloud_task_event_metrics, [
        counter("readaloud.task.transition.count",
          event_name: [:readaloud, :task, :transition],
          description: "Task status transitions, by task kind and target status.",
          tags: [:kind, :to]
        )
      ]),
      Event.build(:readaloud_tts_event_metrics, [
        distribution("readaloud.tts.chapter.stop.duration",
          event_name: [:readaloud, :tts, :chapter, :stop],
          measurement: :duration,
          unit: {:native, :second},
          description: "Full-chapter TTS synthesis duration, by outcome.",
          tags: [:status],
          reporter_options: [buckets: [5, 15, 30, 60, 120, 300, 600, 1200, 3600]]
        ),
        distribution("readaloud.tts.chunk.stop.duration",
          event_name: [:readaloud, :tts, :chunk, :stop],
          measurement: :duration,
          unit: {:native, :second},
          description: "Per-chunk TTS synthesis duration, by outcome.",
          tags: [:status],
          reporter_options: [buckets: [0.5, 1, 2.5, 5, 10, 30, 60, 120]]
        ),
        counter("readaloud.tts.transcription_failure.count",
          event_name: [:readaloud, :tts, :transcription_failure],
          description: "Chunks whose whisper transcription failed (timings dropped)."
        )
      ])
    ]
  end

  @impl true
  def polling_metrics(opts) do
    poll_rate = Keyword.get(opts, :poll_rate, 10_000)

    [
      Polling.build(
        :readaloud_snapshot_polling_metrics,
        poll_rate,
        {__MODULE__, :execute_snapshot_metrics, []},
        [
          last_value("readaloud.tasks.snapshot.count",
            event_name: [:readaloud, :tasks, :snapshot],
            measurement: :count,
            description: "Tasks currently in the dashboard, by kind and status.",
            tags: [:kind, :status]
          ),
          last_value("readaloud.library.snapshot.books",
            event_name: [:readaloud, :library, :snapshot],
            measurement: :books,
            description: "Books in the library."
          ),
          last_value("readaloud.library.snapshot.chapters",
            event_name: [:readaloud, :library, :snapshot],
            measurement: :chapters,
            description: "Chapters in the library."
          ),
          last_value("readaloud.library.snapshot.chapters_with_audio",
            event_name: [:readaloud, :library, :snapshot],
            measurement: :chapters_with_audio,
            description: "Chapters with generated audio."
          )
        ]
      )
    ]
  end

  @doc """
  Poller callback: snapshot task counts (by kind/status) and library totals.

  Runs in the PromEx poller process. The Repo can be legitimately unavailable
  (test sandbox, app shutdown) — a failed snapshot must never crash the
  poller, so any error just skips this tick.
  """
  def execute_snapshot_metrics do
    for schema <- ReadaloudLibrary.Tasks.schemas() do
      counts =
        from(t in schema, group_by: t.status, select: {t.status, count(t.id)})
        |> ReadaloudLibrary.Repo.all()
        |> Map.new()

      for status <- @task_statuses do
        :telemetry.execute(
          [:readaloud, :tasks, :snapshot],
          %{count: Map.get(counts, status, 0)},
          %{kind: task_kind(schema), status: Atom.to_string(status)}
        )
      end
    end

    :telemetry.execute(
      [:readaloud, :library, :snapshot],
      %{
        books: ReadaloudLibrary.Repo.aggregate(ReadaloudLibrary.Book, :count),
        chapters: ReadaloudLibrary.Repo.aggregate(ReadaloudLibrary.Chapter, :count),
        chapters_with_audio:
          ReadaloudLibrary.Repo.aggregate(ReadaloudAudiobook.ChapterAudio, :count)
      },
      %{}
    )

    :ok
  rescue
    _ -> :ok
  end

  defp task_kind(ReadaloudAudiobook.AudiobookTask), do: "audiobook"
  defp task_kind(ReadaloudImporter.ImportTask), do: "import"
end
