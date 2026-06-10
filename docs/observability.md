# Observability

Readaloud exposes Prometheus metrics and structured logs designed around one
debugging scenario in particular: *"my phone was playing in the background,
something went weird, and I want to reconstruct what happened after the
fact."*

## How it plugs into the monitoring stack

- **Metrics**: PromEx serves `GET /metrics` on the Phoenix port (no separate
  metrics port). The Grafana Alloy agent on the host scrapes it and
  remote-writes to the central Prometheus (`pylon:9091`). Grafana reads from
  there.
- **Logs**: plain stdout → journald → the Alloy journal source → Loki
  (`pylon:3100`), labeled `unit="readaloud.service"`. No app-side log
  shipping. The logger formatter includes per-process metadata
  (`request_id`, `book_id`, `chapter_id`, `task_id`) as `key=value` pairs.

### Alloy scrape config (configs repo, pylon host)

The pylon Alloy agent needs a scrape block pointing at the readaloud port
(4000 by default — `services.readaloud.port`):

```alloy
prometheus.scrape "readaloud" {
  targets = [{ "__address__" = "localhost:4000", "job" = "readaloud" }]
  metrics_path = "/metrics"
  forward_to   = [prometheus.remote_write.central.receiver]
}
```

This lives in `nix/services/modules/monitoring-agent.nix` in the configs
repo, not here.

## Metrics inventory

Stock PromEx plugins (see `ReadaloudWeb.PromEx`): `Application`, `Beam`,
`Phoenix` (router/endpoint), `Ecto` (`ReadaloudLibrary.Repo`), `Oban`
(job/queue metrics for the `tts` and `import` queues), `PhoenixLiveView`
(mount / handle_event / exception timings).

Custom domain metrics (`ReadaloudWeb.PromEx.Plugins.Readaloud`):

| Metric | Type | Labels | Source |
|---|---|---|---|
| `readaloud_player_event_count` | counter | `event`, `transport` | client player events via `PlayerEvents.ingest/3` |
| `readaloud_reader_chapter_advance_count` | counter | `direction` (`next`/`prev`), `mode` (`client_owned`/`server_patch`/`noop`) | `ReaderLive` |
| `readaloud_progress_flush_count` / `_dropped` | sum | `transport` (`ws`/`beacon`) | progress observation batches |
| `readaloud_task_transition_count` | counter | `kind` (`audiobook`/`import`), `to` (status) | `ReadaloudLibrary.Tasks` |
| `readaloud_tts_chapter_stop_duration_seconds` | histogram | `status` (`ok`/`error`) | `GenerateJob` whole-chapter span |
| `readaloud_tts_chunk_stop_duration_seconds` | histogram | `status` | per-chunk synthesis span |
| `readaloud_tts_transcription_failure_count` | counter | — | whisper alignment fallbacks |
| `readaloud_tasks_snapshot_count` | gauge | `kind`, `status` | 10s poller |
| `readaloud_library_snapshot_{books,chapters,chapters_with_audio}` | gauge | — | 10s poller |

Label cardinality is bounded on purpose: event names are whitelisted at the
ingest boundary (unknown → `other`), and book/chapter/task ids never become
labels — they live in the logs.

## The player-event channel (mobile background debugging)

The `AudioPlayerHook`'s always-on `[autoplay]` console logging is mirrored
to the server: every `log()` call in `audio_player.ts` is also recorded into
`playerEventBuffer` (localStorage-backed), which delivers via LiveView push
while the WS is alive and via `navigator.sendBeacon` to
`/api/books/:id/player-events` when it isn't. Events recorded while a locked
phone's WS was dead drain on the next visibility transition or LV re-mount.

On top of the existing autoplay events (`mount`, `swap-to-chapter`,
`swap-play-blocked`, `prefetch-*`, `audio-play/pause/ended/error/stalled/
waiting`, …) the hook records the platform transitions that the console
can't show after the fact:

- `visibility-hidden` / `visibility-visible` — screen lock / app switch,
  with an audio-element snapshot (`paused`, `currentTime`, `readyState`,
  `networkState`, `srcKind`)
- `page-hide` / `page-show` (with bfcache `persisted` flag), `page-freeze` /
  `page-resume` (Page Lifecycle API)
- `net-online` / `net-offline`
- `audio-seeked`
- `heartbeat` — every 30s while playing, carrying `wallDeltaMs` vs
  `audioDeltaMs` since the previous beat. On a healthy player they match
  (scaled by `rate`); divergence or a gap in the series is direct evidence
  of throttling/suspension.

Server side, each event becomes a `[player]` log line with the client
wall-clock timestamp (`at=`), so client and server timelines can be merged
even when delivery was delayed by minutes.

Duplicate delivery is possible (the buffer re-beacons rather than risk
losing events) — treat counter *rates* as approximate and dedupe in Loki by
the `at=` timestamp when doing forensics.

## Useful queries

Loki — full timeline for one book (server + client events interleaved):

```logql
{unit="readaloud.service"} |~ "\\[(autoplay|player)\\]" |= "book_id=12"
```

Loki — what did the phone do while backgrounded:

```logql
{unit="readaloud.service"} |= "[player]" |~ "event=(visibility|page|net)-"
```

PromQL — play attempts blocked by the platform (the classic locked-screen
autoplay failure):

```promql
increase(readaloud_player_event_count{event="swap-play-blocked"}[1h])
```

PromQL — beacon-only delivery share (how often the WS was already dead):

```promql
sum(rate(readaloud_player_event_count{transport="beacon"}[1h]))
/ sum(rate(readaloud_player_event_count[1h]))
```

PromQL — TTS p90 chapter synthesis time:

```promql
histogram_quantile(0.9,
  rate(readaloud_tts_chapter_stop_duration_seconds_bucket{status="ok"}[6h]))
```

## Verifying locally

```nu
curl -s http://localhost:4000/metrics | grep readaloud_
journalctl -u readaloud.service -f | grep '\[player\]'
```
