defmodule ReadaloudWebWeb.PlayerEventControllerTest do
  use ReadaloudWebWeb.ConnCase, async: true

  setup do
    ref = :telemetry_test.attach_event_handlers(self(), [[:readaloud, :player, :event]])
    on_exit(fn -> :telemetry.detach(ref) end)
    %{ref: ref}
  end

  describe "POST /api/books/:book_id/player-events" do
    test "accepts a batch and counts each event with beacon transport", %{conn: conn, ref: ref} do
      payload = %{
        "events" => [
          %{"event" => "visibility-hidden", "at" => "2026-06-10T01:00:00Z"},
          %{"event" => "audio-stalled", "at" => "2026-06-10T01:00:01Z", "position_ms" => 9000}
        ]
      }

      conn = post(conn, ~p"/api/books/123/player-events", payload)
      assert response(conn, 204)

      assert_received {[:readaloud, :player, :event], ^ref, %{count: 1},
                       %{event: "visibility-hidden", transport: "beacon"}}

      assert_received {[:readaloud, :player, :event], ^ref, %{count: 1},
                       %{event: "audio-stalled", transport: "beacon"}}
    end

    test "responds 204 even with no events key", %{conn: conn, ref: ref} do
      conn = post(conn, ~p"/api/books/123/player-events", %{})
      assert response(conn, 204)
      refute_received {[:readaloud, :player, :event], ^ref, _, _}
    end
  end
end
