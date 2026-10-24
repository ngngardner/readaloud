defmodule ReadaloudAudiobook.Planner.State do
  @moduledoc """
  What the planner carries from chapter to chapter of a book: the names it has
  respelled, word fixes for words the voice misreads ("feathermen" → "feather men"),
  the voice each character was given, and an optional note for the model about the
  book (who is male or female, how names are written).

  Stored as JSON beside the book's plans: `<storage>/books/<id>/voice-plan-state.json`.
  """

  require Logger

  defstruct context: nil, names: %{}, words: %{}, speakers: %{}

  @type t :: %__MODULE__{
          context: String.t() | nil,
          names: %{String.t() => String.t()},
          words: %{String.t() => String.t()},
          speakers: %{String.t() => String.t()}
        }

  @doc "A fresh state whose context names the book."
  def new(title), do: %__MODULE__{context: ~s(The lines are from the novel "#{title}".)}

  def path(book_id, base \\ storage_base()),
    do: Path.join([base, "books", "#{book_id}", "voice-plan-state.json"])

  @doc "The book's state; a book never planned before gets `fallback`."
  def load(book_id, base \\ storage_base(), fallback \\ %__MODULE__{}) do
    with {:ok, json} <- File.read(path(book_id, base)),
         {:ok, map} <- Jason.decode(json) do
      %__MODULE__{
        context: map["context"] || fallback.context,
        names: map["names"] || %{},
        words: map["words"] || %{},
        speakers: map["speakers"] || %{}
      }
    else
      {:error, :enoent} ->
        fallback

      # A damaged file must not stop the book being read: start afresh.
      {:error, reason} ->
        Logger.warning(
          "Voice plan state for book #{book_id} unreadable, starting afresh: #{inspect(reason)}"
        )

        fallback
    end
  end

  def save(%__MODULE__{} = state, book_id, base \\ storage_base()) do
    dest = path(book_id, base)
    File.mkdir_p!(Path.dirname(dest))
    tmp = "#{dest}.#{System.unique_integer([:positive])}.tmp"
    File.write!(tmp, Jason.encode!(Map.from_struct(state), pretty: true))
    File.rename!(tmp, dest)
  end

  defp storage_base, do: System.get_env("STORAGE_PATH", "priv/static/files")
end
