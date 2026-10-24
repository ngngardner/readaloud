defmodule ReadaloudAudiobook.Planner do
  @moduledoc """
  Makes a chapter's voice plan (`ReadaloudAudiobook.VoicePlan`) for a cloned
  narrator with a voice library (`Planner.Library`): the chapter is cut into speaker
  turns, the language model (`Planner.Bonsai`) says who speaks each one and which of
  the narrator's voices fits it, and names are respelled so the voice says them
  right. A woman's line is then read from a clip of him voicing a woman, and so on.

  This is the pipeline Noah approved on the voice-refs comparison page
  (tools/voice-refs, Oct 2026), minus laya: Bonsai's own mood tag covers it.
  """

  alias ReadaloudAudiobook.Planner.{Bonsai, Library, Names, Passages, State, Text}
  alias ReadaloudAudiobook.VoicePlan

  require Logger

  @doc """
  Plans and saves a chapter for `voice`. `:none` when the voice has no library or no
  model is configured (`BONSAI_URL`); the chapter is then read from the voice's own clip.

  Options: `chat` (a `Planner.Bonsai` chat function; nil for none), `base` (storage root).
  """
  @spec plan_chapter(map(), ReadaloudTTS.Voice.t(), keyword()) ::
          {:ok, VoicePlan.t()} | :none | {:error, {:transient, term()} | term()}
  def plan_chapter(chapter, voice, opts \\ []) do
    base = Keyword.get(opts, :base, System.get_env("STORAGE_PATH", "priv/static/files"))
    chat = Keyword.get_lazy(opts, :chat, &default_chat/0)

    with {:ok, library} <- Library.for_voice(voice),
         true <- chat != nil || :none do
      # One planning run per book at a time: the generation and planning queues can
      # reach the same chapter together, and each run reads and rewrites the book's
      # state. The plan is looked up again under the lock, so the second run uses
      # the first one's plan.
      # The lock id is {resource, requester}: each caller must be its own requester.
      :global.trans(
        {{__MODULE__, chapter.book_id}, self()},
        fn -> plan_locked(chapter, voice, library, chat, base) end,
        [node()],
        :infinity
      )
    end
  end

  defp plan_locked(chapter, voice, library, chat, base) do
    case chapter |> VoicePlan.load(base) |> VoicePlan.for_voice(voice) do
      {:ok, plan} ->
        {:ok, plan}

      _ ->
        with {:ok, html} <- ReadaloudLibrary.get_chapter_content(chapter) do
          book = ReadaloudLibrary.get_book!(chapter.book_id)
          state = State.load(book.id, base, State.new(book.title))
          started = System.monotonic_time(:millisecond)

          case plan(html, library, state, chat) do
            {:ok, doc, state} ->
              with {:ok, plan} <- save_or_plain(chapter, doc, html, library, base) do
                State.save(state, book.id, base)
                ms = System.monotonic_time(:millisecond) - started

                Logger.info(
                  "Planned chapter #{chapter.number}: #{length(plan.chunks)} chunks in #{ms} ms"
                )

                {:ok, plan}
              end

            {:error, :empty_chapter} = empty ->
              empty

            {:error, reason} ->
              if transient?(reason),
                do: {:error, {:transient, reason}},
                else: save_or_plain(chapter, {:error, reason}, html, library, base)
          end
        end
    end
  end

  # A plan that can't be made or saved for a reason that won't go away is replaced
  # by a plain one, so the chapter counts as planned and is not queued again.
  defp save_or_plain(chapter, doc, html, library, base) do
    result = if is_map(doc), do: VoicePlan.save(chapter, doc, base), else: doc

    case result do
      {:ok, plan} ->
        {:ok, plan}

      {:error, reason} ->
        Logger.warning(
          "Chapter #{chapter.number} read from the voice's own clip: #{inspect(reason)}"
        )

        VoicePlan.save(chapter, plain(html, library), base)
    end
  end

  defp transient?({kind, _}) when kind in [:transport, :http], do: true
  defp transient?(:no_usable_reply), do: true
  defp transient?(_), do: false

  @doc "A plan reading the whole chapter from the voice's own clip, as before plans existed."
  def plain(html, %Library{} = library) do
    text = html |> Text.paragraphs() |> Enum.join("\n")

    %{
      "model" => library.model,
      "voice" => library.voice,
      "temperature" => nil,
      "chunks" => Passages.chunks([{text, library.fallback}], %{})
    }
  end

  defp default_chat do
    case System.get_env("BONSAI_URL") do
      url when url in [nil, ""] -> nil
      url -> Bonsai.chat(url)
    end
  end

  @doc "The plan document for one chapter's HTML, and the book's state after it."
  @spec plan(String.t(), Library.t(), State.t(), function()) ::
          {:ok, map(), State.t()} | {:error, term()}
  def plan(html, %Library{} = library, %State{} = state, chat) do
    paragraphs = Text.paragraphs(html)
    units = Text.units(paragraphs)

    context = state.context || ""

    with :ok <- non_empty(units),
         {:ok, tags} <- Bonsai.tag(chat, Enum.map(units, & &1.text), context),
         passages = Passages.build(units, tags),
         {:ok, picks} <-
           Bonsai.assign(
             chat,
             Enum.map(passages, &String.trim(&1.text)),
             Library.menu(library),
             context
           ),
         text = Enum.join(paragraphs, "\n"),
         {:ok, found} <- Bonsai.names(chat, text) do
      passage_tags = Enum.map(passages, & &1.tag)

      picks =
        library
        |> Library.enforce_group(passage_tags, picks)
        |> then(&Library.one_voice_per_speaker(passage_tags, &1))

      {picks, speakers} = Library.remember_speakers(library, passage_tags, picks, state.speakers)

      known = Map.merge(state.names, state.words)
      names = Map.merge(Names.new_names(found, text, known), state.names)
      name_map = Map.merge(names, state.words)

      chunks =
        passages
        |> Enum.zip(picks)
        |> Enum.map(fn {p, pick} -> {p.text, Library.clip(library, pick)} end)
        |> Passages.chunks(name_map)

      doc = %{
        "model" => library.model,
        "voice" => library.voice,
        "temperature" => library.temperature,
        "chunks" => chunks
      }

      {:ok, doc, %{state | names: names, speakers: speakers}}
    end
  end

  defp non_empty([]), do: {:error, :empty_chapter}
  defp non_empty(_units), do: :ok
end
