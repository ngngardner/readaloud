defmodule ReadaloudReader do
  alias ReadaloudLibrary.Repo
  alias ReadaloudReader.Progress.Observation
  alias ReadaloudReader.ReadingProgress
  import Ecto.Query
  require Logger

  def get_progress(book_id) do
    ReadingProgress |> where(book_id: ^book_id) |> Repo.one()
  end

  def list_progress_for_books(book_ids) when is_list(book_ids) do
    ReadingProgress |> where([p], p.book_id in ^book_ids) |> Repo.all()
  end

  @doc """
  Apply a single position observation. Idempotent under replay: if the
  observation's `observed_at` is not strictly newer than the row's stored
  `last_observed_at` *for the same chapter*, the call is a no-op.

  Cross-chapter observations always apply — chapter authority is the URL
  / push_patch, and we trust whatever chapter the observation names. The
  staleness filter is intra-chapter only, which is what stops a delayed
  5-second tick from rewinding state after the user has already moved on.

  Returns the resulting `ReadingProgress` row (current or unchanged).
  """
  @spec observe!(Observation.t()) :: ReadingProgress.t()
  def observe!(%Observation{} = obs) do
    {:ok, result} =
      Repo.transaction(fn ->
        current = get_progress(obs.book_id)
        write_observation(current, obs)
      end)

    result
  end

  @doc """
  Decode a list of raw string-keyed observation maps for a book, apply
  them in `observed_at` order, and return a summary. Used by both the
  LiveView WS path and the HTTP beacon controller — they share the
  ingest pipeline so live and replay drains can interleave safely.

  Returns `%{applied: n, dropped: [reason]}`. The caller decides what
  to log (the WS path trusts authenticated input and logs nothing; the
  beacon path logs at warning since the input is untrusted).
  """
  @spec observe_batch!(pos_integer(), [map()]) :: %{
          applied: non_neg_integer(),
          dropped: [atom()]
        }
  def observe_batch!(book_id, raw_list) when is_integer(book_id) and is_list(raw_list) do
    now = DateTime.utc_now()

    {oks, errors} =
      raw_list
      |> Enum.map(&Map.put(&1, "book_id", book_id))
      |> Enum.map(&Observation.from_map(&1, now))
      |> Enum.split_with(&match?({:ok, _}, &1))

    oks
    |> Enum.map(fn {:ok, obs} -> obs end)
    |> Enum.sort_by(& &1.observed_at, DateTime)
    |> Enum.each(&observe!/1)

    %{
      applied: length(oks),
      dropped: Enum.map(errors, fn {:error, reason} -> reason end)
    }
  end

  # The no-row case is structurally a write against `%ReadingProgress{}`
  # with `current_chapter_id: nil`, which `merge_attrs/2` already handles
  # as a chapter pivot (nil != obs.chapter_id) — so insert and update share
  # one path. `same_chapter?/2` on a fresh struct is false, so stale-drop
  # never fires for a brand-new row.
  defp write_observation(nil, %Observation{} = obs),
    do: write_observation(%ReadingProgress{book_id: obs.book_id}, obs)

  defp write_observation(%ReadingProgress{} = current, %Observation{} = obs) do
    if same_chapter?(current, obs) and stale?(current, obs) do
      Logger.debug(
        "[reader] dropping stale observation book_id=#{obs.book_id} chapter_id=#{obs.chapter_id} observed_at=#{obs.observed_at} stored=#{current.last_observed_at}"
      )

      current
    else
      current
      |> ReadingProgress.changeset(merge_attrs(current, obs))
      |> Repo.insert_or_update!()
    end
  end

  defp same_chapter?(%ReadingProgress{current_chapter_id: cid}, %Observation{chapter_id: ocid}),
    do: cid == ocid

  defp stale?(%ReadingProgress{last_observed_at: nil}, _obs), do: false

  # `compare != :gt` covers both `:lt` and `:eq`. Equal-timestamp drop is
  # what makes WS+beacon dual-send idempotent: a same-instant replay won't
  # roll forward (nor back), and the latency cost on the live path is the
  # negligible "compared, no-op'd" branch.
  defp stale?(%ReadingProgress{last_observed_at: stored}, %Observation{observed_at: obs}),
    do: DateTime.compare(obs, stored) != :gt

  # `nil` fields on the observation mean "no information about this
  # dimension" — for same-chapter writes they preserve stored state; for
  # cross-chapter writes (a pivot) they reset to the chapter-fresh
  # default. An explicit `0` / `0.0` always wins, which is how the LV
  # chapter-switch path resets the cursor on a known-fresh chapter.
  defp merge_attrs(%ReadingProgress{} = current, %Observation{} = obs) do
    chapter_changed? = current.current_chapter_id != obs.chapter_id

    %{
      book_id: obs.book_id,
      current_chapter_id: obs.chapter_id,
      audio_position_ms:
        next_value(obs.audio_position_ms, current.audio_position_ms, chapter_changed?, 0),
      scroll_position:
        next_value(obs.scroll_position, current.scroll_position, chapter_changed?, 0.0),
      last_observed_at: obs.observed_at
    }
  end

  defp next_value(nil, _stored, true, fresh_default), do: fresh_default
  defp next_value(nil, stored, false, _fresh_default), do: stored
  defp next_value(value, _stored, _changed, _fresh), do: value

  def chapter_statuses(chapters, nil), do: Map.new(chapters, &{&1.id, :unread})

  def chapter_statuses(chapters, %{current_chapter_id: nil}),
    do: Map.new(chapters, &{&1.id, :unread})

  def chapter_statuses(chapters, %{current_chapter_id: current_id}) do
    current_number =
      case Enum.find(chapters, &(&1.id == current_id)) do
        nil -> nil
        ch -> ch.number
      end

    Map.new(chapters, fn ch ->
      status =
        cond do
          ch.id == current_id -> :current
          current_number && ch.number < current_number -> :read
          true -> :unread
        end

      {ch.id, status}
    end)
  end
end
