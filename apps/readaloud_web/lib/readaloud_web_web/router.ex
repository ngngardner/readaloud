defmodule ReadaloudWebWeb.Router do
  use ReadaloudWebWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ReadaloudWebWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", ReadaloudWebWeb do
    pipe_through :browser

    live "/", LibraryLive
    live "/books/:id", BookLive
    live "/books/:id/read/:chapter_id", ReaderLive
    live "/books/:id/listen/:chapter_id", PlayerLive
    live "/tasks", TasksLive
  end

  scope "/api", ReadaloudWebWeb do
    pipe_through :api

    get "/books/:book_id/cover", AudioController, :cover
    get "/books/:book_id/chapters/:chapter_id/audio", AudioController, :stream
    get "/books/:book_id/chapters/:chapter_id/timings", AudioController, :timings
  end
end
