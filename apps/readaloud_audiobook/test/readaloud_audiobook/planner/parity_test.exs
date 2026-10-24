defmodule ReadaloudAudiobook.Planner.ParityTest do
  # The planner was first written in Python (tools/voice-refs) and its output was what
  # Noah approved; test/fixtures/planner_parity.json is that code's output on the same
  # inputs (regenerate with tools/voice-refs/explore/parity_fixture.py).
  use ExUnit.Case, async: true

  alias ReadaloudAudiobook.Planner.{Names, Text}

  @fixture "test/fixtures/planner_parity.json" |> File.read!() |> Jason.decode!()

  test "pinyin names are respelled exactly as the Python planner respells them" do
    for {name, expected} <- @fixture["respell"] do
      assert {name, Names.respell(name)} == {name, expected}
    end
  end

  test "names and word fixes are substituted exactly as in Python" do
    for %{"text" => text, "map" => map, "out" => out} <- @fixture["apply_names"] do
      assert Names.apply(text, map) == out
    end
  end

  test "chapter HTML splits into the same paragraphs and quote units" do
    for %{"html" => html, "paragraphs" => paragraphs, "units" => units} <- @fixture["html"] do
      assert Text.paragraphs(html) == paragraphs

      assert paragraphs |> Text.units() |> Enum.map(&Map.take(&1, [:para, :text, :quoted])) ==
               Enum.map(units, fn u ->
                 %{para: u["para"], text: u["text"], quoted: u["quoted"]}
               end)
    end
  end
end
