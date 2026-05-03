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
  """

  alias ReadaloudLibrary.Repo
  alias ReadaloudLibrary.Tasks.Status

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
  Broadcast a `{:task_updated, task}` event on the task type's PubSub topics.

  Audiobook tasks fan out to both a global topic and a book-scoped topic so
  ReaderLive can subscribe to its single book without a global subscription.
  Import tasks broadcast on a single global topic.
  """
  def broadcast(task) do
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
