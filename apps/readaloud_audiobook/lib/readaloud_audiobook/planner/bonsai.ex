defmodule ReadaloudAudiobook.Planner.Bonsai do
  @moduledoc """
  The planner's language model: Ternary-Bonsai, served by llama.cpp on the GPU host
  (`BONSAI_URL`, OpenAI-compatible) and shared with the gameassets tagger. Replies
  are constrained to a JSON schema.

  Callers pass a `chat` function, `(system, user, schema) -> {:ok, map} | {:error, _}`,
  so tests stand in a fake model; `chat/1` makes the real one.
  """

  require Logger

  # Lines labelled per request, and neighbours shown on each side so the model can
  # tell who is speaking across a window boundary.
  @window 40
  @context 5

  @kinds ["narration", "dialogue"]
  @sexes ["male", "female", "unknown"]
  @moods ["calm", "casual", "intense", "action"]
  @fallback_tag %{kind: "narration", speaker: "narrator", sex: "unknown", mood: "calm"}

  @tag_system """
  You label lines of a novel for an audiobook narrator.
  <%= context %>

  For every numbered line marked TAG, return one entry with:
  - i: the line number
  - kind: "dialogue" if the line is a character speaking aloud (a quotation), otherwise "narration"
  - speaker: for dialogue, the character's name (or a short description like "the mother" if unnamed); for narration, "narrator"
  - sex: the speaker's sex for dialogue ("male" / "female", "unknown" only if truly impossible to tell); for narration, "unknown"
  - mood: the delivery the line calls for: "calm", "casual", "intense" (angry, afraid, shouting, desperate), or "action" (fast physical action or combat)

  Use the surrounding lines to work out who is speaking: attributions like "she said" may come before or after the quote, and speakers usually alternate in a conversation. Lines marked CONTEXT are only there to help; do not return entries for them.
  """

  @assign_system """
  You choose which recorded narrator voice should read each line of a novel aloud.
  <%= context %>

  Available voices:
  <%= menu %>

  For every numbered line marked TAG return the id of the voice that best fits how that line should be performed: match the speaker (sex, age, temperament) for dialogue, and the scene's tension for narration. Lines marked CONTEXT are only there to help you work out who is speaking.
  """

  @names_system """
  You prepare a pronunciation list for a narrator reading a Chinese web novel in English translation.
  List every Chinese name written in pinyin in the text: people, nicknames, clans, tribes and places, exactly as written (e.g. "Hei Lou Lan", "Fang Yuan", "Huang Er"). Skip anything translated into English, such as "Blazing Heaven Demoness", "Verdant Great Sun" or "Spirit Affinity House". List each name once.
  """

  # The cap ends a reply that starts repeating itself before it runs into max_tokens.
  @names_schema %{
    type: "object",
    properties: %{names: %{type: "array", items: %{type: "string"}, maxItems: 60}},
    required: ["names"]
  }

  @doc "A chat function against the server at `base_url`."
  def chat(base_url) do
    fn system, user, schema -> chat_json(base_url, system, user, schema) end
  end

  @doc false
  def chat_json(base_url, system, user, schema, max_tokens \\ 4096) do
    body = %{
      messages: [%{role: "system", content: system}, %{role: "user", content: user}],
      temperature: 0.3,
      max_tokens: max_tokens,
      chat_template_kwargs: %{enable_thinking: false},
      response_format: %{type: "json_schema", json_schema: %{name: "reply", schema: schema}}
    }

    case Req.post("#{base_url}/v1/chat/completions",
           json: body,
           receive_timeout: 900_000,
           retry: false
         ) do
      {:ok, %{status: 200, body: %{"choices" => [%{"finish_reason" => "length"} | _]}}} ->
        {:error, :truncated}

      {:ok, %{status: 200, body: %{"choices" => [%{"message" => %{"content" => content}} | _]}}} ->
        Jason.decode(content)

      {:ok, %{status: status}} ->
        {:error, {:http, status}}

      {:error, reason} ->
        {:error, {:transport, reason}}
    end
  end

  # The server being down or erroring is not a bad reply: it fails the chapter
  # rather than turning lines into fallbacks.
  defp unreachable?({:error, {kind, _}}) when kind in [:transport, :http], do: true
  defp unreachable?(_), do: false

  @doc """
  Kind, speaker, sex and mood for each text; texts left unlabelled get narration.
  An error when the model gave no usable reply at all.
  """
  def tag(chat, texts, context) do
    schema = %{
      type: "object",
      properties: %{
        tags: %{
          type: "array",
          items: %{
            type: "object",
            properties: %{
              i: %{type: "integer"},
              kind: %{enum: @kinds},
              speaker: %{type: "string"},
              sex: %{enum: @sexes},
              mood: %{enum: @moods}
            },
            required: ["i", "kind", "speaker", "sex", "mood"]
          }
        }
      },
      required: ["tags"]
    }

    parse = fn e -> %{kind: e["kind"], speaker: e["speaker"], sex: e["sex"], mood: e["mood"]} end

    label(
      chat,
      texts,
      String.replace(@tag_system, "<%= context %>", context),
      schema,
      parse,
      @fallback_tag
    )
  end

  @doc "The id of the voice from `menu` (id => description) for each text, or nil; an error as for `tag/3`."
  def assign(chat, texts, menu, context) do
    ids = menu |> Map.keys() |> Enum.sort()

    schema = %{
      type: "object",
      properties: %{
        picks: %{
          type: "array",
          items: %{
            type: "object",
            properties: %{i: %{type: "integer"}, cluster: %{enum: ids}},
            required: ["i", "cluster"]
          }
        }
      },
      required: ["picks"]
    }

    lines = Enum.map_join(ids, "\n", &"- #{&1}: #{menu[&1]}")

    system =
      @assign_system
      |> String.replace("<%= context %>", context)
      |> String.replace("<%= menu %>", lines)

    label(chat, texts, system, schema, & &1["cluster"], nil)
  end

  @doc """
  Pinyin names in `text`. A bad reply is retried once; a second one gives no names
  rather than failing the chapter, which then uses the names already learned. An
  unreachable server is an error.
  """
  def names(chat, text) do
    Enum.reduce_while(1..2, {:ok, []}, fn _attempt, acc ->
      case chat.(@names_system, text, @names_schema) do
        {:ok, %{"names" => names}} when is_list(names) ->
          {:halt, {:ok, Enum.map(names, &to_string/1)}}

        reply ->
          if unreachable?(reply), do: {:halt, reply}, else: {:cont, acc}
      end
    end)
  end

  @doc """
  Labels every text in windows of #{@window}, retrying a window once when the reply
  misses or repeats line numbers; lines still missing get `fallback`. An error if no
  window got a usable reply.
  """
  def label(chat, texts, system, schema, parse, fallback) do
    texts = List.to_tuple(texts)
    n = tuple_size(texts)
    key = schema.properties |> Map.keys() |> hd() |> to_string()

    windows =
      0
      |> Stream.iterate(&(&1 + @window))
      |> Enum.take_while(&(&1 < n))
      |> Enum.reduce_while([], fn start, acc ->
        stop = min(start + @window, n)

        case window(chat, texts, start, stop, system, schema, key, parse) do
          {:error, _} = error -> {:halt, error}
          got -> {:cont, [{start, stop, got} | acc]}
        end
      end)

    cond do
      match?({:error, _}, windows) ->
        windows

      # Not one usable reply means the model is broken, not that every line is narration.
      n > 0 and Enum.all?(windows, fn {_, _, got} -> got == %{} end) ->
        {:error, :no_usable_reply}

      true ->
        windows = Enum.reverse(windows)

        {:ok,
         Enum.flat_map(windows, fn {start, stop, got} ->
           Enum.map(start..(stop - 1)//1, &Map.get(got, &1, fallback))
         end)}
    end
  end

  defp window(chat, texts, start, stop, system, schema, key, parse) do
    n = tuple_size(texts)

    lines =
      Enum.map(max(0, start - @context)..(start - 1)//1, &"[#{&1}] CONTEXT: #{elem(texts, &1)}") ++
        Enum.map(start..(stop - 1)//1, &"[#{&1}] TAG: #{elem(texts, &1)}") ++
        Enum.map(stop..(min(n, stop + @context) - 1)//1, &"[#{&1}] CONTEXT: #{elem(texts, &1)}")

    want = MapSet.new(start..(stop - 1)//1)

    Enum.reduce_while(1..2, %{}, fn _attempt, best ->
      case chat.(system, Enum.join(lines, "\n"), schema) do
        {:ok, %{^key => entries}} when is_list(entries) ->
          seen = Enum.map(entries, & &1["i"])
          got = for e <- entries, e["i"] in want, into: %{}, do: {e["i"], parse.(e)}

          cond do
            Enum.sort(seen) == Enum.to_list(start..(stop - 1)//1) -> {:halt, got}
            map_size(got) > map_size(best) -> {:cont, got}
            true -> {:cont, best}
          end

        other ->
          if unreachable?(other) do
            {:halt, other}
          else
            Logger.warning(
              "Bonsai window #{start}-#{stop - 1}: unusable reply #{inspect(other) |> String.slice(0, 200)}"
            )

            {:cont, best}
          end
      end
    end)
  end
end
