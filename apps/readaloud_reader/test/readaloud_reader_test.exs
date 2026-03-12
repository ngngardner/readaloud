defmodule ReadaloudReaderTest do
  use ExUnit.Case
  doctest ReadaloudReader

  test "greets the world" do
    assert ReadaloudReader.hello() == :world
  end
end
