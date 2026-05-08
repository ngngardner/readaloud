defmodule ReadaloudLibrary.Tasks do
  @moduledoc """
  Domain verbs for any task with a `:status` field of type
  `ReadaloudLibrary.Tasks.Status`. Workers call `start/1`, `complete/1,2`, and
  `fail/2,3` instead of poking the changeset directly. Predicates replace
  string-equality checks at every read site.

  Terminal transitions (`complete/2`, `fail/2,3`) automatically broadcast
  `{:task_updated, task}` on the appropriate PubSub topics so workers don't
  need to remember to fan out events. `start/1` stays silent — only terminal
  transitions are observable to subscribers.

  The framework also owns the cross-cutting verbs the `/tasks` dashboard
  needs: `subscribe/0`, `get/1`, `cancel/1`, `clear_completed/0`. They span
  every task schema in `schemas/0` so callers never name a specific task
  table.
  """

  import Ecto.Query

  alias ReadaloudLibrary.Repo
  alias ReadaloudLibrary.Tasks.{Query, Status}

  @task_schemas [ReadaloudAudiobook.AudiobookTask, ReadaloudImporter.ImportTask]
  @subscribe_topics ["tasks:audiobook", "tasks:import"]
  @cancel_states ["available", "scheduled", "executing", "retryable"]

  @doc """
  Every task schema the framework knows about. Used by `Dashboard.load/0`,
  `get/1`, `cancel/1`, and `clear_completed/0`. Hard-coded by name to avoid
  a compile-time cycle with the consumer apps that own the structs.
  """
  def schemas, do: @task_schemas

  def pending?(%{status: :pending}), do: true
  def pending?(_), do: false
  def processing?(%{status: :processing}), do: true
  def processing?(_), do: false
  def completed?(%{status: :completed}), do: true
  def completed?(_), do: false
  def failed?(%{status: :failed}), do: true
  def failed?(_), do: false

  def active?(%{status: status}), do: status in Status.active()
  def active?(_), do: false
  def terminal?(%{status: status}), do: status in Status.terminal()
  def terminal?(_), do: false

  @doc "Transition to `:processing`."
  def start(task), do: transition(task, :processing, %{})

  @doc """
  Transition to `:completed`. Optional extra attrs (e.g. `book_id`).
  Broadcasts `{:task_updated, task}` on the task's PubSub topics.
  """
  def complete(task, extra \\ %{}) do
    with {:ok, task} <- transition(task, :completed, extra) do
      broadcast(task)
      {:ok, task}
    end
  end

  @doc """
  Transition to `:failed` with a human-readable reason.
  Broadcasts `{:task_updated, task}` on the task's PubSub topics.
  """
  def fail(task, reason) when is_binary(reason) do
    with {:ok, task} <- transition(task, :failed, %{error_message: reason}) do
      broadcast(task)
      {:ok, task}
    end
  end

  @doc """
  Subscribe the calling process to every task lifecycle topic. Use from
  LiveViews that refresh on any task transition.
  """
  def subscribe do
    for topic <- @subscribe_topics do
      Phoenix.PubSub.subscribe(ReadaloudWeb.PubSub, topic)
    end

    :ok
  end

  @doc """
  Look up a task by id across all known task schemas. Returns the task struct
  or `nil`. Used to resolve a `task-id` from the UI back to a concrete struct
  when the caller doesn't know which kind it is.
  """
  def get(id) when is_integer(id) do
    Enum.find_value(schemas(), fn schema -> Repo.get(schema, id) end)
  end

  @doc """
  Cancel a task: cancel any queued/executing Oban jobs for it, then mark the
  task itself `:failed("Cancelled by user")`. No-op if no task with that id
  exists. Oban-job cancellation is scoped by queue so that an audiobook task
  and an import task with colliding ids do not cancel each other's jobs.
  """
  def cancel(id) when is_integer(id) do
    case get(id) do
      nil ->
        :ok

      task ->
        cancel_oban_jobs_for(task)
        fail(task, "Cancelled by user")
        :ok
    end
  end

  @doc """
  Delete every terminal (completed or failed) task across all known task
  schemas. Drives the `/tasks` page's "Clear Completed" action.
  """
  def clear_completed do
    Enum.each(schemas(), fn schema ->
      schema |> Query.terminal() |> Repo.delete_all()
    end)
  end

  # --- private ---

  defp cancel_oban_jobs_for(task) do
    queue = queue_for(task)

    from(j in Oban.Job,
      where:
        j.queue == ^queue and j.state in ^@cancel_states and
          fragment("?->>'task_id' = ?", j.args, ^to_string(task.id))
    )
    |> Repo.all()
    |> Enum.each(fn job -> Oban.cancel_job(job.id) end)
  end

  # Cross-app dispatch by struct module name; see `topics_for/1`.
  defp queue_for(%{__struct__: ReadaloudAudiobook.AudiobookTask}), do: "tts"
  defp queue_for(%{__struct__: ReadaloudImporter.ImportTask}), do: "import"

  defp broadcast(task) do
    for topic <- topics_for(task) do
      Phoenix.PubSub.broadcast(ReadaloudWeb.PubSub, topic, {:task_updated, task})
    end

    task
  end

  # Cross-app dispatch. `readaloud_library` cannot reference the task structs
  # at compile time — they live in apps that depend on `readaloud_library`,
  # which would create a cyclic dep. Match on the struct module name instead.
  defp topics_for(%{__struct__: ReadaloudAudiobook.AudiobookTask, book_id: book_id}) do
    ["tasks:audiobook", "tasks:audiobook:#{book_id}"]
  end

  defp topics_for(%{__struct__: ReadaloudImporter.ImportTask}) do
    ["tasks:import"]
  end

  defp transition(task, status, extra) do
    schema = task.__struct__
    attrs = Map.put(extra, :status, status)

    task
    |> schema.changeset(attrs)
    |> Repo.update()
  end
end
