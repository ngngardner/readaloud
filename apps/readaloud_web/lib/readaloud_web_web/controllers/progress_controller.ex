defmodule ReadaloudWebWeb.ProgressController do
  @moduledoc """
  HTTP beacon for client-side progress observations.

  This route exists so the JS-side `progressBuffer` can drain its queue via
  `navigator.sendBeacon` when the LiveView WebSocket is unavailable — the
  canonical case being a mobile device locking its screen mid-playback.
  Without this path, observations made after WS suspension are lost and PC
  resume lands several chapters behind where audio actually played.

  The endpoint is intentionally a plain JSON POST, not a LiveView event.
  `sendBeacon` only supports HTTP, and a beacon fired from `pagehide` /
  `visibilitychange:hidden` runs after the LV socket has already been
  torn down by the browser's tab-suspension logic.
  """

  use ReadaloudWebWeb, :controller

  alias ReadaloudReader

  require Logger

  @max_observations_per_request 200

  def beacon(conn, %{"book_id" => book_id_param} = params) do
    book_id = String.to_integer(book_id_param)
    raw = List.wrap(params["observations"])

    if length(raw) > @max_observations_per_request do
      conn |> put_status(:request_entity_too_large) |> json(%{error: "too_many_observations"})
    else
      %{dropped: dropped} = ReadaloudReader.observe_batch!(book_id, raw)

      :telemetry.execute(
        [:readaloud, :progress, :flush],
        %{count: length(raw), dropped: length(dropped)},
        %{transport: "beacon"}
      )

      Enum.each(dropped, fn reason ->
        Logger.warning("[reader] dropping malformed beacon observation: #{inspect(reason)}")
      end)

      send_resp(conn, 204, "")
    end
  end
end
