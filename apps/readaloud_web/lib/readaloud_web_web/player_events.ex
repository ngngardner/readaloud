defmodule ReadaloudWebWeb.PlayerEvents do
  @moduledoc """
  Ingest boundary for client-side audio-player diagnostic events.

  The JS `playerEventBuffer` mirrors every `[autoplay]` console log line —
  plus visibility/page-lifecycle/network transitions and playback heartbeats
  — to the server, over the LiveView socket while it's alive and via
  `navigator.sendBeacon` when it isn't (mobile screen lock). Both transports
  land here. Each event becomes:

    * one structured `[player]` log line (info level) carrying the client
      wall-clock timestamp, chapter id, audio position, and a sanitized
      detail map — journald ships these to Loki, where they can be lined up
      against the server-side `[autoplay]` traces to reconstruct exactly
      what a sleeping phone did;
    * one bump of the `readaloud_player_event_count` Prometheus counter,
      tagged by event name and transport.

  Counter labels are bounded: only whitelisted event names become label
  values, anything else is counted as `"other"` (and `"malformed"` for
  entries that don't even have an `event` string). The raw name still
  appears in the log line. Duplicate delivery is possible by design (the
  client buffer re-beacons recent events rather than risk losing them), so
  treat counter rates as approximate; logs carry the client timestamp for
  exact forensics.
  """

  require Logger

  @max_events_per_batch 100
  @max_detail_pairs 20
  @max_string_length 300

  # Must cover every event name the audio_player hook can emit (see
  # assets/js/hooks/audio_player.ts). Unknown names are counted as "other".
  @known_events ~w(
    mount destroy set-initial-src preserve-existing-src
    swap-to-chapter swap-play-ok swap-play-blocked
    prefetch-start prefetch-done prefetch-fail prefetch-aborted
    prefetch-abort-stale prefetch-revoke-stale prefetch-discard-target-changed
    prefetch-nav-done prefetch-nav-fail
    go-to-next-chapter go-to-prev-chapter
    next-chapter-blocked-no-target prev-chapter-blocked-no-target
    nav-blocked-self-swap window-adopt autoplay-retry
    history-pushstate push-event
    media-session-nexttrack media-session-previoustrack
    nav-next-chapter-event nav-prev-chapter-event
    audio-play audio-pause audio-ended audio-error
    audio-stalled audio-waiting audio-loadedmetadata audio-seeked
    visibility-hidden visibility-visible page-show page-hide
    page-freeze page-resume net-online net-offline
    lv-reload-deferred lv-reload-resumed
    heartbeat
    sync-audio-to-dataset state-divergence restore-position
    nav-ack-timeout force-reconnect
    lv-disconnected lv-reconnected rejoin-reassert-chapter
  )

  @doc """
  Log + count a batch of raw client events for `book_id`. `transport` is
  `"ws"` (LiveView channel) or `"beacon"` (HTTP fallback). Batches above
  #{@max_events_per_batch} events are truncated with a warning.
  """
  @spec ingest(integer(), [map()] | term(), String.t()) :: :ok
  def ingest(book_id, raw_events, transport) when is_list(raw_events) do
    {events, overflow} = Enum.split(raw_events, @max_events_per_batch)

    if overflow != [] do
      Logger.warning(
        "[player] dropping #{length(overflow)} events over batch cap " <>
          "book_id=#{book_id} transport=#{transport}"
      )
    end

    Enum.each(events, &ingest_one(book_id, &1, transport))
  end

  def ingest(book_id, _raw_events, transport) do
    Logger.warning("[player] non-list events payload book_id=#{book_id} transport=#{transport}")
    :ok
  end

  defp ingest_one(book_id, %{"event" => name} = event, transport) when is_binary(name) do
    emit(metric_label(name), transport)

    Logger.info(fn ->
      detail = event |> Map.get("detail") |> sanitize_detail()

      "[player] event=#{sanitize_string(name)} book_id=#{book_id} " <>
        "chapter_id=#{scalar_field(event, "chapter_id")} " <>
        "position_ms=#{scalar_field(event, "position_ms")} " <>
        "at=#{scalar_field(event, "at")} transport=#{transport} detail=#{inspect(detail)}"
    end)
  end

  defp ingest_one(book_id, _event, transport) do
    emit("malformed", transport)
    Logger.warning("[player] malformed event book_id=#{book_id} transport=#{transport}")
  end

  defp emit(label, transport) do
    :telemetry.execute(
      [:readaloud, :player, :event],
      %{count: 1},
      %{event: label, transport: transport}
    )
  end

  defp metric_label(name) when name in @known_events, do: name
  defp metric_label(_name), do: "other"

  # Client-controlled input goes into log lines — clamp it. Scalars only,
  # strings truncated, pair count capped.
  defp sanitize_detail(detail) when is_map(detail) do
    detail
    |> Enum.filter(fn {k, v} -> is_binary(k) and scalar?(v) end)
    |> Enum.take(@max_detail_pairs)
    |> Map.new(fn {k, v} -> {sanitize_string(k), sanitize_scalar(v)} end)
  end

  defp sanitize_detail(_), do: %{}

  defp scalar_field(event, key) do
    case Map.get(event, key) do
      v when is_binary(v) -> sanitize_string(v)
      v when is_number(v) or is_boolean(v) -> v
      _ -> nil
    end
  end

  defp scalar?(v), do: is_binary(v) or is_number(v) or is_boolean(v) or is_nil(v)

  defp sanitize_scalar(v) when is_binary(v), do: sanitize_string(v)
  defp sanitize_scalar(v), do: v

  defp sanitize_string(s) do
    s
    |> String.slice(0, @max_string_length)
    |> String.replace(~r/[\r\n]/, " ")
  end
end
