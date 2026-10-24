defmodule ReadaloudAudiobook.Planner.BonsaiTest do
  use ExUnit.Case, async: true

  alias ReadaloudAudiobook.Planner.Bonsai

  # A fake model that answers each request with `reply.(lines_marked_tag)`.
  defp model(reply) do
    me = self()

    fn system, user, schema ->
      send(me, {:asked, system, user, schema})

      tagged =
        for line <- String.split(user, "\n"),
            [_, i] <- [Regex.run(~r/^\[(\d+)\] TAG:/, line)],
            do: String.to_integer(i)

      reply.(tagged)
    end
  end

  defp tags_for(ids),
    do:
      {:ok,
       %{
         "tags" =>
           Enum.map(
             ids,
             &%{
               "i" => &1,
               "kind" => "dialogue",
               "speaker" => "Fang Yuan",
               "sex" => "male",
               "mood" => "calm"
             }
           )
       }}

  test "labels in windows of 40 with neighbouring lines as context" do
    texts = Enum.map(0..84, &"line #{&1}")
    {:ok, tags} = Bonsai.tag(model(&tags_for/1), texts, "A novel.")
    assert length(tags) == 85
    assert Enum.all?(tags, &(&1.speaker == "Fang Yuan"))

    assert_received {:asked, system, user1, _}
    assert system =~ "A novel."
    refute user1 =~ "[39] CONTEXT"
    assert user1 =~ "[40] CONTEXT: line 40"
    assert_received {:asked, _, user2, _}
    assert user2 =~ "[35] CONTEXT: line 35"
    assert user2 =~ "[40] TAG: line 40"
  end

  test "a window whose reply misses lines is asked again" do
    {:ok, calls} = Agent.start_link(fn -> 0 end)

    reply = fn ids ->
      n = Agent.get_and_update(calls, &{&1, &1 + 1})
      if n == 0, do: tags_for(Enum.take(ids, 1)), else: tags_for(ids)
    end

    {:ok, tags} = Bonsai.tag(model(reply), ["a", "b", "c"], "ctx")
    assert Enum.all?(tags, &(&1.kind == "dialogue"))
    assert Agent.get(calls, & &1) == 2
  end

  test "lines of a window that never gets a usable reply are read as narration" do
    reply = fn ids -> if 0 in ids, do: {:error, :truncated}, else: tags_for(ids) end
    {:ok, tags} = Bonsai.tag(model(reply), Enum.map(0..44, &"line #{&1}"), "ctx")

    assert Enum.at(tags, 0) == %{
             kind: "narration",
             speaker: "narrator",
             sex: "unknown",
             mood: "calm"
           }

    assert Enum.at(tags, 44).kind == "dialogue"
  end

  # Labelling everything as narration would save a plan with no character voices
  # that is never revisited; failing lets the chapter be planned again later.
  test "no usable reply at all is an error, not a chapter of narration" do
    assert {:error, _} = Bonsai.tag(model(fn _ -> {:error, :econnrefused} end), ["a", "b"], "ctx")
  end

  test "assign offers only the menu's voice ids" do
    reply = fn ids -> {:ok, %{"picks" => Enum.map(ids, &%{"i" => &1, "cluster" => "male-0"})}} end

    assert Bonsai.assign(
             model(reply),
             ["a"],
             %{"male-0" => "male, casual", "female-0" => "female, warm"},
             "ctx"
           ) ==
             {:ok, ["male-0"]}

    assert_received {:asked, system, _, schema}
    assert system =~ "- female-0: female, warm"
    assert schema.properties.picks.items.properties.cluster.enum == ["female-0", "male-0"]
  end

  test "names retries a bad reply once, then gives up quietly" do
    {:ok, calls} = Agent.start_link(fn -> 0 end)

    flaky = fn _, _, _ ->
      if Agent.get_and_update(calls, &{&1, &1 + 1}) == 0,
        do: {:error, :truncated},
        else: {:ok, %{"names" => ["Bo Qing"]}}
    end

    assert Bonsai.names(flaky, "text") == {:ok, ["Bo Qing"]}
    assert Bonsai.names(fn _, _, _ -> {:error, :truncated} end, "text") == {:ok, []}
  end

  # A server that is down or erroring mid-chapter must fail the chapter, not save a
  # plan in which that window's dialogue is read as narration.
  test "a transport or HTTP error in any window fails the labelling" do
    reply = fn ids ->
      if 0 in ids, do: tags_for(ids), else: {:error, {:transport, :econnrefused}}
    end

    assert {:error, {:transport, :econnrefused}} =
             Bonsai.tag(model(reply), Enum.map(0..44, &"l#{&1}"), "ctx")

    http = fn _ids -> {:error, {:http, 503}} end
    assert {:error, {:http, 503}} = Bonsai.tag(model(http), ["a"], "ctx")
  end

  test "names: a transport error fails, a bad reply gives no names" do
    assert {:error, {:transport, :timeout}} =
             Bonsai.names(fn _, _, _ -> {:error, {:transport, :timeout}} end, "t")

    assert Bonsai.names(fn _, _, _ -> {:error, :truncated} end, "t") == {:ok, []}
  end
end
