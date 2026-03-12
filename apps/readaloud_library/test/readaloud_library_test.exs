defmodule ReadaloudLibraryTest do
  use ExUnit.Case
  doctest ReadaloudLibrary

  test "greets the world" do
    assert ReadaloudLibrary.hello() == :world
  end
end
