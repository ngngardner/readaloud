defmodule ReadaloudAudiobook.PlannerTest do
  use ExUnit.Case, async: false

  alias ReadaloudAudiobook.{Planner, VoicePlan}
  alias ReadaloudAudiobook.Planner.{Library, State}
  alias ReadaloudLibrary.Repo

  @html """
  <p>Chapter 959: Duel</p><p>Translator: Atlas Studios</p>
  <p>Feng Jiu Ge smiled. “Leave,” Hei Lou Lan said.</p>
  <p>“Never,” Fang Yuan replied.</p>
  """

  # A fake Bonsai: tags quotes by who is named in them, picks voices by sex, names Feng Jiu Ge.
  def model(texts_seen \\ self()) do
    fn _system, user, schema ->
      send(texts_seen, {:asked, Map.keys(schema.properties)})

      lines =
        for l <- String.split(user, "\n"),
            [_, i, t] <- [Regex.run(~r/^\[(\d+)\] TAG: (.*)$/, l)],
            do: {String.to_integer(i), t}

      case Map.keys(schema.properties) do
        [:tags] ->
          {:ok, %{"tags" => Enum.map(lines, fn {i, t} -> tag(i, t) end)}}

        [:picks] ->
          {:ok,
           %{
             "picks" =>
               Enum.map(lines, fn {i, t} ->
                 %{"i" => i, "cluster" => if(t =~ "Leave", do: "female-0", else: "male-0")}
               end)
           }}

        [:names] ->
          {:ok, %{"names" => ["Feng Jiu Ge", "Hei Lou Lan", "Fang Yuan"]}}
      end
    end
  end

  defp tag(i, "“Leave" <> _),
    do: %{
      "i" => i,
      "kind" => "dialogue",
      "speaker" => "Hei Lou Lan",
      "sex" => "female",
      "mood" => "intense"
    }

  defp tag(i, "“Never" <> _),
    do: %{
      "i" => i,
      "kind" => "dialogue",
      "speaker" => "Fang Yuan",
      "sex" => "male",
      "mood" => "calm"
    }

  defp tag(i, _),
    do: %{
      "i" => i,
      "kind" => "narration",
      "speaker" => "narrator",
      "sex" => "unknown",
      "mood" => "calm"
    }

  setup do
    {:ok, lib} =
      Library.for_voice(%ReadaloudTTS.Voice{model: "breeze-tts-2", voice: "heath-miller"})

    %{lib: lib}
  end

  describe "plain/2" do
    # Used when planning can never succeed for a chapter: it is still recorded as
    # planned, read from the voice's own clip, so it is not queued again and again.
    test "the whole chapter from the voice's own clip, cut at 400 characters", %{lib: lib} do
      doc = Planner.plain(@html, lib)
      assert {:ok, _} = VoicePlan.parse(doc)

      assert Enum.all?(
               doc["chunks"],
               &(&1["voice"] == lib.fallback.voice and &1["text"] == &1["spoken"])
             )

      assert Enum.map_join(doc["chunks"], " ", & &1["text"]) =~ "Feng Jiu Ge smiled."
    end
  end

  describe "plan/4" do
    test "each passage is read from a clip of its own register, names respelled", %{lib: lib} do
      assert {:ok, doc, state} = Planner.plan(@html, lib, State.new("Reverend Insanity"), model())
      assert {:ok, _} = VoicePlan.parse(doc)
      assert doc["model"] == "breeze-tts-2" and doc["temperature"] == 0.6

      leave = Enum.find(doc["chunks"], &(&1["text"] =~ "Leave"))
      never = Enum.find(doc["chunks"], &(&1["text"] =~ "Never"))
      assert leave["voice"] == Library.clip(lib, "female-0").voice
      assert never["voice"] == Library.clip(lib, "male-0").voice

      smiled = Enum.find(doc["chunks"], &(&1["text"] =~ "smiled"))
      assert smiled["text"] =~ "Feng Jiu Ge smiled."
      # A fresh book gets the computed respelling; the ear-tested ones come with its state.
      assert smiled["spoken"] =~ "Fung Jyo Guh smiled."

      refute Enum.any?(doc["chunks"], &(&1["text"] =~ "Translator"))
      assert state.names["Feng Jiu Ge"] == "Fung Jyo Guh"
      assert state.speakers == %{"Hei Lou Lan" => "female-0", "Fang Yuan" => "male-0"}
    end

    test "known names and word fixes win over new ones", %{lib: lib} do
      state = %{
        State.new("RI")
        | names: %{"Feng Jiu Ge" => "Fung Jyo Guhh"},
          words: %{"smiled" => "grinned"}
      }

      {:ok, doc, _} = Planner.plan(@html, lib, state, model())

      assert Enum.find(doc["chunks"], &(&1["text"] =~ "smiled"))["spoken"] =~
               "Fung Jyo Guhh grinned."
    end

    test "an empty chapter has nothing to plan", %{lib: lib} do
      assert {:error, :empty_chapter} = Planner.plan("<p> </p>", lib, State.new("RI"), model())
    end
  end

  describe "plan_chapter/3" do
    setup do
      :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
      base = Path.join(System.tmp_dir!(), "planner_#{System.unique_integer([:positive])}")
      File.mkdir_p!(base)
      on_exit(fn -> File.rm_rf!(base) end)
      html = Path.join(base, "ch.html")
      File.write!(html, @html)

      {:ok, book} =
        ReadaloudLibrary.create_book(%{title: "Reverend Insanity", source_type: "epub"})

      {:ok, chapter} =
        ReadaloudLibrary.create_chapter(%{book_id: book.id, number: 210, content_path: html})

      %{base: base, chapter: chapter}
    end

    @breeze %ReadaloudTTS.Voice{model: "breeze-tts-2", voice: "heath-miller"}

    test "plans, saves the plan and keeps the book's state for the next chapter", %{
      base: base,
      chapter: chapter
    } do
      assert {:ok, %VoicePlan{}} =
               Planner.plan_chapter(chapter, @breeze, chat: model(), base: base)

      assert {:ok, _} = VoicePlan.load(chapter, base)
      assert State.load(chapter.book_id, base).speakers["Hei Lou Lan"] == "female-0"
    end

    test "the book's saved context goes to the model", %{base: base, chapter: chapter} do
      State.save(
        %{State.new("x") | context: "Chinese names; Hei Lou Lan is female."},
        chapter.book_id,
        base
      )

      chat = fn system, user, schema ->
        send(self(), {:system, system})
        model().(system, user, schema)
      end

      {:ok, _} = Planner.plan_chapter(chapter, @breeze, chat: chat, base: base)
      assert_received {:system, system}
      assert system =~ "Hei Lou Lan is female."
    end

    test "voices with no narrator library are not planned", %{base: base, chapter: chapter} do
      assert Planner.plan_chapter(
               chapter,
               %ReadaloudTTS.Voice{model: "kokoro", voice: "af_heart"},
               chat: model(),
               base: base
             ) == :none
    end

    test "a chapter already planned for the voice is not planned again", %{
      base: base,
      chapter: chapter
    } do
      {:ok, plan} = Planner.plan_chapter(chapter, @breeze, chat: model(), base: base)
      never = fn _, _, _ -> flunk("asked the model again") end
      assert {:ok, ^plan} = Planner.plan_chapter(chapter, @breeze, chat: never, base: base)
    end

    # GenerateJob and PlanJob can reach the same chapter together; the second must
    # wait and use the first one's plan, or one overwrites the other's plan and state.
    test "planning one book is serialised: the same chapter is planned once", %{
      base: base,
      chapter: chapter
    } do
      {:ok, asked} = Agent.start_link(fn -> 0 end)

      slow = fn system, user, schema ->
        Agent.update(asked, &(&1 + 1))
        Process.sleep(50)
        model().(system, user, schema)
      end

      results =
        1..2
        |> Enum.map(fn _ ->
          Task.async(fn -> Planner.plan_chapter(chapter, @breeze, chat: slow, base: base) end)
        end)
        |> Enum.map(&Task.await(&1, 10_000))

      assert [{:ok, plan}, {:ok, plan}] = results
      # One planning run: tag, assign and names requests.
      assert Agent.get(asked, & &1) == 3
    end

    test "an unreachable model is a temporary failure and saves nothing", %{
      base: base,
      chapter: chapter
    } do
      down = fn _, _, _ -> {:error, {:transport, :econnrefused}} end

      assert {:error, {:transient, _}} =
               Planner.plan_chapter(chapter, @breeze, chat: down, base: base)

      assert VoicePlan.load(chapter, base) == :none
    end

    test "a corrupt state file starts the book's state afresh instead of failing", %{
      base: base,
      chapter: chapter
    } do
      path = State.path(chapter.book_id, base)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, "{not json")
      assert {:ok, _} = Planner.plan_chapter(chapter, @breeze, chat: model(), base: base)
    end

    test "no model configured means no planning", %{base: base, chapter: chapter} do
      assert Planner.plan_chapter(chapter, @breeze, chat: nil, base: base) == :none
    end
  end
end
