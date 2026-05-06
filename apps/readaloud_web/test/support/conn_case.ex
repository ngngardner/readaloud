defmodule ReadaloudWebWeb.ConnCase do
  @moduledoc """
  Test case for tests that need a `Plug.Conn` and may touch the database.

  Each test gets a fresh sandboxed `ReadaloudLibrary.Repo` connection that
  rolls back at the end. Tag a test `async: true` if it doesn't need
  cross-process database visibility (most LiveView tests do — they share
  the connection between the test process and the LV process via
  `Sandbox.allow/3`).
  """

  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox

  using do
    quote do
      # The default endpoint for testing
      @endpoint ReadaloudWebWeb.Endpoint

      use ReadaloudWebWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import ReadaloudWebWeb.ConnCase
    end
  end

  setup tags do
    pid = Sandbox.start_owner!(ReadaloudLibrary.Repo, shared: not tags[:async])
    on_exit(fn -> Sandbox.stop_owner(pid) end)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
