defmodule ReadaloudWebWeb.ReaderLive do
  use ReadaloudWebWeb, :live_view

  @impl true
  def mount(%{"id" => book_id, "chapter_id" => chapter_id}, _session, socket) do
    book = ReadaloudLibrary.get_book!(String.to_integer(book_id))
    chapter = ReadaloudLibrary.get_chapter!(String.to_integer(chapter_id))
    chapters = ReadaloudLibrary.list_chapters(book.id)
    {:ok, content} = ReadaloudLibrary.get_chapter_content(chapter)
    progress = ReadaloudReader.get_progress(book.id)

    socket =
      socket
      |> assign(:book, book)
      |> assign(:chapter, chapter)
      |> assign(:chapters, chapters)
      |> assign(:content, content)
      |> assign(:initial_scroll, (progress && progress.scroll_position) || 0.0)

    {:ok, socket}
  end

  @impl true
  def handle_event("scroll", %{"position" => position}, socket) do
    ReadaloudReader.upsert_progress(%{
      book_id: socket.assigns.book.id,
      current_chapter_id: socket.assigns.chapter.id,
      scroll_position: position
    })

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-3xl mx-auto p-6">
      <div class="flex justify-between items-center mb-6">
        <.link navigate={~p"/books/#{@book.id}"} class="text-sm opacity-60 hover:opacity-100">
          &larr; <%= @book.title %>
        </.link>
        <.link
          :if={audio_available?(@chapter)}
          navigate={~p"/books/#{@book.id}/listen/#{@chapter.id}"}
          class="btn btn-primary btn-xs"
        >
          Listen
        </.link>
      </div>

      <h1 class="text-2xl font-bold mb-6">
        <%= @chapter.title || "Chapter #{@chapter.number}" %>
      </h1>

      <div
        id="reader-content"
        phx-hook="ScrollTracker"
        data-initial-scroll={@initial_scroll}
        class="prose prose-lg max-w-none overflow-y-auto"
        style="max-height: calc(100vh - 200px);"
      >
        <%= raw(@content) %>
      </div>

      <div class="flex justify-between mt-6">
        <%= if prev = prev_chapter(@chapter, @chapters) do %>
          <.link navigate={~p"/books/#{@book.id}/read/#{prev.id}"} class="btn btn-ghost btn-sm">
            &larr; Previous
          </.link>
        <% else %>
          <div></div>
        <% end %>
        <%= if nxt = next_chapter(@chapter, @chapters) do %>
          <.link navigate={~p"/books/#{@book.id}/read/#{nxt.id}"} class="btn btn-ghost btn-sm">
            Next &rarr;
          </.link>
        <% end %>
      </div>
    </div>
    """
  end

  defp prev_chapter(current, chapters) do
    Enum.find(chapters, &(&1.number == current.number - 1))
  end

  defp next_chapter(current, chapters) do
    Enum.find(chapters, &(&1.number == current.number + 1))
  end

  defp audio_available?(chapter) do
    ReadaloudAudiobook.get_chapter_audio(chapter.id) != nil
  end
end
