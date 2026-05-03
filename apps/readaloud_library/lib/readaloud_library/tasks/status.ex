defmodule ReadaloudLibrary.Tasks.Status do
  @moduledoc """
  The lifecycle of a background task. Single source of truth for the FSM that
  both `ReadaloudAudiobook.AudiobookTask` and `ReadaloudImporter.ImportTask`
  share.

      :pending  ──start──▶  :processing  ──complete──▶  :completed
                                  │
                                  └──────fail───────▶   :failed
  """

  @values [:pending, :processing, :completed, :failed]
  @active [:pending, :processing]
  @terminal [:completed, :failed]

  @type t :: :pending | :processing | :completed | :failed

  @doc "All status values, in `Ecto.Enum`-compatible order."
  def values, do: @values

  @doc "Statuses representing in-flight work."
  def active, do: @active

  @doc "Statuses representing finished work (success or failure)."
  def terminal, do: @terminal
end
