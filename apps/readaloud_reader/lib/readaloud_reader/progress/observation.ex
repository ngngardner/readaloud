defmodule ReadaloudReader.Progress.Observation do
  @moduledoc """
  A single point-in-time fact about a book's reading position.

  Observations are write-once durable records carried across a transport
  (LiveView WebSocket *or* HTTP beacon). They are idempotent under replay:
  `ReadaloudReader.observe!/1` drops any observation whose `observed_at` is
  not strictly newer than the row's stored `last_observed_at` for the same
  chapter. That's what makes the JS-side progress buffer safe to replay on
  reconnect.

  `audio_position_ms` and `scroll_position` are independently optional —
  `nil` means "no information about this dimension," not zero. To reset a
  dimension explicitly (e.g. a chapter switch resets the audio cursor),
  pass the explicit value (`0` / `0.0`).
  """

  @enforce_keys [:book_id, :chapter_id, :observed_at]
  defstruct [:book_id, :chapter_id, :audio_position_ms, :scroll_position, :observed_at]

  @type t :: %__MODULE__{
          book_id: pos_integer(),
          chapter_id: pos_integer(),
          audio_position_ms: non_neg_integer() | nil,
          scroll_position: float() | nil,
          observed_at: DateTime.t()
        }

  @max_clock_skew_seconds 5 * 60
  @max_observation_age_seconds 7 * 24 * 60 * 60

  @doc """
  Build an observation from an untyped string-keyed map (HTTP beacon body
  or LiveView event payload). Returns `{:ok, t}` or `{:error, reason}`.

  Client-supplied `observed_at` is clamped to `[now - 7d, now + 5min]`. A
  client clock 6 minutes ahead can't pre-empt later real observations; a
  buffered week-old entry can't poison the stream. Outside the window → the
  current server time is substituted, with a log line so we can spot the
  bad clocks.
  """
  @spec from_map(map(), DateTime.t()) :: {:ok, t()} | {:error, atom()}
  def from_map(attrs, now \\ DateTime.utc_now()) when is_map(attrs) do
    with {:ok, book_id} <- fetch_int(attrs, "book_id"),
         {:ok, chapter_id} <- fetch_int(attrs, "chapter_id"),
         {:ok, observed_at} <- parse_observed_at(attrs["observed_at"], now) do
      {:ok,
       %__MODULE__{
         book_id: book_id,
         chapter_id: chapter_id,
         audio_position_ms: optional_int(attrs["audio_position_ms"]),
         scroll_position: optional_float(attrs["scroll_position"]),
         observed_at: observed_at
       }}
    end
  end

  defp fetch_int(attrs, key) do
    case attrs[key] do
      n when is_integer(n) and n > 0 ->
        {:ok, n}

      s when is_binary(s) ->
        case Integer.parse(s) do
          {n, ""} when n > 0 -> {:ok, n}
          _ -> {:error, :"invalid_#{key}"}
        end

      _ ->
        {:error, :"invalid_#{key}"}
    end
  end

  defp optional_int(nil), do: nil
  defp optional_int(n) when is_integer(n) and n >= 0, do: n
  defp optional_int(n) when is_float(n) and n >= 0, do: trunc(n)
  defp optional_int(_), do: nil

  defp optional_float(nil), do: nil
  defp optional_float(n) when is_number(n), do: n / 1
  defp optional_float(_), do: nil

  defp parse_observed_at(nil, now), do: {:ok, DateTime.truncate(now, :second)}

  defp parse_observed_at(iso, now) when is_binary(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, dt, _offset} -> {:ok, clamp(dt, now)}
      _ -> {:ok, DateTime.truncate(now, :second)}
    end
  end

  defp parse_observed_at(_, now), do: {:ok, DateTime.truncate(now, :second)}

  defp clamp(dt, now) do
    diff = DateTime.diff(dt, now, :second)

    cond do
      diff > @max_clock_skew_seconds -> DateTime.truncate(now, :second)
      diff < -@max_observation_age_seconds -> DateTime.truncate(now, :second)
      true -> DateTime.truncate(dt, :second)
    end
  end
end
