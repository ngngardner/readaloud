defmodule ReadaloudLibrary.Tasks.Query do
  @moduledoc """
  Composable Ecto query helpers for any schema with a `:status` field of type
  `ReadaloudLibrary.Tasks.Status`. Importing this module lets context queries
  speak in lifecycle terms instead of string literals.
  """

  import Ecto.Query

  alias ReadaloudLibrary.Repo
  alias ReadaloudLibrary.Tasks.Status

  def active(query), do: where(query, [t], t.status in ^Status.active())
  def terminal(query), do: where(query, [t], t.status in ^Status.terminal())
  def pending(query), do: where(query, [t], t.status == :pending)
  def processing(query), do: where(query, [t], t.status == :processing)
  def failed(query), do: where(query, [t], t.status == :failed)

  @doc "Active or failed — used by retry-aware listings."
  def in_progress_or_failed(query) do
    where(query, [t], t.status in ^(Status.active() ++ [:failed]))
  end

  @doc "Count of active tasks for the given schema. Pass the schema module."
  def active_count(schema) do
    schema |> active() |> Repo.aggregate(:count, :id)
  end
end
