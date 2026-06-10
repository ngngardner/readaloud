defmodule ReadaloudWeb.PromEx do
  @moduledoc """
  Prometheus metrics for the whole umbrella, exposed at `GET /metrics` on the
  Phoenix port via `PromEx.Plug` (see `ReadaloudWebWeb.Endpoint`). The Grafana
  Alloy agent on the host scrapes that path and remote-writes to the central
  Prometheus on pylon:9091 — no standalone metrics server, no extra port.

  Stock plugins cover the runtime (BEAM), HTTP (Phoenix router/endpoint),
  LiveView lifecycle, Ecto query timings, and Oban job execution. The custom
  `Readaloud` plugin adds the domain metrics: audio playback client events,
  chapter navigation, progress-observation flushes, TTS synthesis spans, and
  task/library snapshots. See `docs/observability.md` for the full inventory.
  """

  use PromEx, otp_app: :readaloud_web

  alias PromEx.Plugins

  @impl true
  def plugins do
    [
      Plugins.Application,
      Plugins.Beam,
      {Plugins.Phoenix, router: ReadaloudWebWeb.Router, endpoint: ReadaloudWebWeb.Endpoint},
      {Plugins.Ecto, repos: [ReadaloudLibrary.Repo]},
      Plugins.Oban,
      Plugins.PhoenixLiveView,
      ReadaloudWeb.PromEx.Plugins.Readaloud
    ]
  end
end
