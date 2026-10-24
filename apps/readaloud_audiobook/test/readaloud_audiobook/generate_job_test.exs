defmodule ReadaloudAudiobook.GenerateJobTest do
  use ExUnit.Case, async: false

  alias ReadaloudAudiobook.{AudiobookTask, GenerateJob}
  alias ReadaloudLibrary.Repo

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    {:ok, book} = ReadaloudLibrary.create_book(%{title: "Empty test", source_type: "epub"})
    %{book: book}
  end

  # Regression: chapters with no text used to land on LocalAI as an empty
  # synthesis call, which 500s and burns Oban retry attempts. Now we fail
  # fast with :empty_chapter_content and never hit the network.
  describe "perform/1 on empty chapter content" do
    test "fails the task with empty_chapter_content and does not call TTS", %{book: book} do
      empty_path =
        Path.join(System.tmp_dir!(), "empty_chapter_#{System.unique_integer([:positive])}.html")

      File.write!(empty_path, "")

      {:ok, chapter} =
        ReadaloudLibrary.create_chapter(%{book_id: book.id, number: 1, content_path: empty_path})

      task =
        %AudiobookTask{}
        |> AudiobookTask.changeset(%{
          book_id: book.id,
          chapter_id: chapter.id,
          model: "kokoro",
          voice: "af_heart",
          status: :pending,
          attempt_number: 1
        })
        |> Repo.insert!()

      job = %Oban.Job{id: 0, args: %{"task_id" => task.id}}

      assert {:error, :empty_chapter_content} = GenerateJob.perform(job)

      reloaded = Repo.get!(AudiobookTask, task.id)
      assert reloaded.status == :failed
      assert reloaded.error_message =~ "empty_chapter_content"
    end

    test "fails on whitespace-only HTML", %{book: book} do
      path = Path.join(System.tmp_dir!(), "ws_chapter_#{System.unique_integer([:positive])}.html")
      File.write!(path, "<p>   </p>\n<div>&nbsp;</div>")

      {:ok, chapter} =
        ReadaloudLibrary.create_chapter(%{book_id: book.id, number: 2, content_path: path})

      task =
        %AudiobookTask{}
        |> AudiobookTask.changeset(%{
          book_id: book.id,
          chapter_id: chapter.id,
          model: "kokoro",
          voice: "af_heart",
          status: :pending,
          attempt_number: 1
        })
        |> Repo.insert!()

      job = %Oban.Job{id: 0, args: %{"task_id" => task.id}}

      assert {:error, :empty_chapter_content} = GenerateJob.perform(job)
    end

    # Regression: a Reverend Insanity crawl source injected an h12-media ad
    # block whose <script> body was getting spoken aloud as raw JavaScript.
    # strip_html/1 now drops <script>/<style>/<iframe> bodies whole before
    # the generic tag pass, so a script-only chapter strips to empty and we
    # fail fast rather than synthesizing JS source code.
    test "strips <script> bodies — chapter that is only an ad fails empty", %{book: book} do
      path = Path.join(System.tmp_dir!(), "ad_chapter_#{System.unique_integer([:positive])}.html")

      File.write!(path, """
      <script>
      /* info line, ad unit name: Ad02*/
      window.h12_autoplaced_enable=1;
      window.h12_autoplaced_pub="abc";
      </script>
      <iframe src="https://ads.example.com"></iframe>
      <style>.x{color:red}</style>
      """)

      {:ok, chapter} =
        ReadaloudLibrary.create_chapter(%{book_id: book.id, number: 3, content_path: path})

      task =
        %AudiobookTask{}
        |> AudiobookTask.changeset(%{
          book_id: book.id,
          chapter_id: chapter.id,
          model: "kokoro",
          voice: "af_heart",
          status: :pending,
          attempt_number: 1
        })
        |> Repo.insert!()

      job = %Oban.Job{id: 0, args: %{"task_id" => task.id}}

      assert {:error, :empty_chapter_content} = GenerateJob.perform(job)
    end
  end

  # Stands in for LocalAI: records every request in the test process's
  # mailbox and answers with a short, valid 24 kHz PCM WAV.
  defmodule RecordingProvider do
    @behaviour ReadaloudTTS.Provider

    @impl true
    def synthesize(text, voice, opts) do
      send(self(), {:synthesize, text, voice, Keyword.drop(opts, [:provider])})
      pcm = for i <- 0..2399, into: <<>>, do: <<round(:math.sin(i / 8) * 8000)::little-signed-16>>
      {:ok, wav(pcm)}
    end

    @impl true
    def transcribe(_audio, _opts), do: {:ok, []}

    @impl true
    def catalog(_opts), do: {:ok, []}

    @impl true
    def max_chunk_chars(_voice), do: 400

    defp wav(pcm) do
      size = byte_size(pcm)

      <<"RIFF", 36 + size::little-32, "WAVE", "fmt ", 16::little-32, 1::little-16, 1::little-16,
        24_000::little-32, 48_000::little-32, 2::little-16, 16::little-16, "data",
        size::little-32, pcm::binary>>
    end
  end

  describe "perform/1 with a voice plan" do
    setup %{book: book} do
      storage = Path.join(System.tmp_dir!(), "plan_job_#{System.unique_integer([:positive])}")
      previous = System.get_env("STORAGE_PATH")
      System.put_env("STORAGE_PATH", storage)
      Application.put_env(:readaloud_audiobook, :tts_opts, provider: RecordingProvider)

      on_exit(fn ->
        Application.delete_env(:readaloud_audiobook, :tts_opts)

        if previous,
          do: System.put_env("STORAGE_PATH", previous),
          else: System.delete_env("STORAGE_PATH")

        File.rm_rf!(storage)
      end)

      path = Path.join(storage, "chapter.html")
      File.mkdir_p!(storage)
      File.write!(path, "<p>Feng Jiu Ge smiled.</p><p>\u201cLeave,\u201d she said.</p>")

      {:ok, chapter} =
        ReadaloudLibrary.create_chapter(%{book_id: book.id, number: 7, content_path: path})

      %{chapter: chapter}
    end

    defp breeze_task(book, chapter) do
      %AudiobookTask{}
      |> AudiobookTask.changeset(%{
        book_id: book.id,
        chapter_id: chapter.id,
        model: "breeze-tts-2",
        voice: "heath-miller",
        status: :pending,
        attempt_number: 1
      })
      |> Repo.insert!()
    end

    defp plan(model) do
      %{
        "model" => model,
        "voice" => "heath-miller",
        "temperature" => 0.6,
        "chunks" => [
          %{
            "text" => "Feng Jiu Ge smiled.",
            "spoken" => "Fung Jyo Guhh smiled.",
            "voice" => "/models/voices/hwfwm-narration-0.wav",
            "reference_text" => "The walls were black."
          },
          %{
            "text" => "\u201cLeave,\u201d she said.",
            "spoken" => "\u201cLeave,\u201d she said.",
            "voice" => "/models/voices/hwfwm-female-0.wav",
            "reference_text" => "Get out of my sight."
          }
        ]
      }
    end

    test "each chunk is spoken from its own clip at the plan's temperature", %{
      book: book,
      chapter: chapter
    } do
      {:ok, _} = ReadaloudAudiobook.VoicePlan.save(chapter, plan("breeze-tts-2"))
      task = breeze_task(book, chapter)

      assert :ok = GenerateJob.perform(%Oban.Job{id: 0, args: %{"task_id" => task.id}})

      assert_received {:synthesize, "Fung Jyo Guhh smiled.", _voice, opts1}
      assert opts1[:reference].voice == "/models/voices/hwfwm-narration-0.wav"
      assert opts1[:temperature] == 0.6

      assert_received {:synthesize, "\u201cLeave,\u201d she said.", _voice, opts2}
      assert opts2[:reference].voice == "/models/voices/hwfwm-female-0.wav"

      assert ReadaloudAudiobook.get_chapter_audio(chapter.id).voice == "heath-miller"
    end

    test "without a plan the chapter is read as before, from the voice's own clip", %{
      book: book,
      chapter: chapter
    } do
      task = breeze_task(book, chapter)

      assert :ok = GenerateJob.perform(%Oban.Job{id: 0, args: %{"task_id" => task.id}})

      assert_received {:synthesize, text, _voice, opts}
      assert text =~ "Feng Jiu Ge smiled."
      refute Keyword.has_key?(opts, :reference)
    end

    test "a chapter with no plan is planned first, then read from its plan", %{
      book: book,
      chapter: chapter
    } do
      Application.put_env(:readaloud_audiobook, :planner_opts,
        chat: ReadaloudAudiobook.PlannerTest.model()
      )

      on_exit(fn -> Application.delete_env(:readaloud_audiobook, :planner_opts) end)
      task = breeze_task(book, chapter)

      assert :ok = GenerateJob.perform(%Oban.Job{id: 0, args: %{"task_id" => task.id}})

      assert {:ok, _} = ReadaloudAudiobook.VoicePlan.load(chapter)
      assert_received {:synthesize, _text, _voice, opts}
      assert opts[:reference].voice =~ "/models/voices/hwfwm-"
    end

    # The model being down is temporary: the job waits rather than reading the
    # chapter from the plain clip for good. Existing audio stays playable.
    test "an unreachable model snoozes the job without starting it", %{
      book: book,
      chapter: chapter
    } do
      down = fn _, _, _ -> {:error, {:transport, :econnrefused}} end
      Application.put_env(:readaloud_audiobook, :planner_opts, chat: down)
      on_exit(fn -> Application.delete_env(:readaloud_audiobook, :planner_opts) end)
      task = breeze_task(book, chapter)

      assert {:snooze, _} =
               GenerateJob.perform(%Oban.Job{id: 0, attempt: 1, args: %{"task_id" => task.id}})

      refute_received {:synthesize, _, _, _}
      assert Repo.get!(AudiobookTask, task.id).status == :pending
    end

    test "after an hour of snoozing the task fails instead", %{book: book, chapter: chapter} do
      down = fn _, _, _ -> {:error, {:transport, :econnrefused}} end
      Application.put_env(:readaloud_audiobook, :planner_opts, chat: down)
      on_exit(fn -> Application.delete_env(:readaloud_audiobook, :planner_opts) end)
      task = breeze_task(book, chapter)

      assert {:cancel, _} =
               GenerateJob.perform(%Oban.Job{id: 0, attempt: 20, args: %{"task_id" => task.id}})

      assert Repo.get!(AudiobookTask, task.id).status == :failed
    end

    test "a plan made for another voice is ignored", %{book: book, chapter: chapter} do
      {:ok, _} = ReadaloudAudiobook.VoicePlan.save(chapter, plan("some-other-model"))
      task = breeze_task(book, chapter)

      assert :ok = GenerateJob.perform(%Oban.Job{id: 0, args: %{"task_id" => task.id}})

      assert_received {:synthesize, text, _voice, opts}
      assert text =~ "Feng Jiu Ge smiled."
      refute Keyword.has_key?(opts, :reference)
    end
  end
end
