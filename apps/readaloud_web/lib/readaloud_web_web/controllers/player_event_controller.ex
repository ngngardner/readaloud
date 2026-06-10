defmodule ReadaloudWebWeb.PlayerEventController do
  @moduledoc """
  HTTP beacon for client audio-player diagnostic events — the durable
  fallback transport for `ReadaloudWebWeb.PlayerEvents` when the LiveView
  WebSocket is suspended (mobile screen lock, tab freeze, page hide). Same
  rationale as `ReadaloudWebWeb.ProgressController`: `navigator.sendBeacon`
  only speaks HTTP, and it's the only delivery mechanism the browser
  guarantees to attempt after the LV socket is already gone.
  """

  use ReadaloudWebWeb, :controller

  alias ReadaloudWebWeb.PlayerEvents

  def beacon(conn, %{"book_id" => book_id_param} = params) do
    book_id = String.to_integer(book_id_param)
    PlayerEvents.ingest(book_id, List.wrap(params["events"]), "beacon")
    send_resp(conn, 204, "")
  end
end
