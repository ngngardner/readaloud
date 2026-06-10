defmodule ReadaloudWebWeb.MetricsEndpointTest do
  use ReadaloudWebWeb.ConnCase, async: true

  alias ReadaloudWebWeb.PlayerEvents

  describe "GET /metrics" do
    test "serves a Prometheus scrape from PromEx.Plug", %{conn: conn} do
      # Make sure at least one domain series exists before scraping.
      PlayerEvents.ingest(1, [%{"event" => "audio-play", "at" => "2026-06-10T01:00:00Z"}], "ws")

      conn = get(conn, "/metrics")
      body = response(conn, 200)

      # Prometheus exposition format with the custom domain series. (Stock
      # plugin series appear once their pollers fire — not within a fresh
      # test boot, so don't assert on them here.)
      assert body =~ "# TYPE readaloud_player_event_count counter"
      assert body =~ ~s(readaloud_player_event_count{event="audio-play",transport="ws"})
    end
  end
end
