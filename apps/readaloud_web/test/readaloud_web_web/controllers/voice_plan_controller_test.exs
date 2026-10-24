defmodule ReadaloudWebWeb.VoicePlanControllerTest do
  # STORAGE_PATH is process-global, so not async.
  use ReadaloudWebWeb.ConnCase, async: false

  alias ReadaloudAudiobook.VoicePlan

  @plan %{
    "model" => "breeze-tts-2",
    "voice" => "heath-miller",
    "temperature" => 0.6,
    "chunks" => [
      %{
        "text" => "Feng Jiu Ge smiled.",
        "spoken" => "Fung Jyo Guhh smiled.",
        "voice" => "/models/voices/hwfwm-narration-0.wav",
        "reference_text" => "The walls were black."
      }
    ]
  }

  setup do
    storage = Path.join(System.tmp_dir!(), "plan_api_#{System.unique_integer([:positive])}")
    previous = System.get_env("STORAGE_PATH")
    System.put_env("STORAGE_PATH", storage)

    on_exit(fn ->
      if previous,
        do: System.put_env("STORAGE_PATH", previous),
        else: System.delete_env("STORAGE_PATH")

      File.rm_rf!(storage)
    end)

    File.mkdir_p!(storage)
    html = Path.join(storage, "0001.html")
    File.write!(html, "<h1>Chapter 1</h1><p>Feng Jiu Ge smiled.</p>")

    {:ok, book} =
      ReadaloudLibrary.create_book(%{
        title: "Plan API",
        source_type: "epub",
        audio_preferences: %{model: "breeze-tts-2", voice: "heath-miller"}
      })

    {:ok, ch1} =
      ReadaloudLibrary.create_chapter(%{
        book_id: book.id,
        number: 1,
        title: "Chapter 1",
        content_path: html
      })

    {:ok, ch2} =
      ReadaloudLibrary.create_chapter(%{book_id: book.id, number: 2, title: "Chapter 2"})

    {:ok, other} = ReadaloudLibrary.create_book(%{title: "Other", source_type: "epub"})
    %{book: book, ch1: ch1, ch2: ch2, other: other}
  end

  describe "GET /api/books/:book_id/chapters" do
    test "lists chapters in order with whether each has a voice plan", %{
      conn: conn,
      book: book,
      ch1: ch1,
      ch2: ch2
    } do
      {:ok, _} = VoicePlan.save(ch2, @plan)

      assert %{"chapters" => chapters} =
               conn |> get(~p"/api/books/#{book.id}/chapters") |> json_response(200)

      assert chapters == [
               %{"id" => ch1.id, "number" => 1, "title" => "Chapter 1", "voice_plan" => false},
               %{"id" => ch2.id, "number" => 2, "title" => "Chapter 2", "voice_plan" => true}
             ]
    end
  end

  describe "GET /api/books/:book_id/chapters/:chapter_id/text" do
    test "returns the chapter HTML readaloud reads aloud", %{conn: conn, book: book, ch1: ch1} do
      body = conn |> get(~p"/api/books/#{book.id}/chapters/#{ch1.id}/text") |> json_response(200)
      assert body["number"] == 1
      assert body["html"] =~ "Feng Jiu Ge smiled."
    end

    test "404s for a chapter of another book", %{conn: conn, other: other, ch1: ch1} do
      conn = get(conn, ~p"/api/books/#{other.id}/chapters/#{ch1.id}/text")
      assert json_response(conn, 404)
    end
  end

  describe "PUT /api/books/:book_id/chapters/:chapter_id/voice-plan" do
    test "saves the plan and queues the chapter", %{conn: conn, book: book, ch1: ch1} do
      body =
        conn
        |> put(~p"/api/books/#{book.id}/chapters/#{ch1.id}/voice-plan", @plan)
        |> json_response(200)

      assert body == %{"chunks" => 1, "queue" => "queued"}
      assert {:ok, _} = VoicePlan.load(ch1)
    end

    test "refuses an invalid plan with the reason", %{conn: conn, book: book, ch1: ch1} do
      conn =
        put(conn, ~p"/api/books/#{book.id}/chapters/#{ch1.id}/voice-plan", %{
          @plan
          | "chunks" => []
        })

      assert %{"error" => _} = json_response(conn, 422)
      assert VoicePlan.load(ch1) == :none
    end

    test "404s for a chapter of another book", %{conn: conn, other: other, ch1: ch1} do
      conn = put(conn, ~p"/api/books/#{other.id}/chapters/#{ch1.id}/voice-plan", @plan)
      assert json_response(conn, 404)
    end
  end
end
