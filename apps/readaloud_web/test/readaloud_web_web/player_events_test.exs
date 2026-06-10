defmodule ReadaloudWebWeb.PlayerEventsTest do
  # async: false — the log-content tests below temporarily lower the global
  # Logger level to :info (the suite default is :warning).
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias ReadaloudWebWeb.PlayerEvents

  setup do
    ref = :telemetry_test.attach_event_handlers(self(), [[:readaloud, :player, :event]])
    on_exit(fn -> :telemetry.detach(ref) end)
    %{ref: ref}
  end

  defp event(name, extra \\ %{}) do
    Map.merge(
      %{
        "event" => name,
        "at" => "2026-06-10T01:00:00.000Z",
        "chapter_id" => "42",
        "position_ms" => 1234
      },
      extra
    )
  end

  describe "ingest/3 metrics" do
    test "whitelisted event counts under its own name", %{ref: ref} do
      PlayerEvents.ingest(1, [event("audio-play")], "ws")

      assert_received {[:readaloud, :player, :event], ^ref, %{count: 1},
                       %{event: "audio-play", transport: "ws"}}
    end

    test "unknown event name counts as other", %{ref: ref} do
      PlayerEvents.ingest(1, [event("totally-new-event")], "beacon")

      assert_received {[:readaloud, :player, :event], ^ref, %{count: 1},
                       %{event: "other", transport: "beacon"}}
    end

    test "entry without an event string counts as malformed", %{ref: ref} do
      capture_log(fn -> PlayerEvents.ingest(1, [%{"at" => "x"}], "ws") end)

      assert_received {[:readaloud, :player, :event], ^ref, %{count: 1},
                       %{event: "malformed", transport: "ws"}}
    end

    test "batches above the cap are truncated with a warning", %{ref: ref} do
      events = for _ <- 1..101, do: event("heartbeat")

      log = capture_log(fn -> PlayerEvents.ingest(1, events, "beacon") end)

      assert log =~ "dropping 1 events over batch cap"

      for _ <- 1..100 do
        assert_received {[:readaloud, :player, :event], ^ref, %{count: 1}, _}
      end

      refute_received {[:readaloud, :player, :event], ^ref, _, _}
    end

    test "non-list payload is tolerated", %{ref: ref} do
      log = capture_log(fn -> assert :ok = PlayerEvents.ingest(1, "nope", "ws") end)

      assert log =~ "non-list events payload"
      refute_received {[:readaloud, :player, :event], ^ref, _, _}
    end
  end

  describe "ingest/3 log lines" do
    setup do
      previous = Logger.level()
      Logger.configure(level: :info)
      on_exit(fn -> Logger.configure(level: previous) end)
      :ok
    end

    test "writes a structured line with ids, position, and sanitized detail" do
      log =
        capture_log(fn ->
          PlayerEvents.ingest(
            7,
            [event("swap-play-blocked", %{"detail" => %{"error" => "NotAllowedError"}})],
            "beacon"
          )
        end)

      assert log =~ "[player] event=swap-play-blocked book_id=7 chapter_id=42"
      assert log =~ "position_ms=1234"
      assert log =~ "transport=beacon"
      assert log =~ "NotAllowedError"
    end

    test "clamps oversized strings and non-scalar detail values" do
      long = String.duplicate("a", 1000)

      log =
        capture_log(fn ->
          PlayerEvents.ingest(
            7,
            [
              event(long, %{
                "detail" => %{"big" => long, "nested" => %{"drop" => "me"}, "ok" => 1}
              })
            ],
            "ws"
          )
        end)

      # 300-char cap: the raw 1000-char value must not appear.
      refute log =~ long
      assert log =~ String.duplicate("a", 300)
      refute log =~ "drop"
      assert log =~ ~s("ok" => 1)
    end
  end
end
