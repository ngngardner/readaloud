defmodule ReadaloudWebWeb.PlayerLive do
  use ReadaloudWebWeb, :live_view

  @impl true
  def mount(%{"id" => book_id, "chapter_id" => chapter_id}, _session, socket) do
    book = ReadaloudLibrary.get_book!(String.to_integer(book_id))
    chapter = ReadaloudLibrary.get_chapter!(String.to_integer(chapter_id))
    {:ok, content} = ReadaloudLibrary.get_chapter_content(chapter)
    audio = ReadaloudAudiobook.get_chapter_audio(chapter.id)
    progress = ReadaloudReader.get_progress(book.id)

    socket =
      socket
      |> assign(:book, book)
      |> assign(:chapter, chapter)
      |> assign(:content, content)
      |> assign(:has_audio, audio != nil)
      |> assign(:audio_url, "/api/books/#{book_id}/chapters/#{chapter_id}/audio")
      |> assign(:timings_url, "/api/books/#{book_id}/chapters/#{chapter_id}/timings")
      |> assign(:initial_position_ms, (progress && progress.audio_position_ms) || 0)

    {:ok, socket}
  end

  @impl true
  def handle_event("audio_position", %{"position_ms" => ms}, socket) do
    ReadaloudReader.upsert_progress(%{
      book_id: socket.assigns.book.id,
      current_chapter_id: socket.assigns.chapter.id,
      audio_position_ms: ms
    })

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto p-6">
      <div class="mb-4">
        <.link navigate={~p"/books/#{@book.id}"} class="text-sm opacity-60 hover:opacity-100">
          &larr; <%= @book.title %>
        </.link>
        <h1 class="text-xl font-bold mt-2">
          <%= @chapter.title || "Chapter #{@chapter.number}" %>
        </h1>
      </div>

      <div :if={!@has_audio} class="alert alert-warning mb-6">
        No audio generated for this chapter yet.
        <.link navigate={~p"/books/#{@book.id}"} class="link">Go back</.link>
        to generate it.
      </div>

      <div
        :if={@has_audio}
        id="audio-player"
        phx-hook="AudioPlayer"
        data-audio-url={@audio_url}
        data-timings-url={@timings_url}
        data-initial-position={@initial_position_ms}
      >
        <div id="player-controls" class="sticky top-0 z-10 bg-base-100 p-4 rounded-lg shadow mb-6">
          <audio id="audio-element" preload="auto"></audio>
          <div class="flex items-center gap-4">
            <button id="play-pause-btn" class="btn btn-circle btn-primary btn-sm">
              &#9654;
            </button>
            <div id="progress-bar" class="flex-1 h-2 bg-base-300 rounded cursor-pointer relative">
              <div
                id="progress-fill"
                class="h-full bg-primary rounded transition-all"
                style="width: 0%"
              >
              </div>
            </div>
            <span id="time-display" class="text-sm font-mono opacity-60">0:00 / 0:00</span>
          </div>
        </div>

        <div id="chapter-text" class="prose prose-lg max-w-none leading-relaxed">
          <%= raw(prepare_text_with_spans(@content)) %>
        </div>
      </div>
    </div>
    """
  end

  defp prepare_text_with_spans(html) do
    # Split on whitespace boundaries while preserving HTML tags
    # Wrap each word in a span with data-word-index
    {_idx, parts} =
      Regex.split(~r/(<[^>]+>)/, html, include_captures: true)
      |> Enum.reduce({0, []}, fn segment, {idx, acc} ->
        if String.starts_with?(segment, "<") do
          # HTML tag - pass through
          {idx, [segment | acc]}
        else
          # Text - wrap each word
          words = String.split(segment, ~r/(\s+)/, include_captures: true)

          {new_idx, wrapped} =
            Enum.reduce(words, {idx, []}, fn word, {i, wacc} ->
              if String.match?(word, ~r/^\s*$/) do
                {i, [word | wacc]}
              else
                {i + 1,
                 ["<span class=\"word\" data-word-index=\"#{i}\">#{word}</span>" | wacc]}
              end
            end)

          {new_idx, Enum.reverse(wrapped) ++ acc}
        end
      end)

    parts |> Enum.reverse() |> Enum.join()
  end
end
