defmodule ReadaloudWebWeb.PageController do
  use ReadaloudWebWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
