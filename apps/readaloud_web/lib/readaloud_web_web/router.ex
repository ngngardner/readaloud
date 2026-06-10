defmodule ReadaloudWebWeb.Router do
  use ReadaloudWebWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ReadaloudWebWeb.Layouts, :root}
    plug :protect_from_forgery

    # CSP allows our own JS+CSS, inline LV bootstrap, blob:/data: URIs (used
    # by the audio player for prefetched chapters and reader theme swatches),
    # and same-origin media (audio + cover images). 'unsafe-inline' is
    # required for LV's <script> bootstrap and Tailwind-emitted style attrs.
    plug :put_secure_browser_headers, %{
      "content-security-policy" =>
        "default-src 'self'; " <>
          "script-src 'self' 'unsafe-inline'; " <>
          "style-src 'self' 'unsafe-inline'; " <>
          "img-src 'self' data: blob:; " <>
          "media-src 'self' blob:; " <>
          "connect-src 'self' ws: wss:; " <>
          "font-src 'self' data:; " <>
          "frame-ancestors 'none'; " <>
          "base-uri 'self'"
    }
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", ReadaloudWebWeb do
    pipe_through :browser

    live_session :default, layout: {ReadaloudWebWeb.Layouts, :app} do
      live "/", LibraryLive
      live "/books/:id", BookLive
      live "/books/:id/read/:chapter_id", ReaderLive
      live "/tasks", TasksLive
    end

    get "/books/:id/listen/:chapter_id", AudioController, :listen_redirect
  end

  scope "/api", ReadaloudWebWeb do
    pipe_through :api

    get "/books/:book_id/cover", AudioController, :cover
    get "/books/:book_id/chapters/:chapter_id/audio", AudioController, :stream
    get "/books/:book_id/chapters/:chapter_id/timings", AudioController, :timings

    post "/books/:book_id/progress", ProgressController, :beacon
    post "/books/:book_id/player-events", PlayerEventController, :beacon
  end
end
