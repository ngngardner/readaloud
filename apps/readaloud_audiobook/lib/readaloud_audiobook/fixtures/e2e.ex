defmodule ReadaloudAudiobook.Fixtures.E2E do
  @moduledoc """
  Canonical seed for the end-to-end test suite.

  Lives here (not in `readaloud_library`) because the fixture writes
  both `chapters` and `chapter_audios`, and `readaloud_audiobook` is
  the only umbrella app that depends on both. Called from
  `cells/app/checks/e2e.nix` via `bin/readaloud rpc` so the seed
  shape stays in sync with the Ecto schema — a migration that adds
  a NOT NULL column will fail the build, not the VM.

  Idempotent: deleting the prior fixture book before insert keeps
  ROWIDs at 1 in a fresh SQLite DB, which is what the e2e tests
  default to (`BOOK_ID=1`).
  """

  import Ecto.Query

  alias ReadaloudAudiobook.ChapterAudio
  alias ReadaloudLibrary.{Book, Chapter, Repo}

  @default_title "Test Book"
  @default_author "Test Author"
  @default_chapter_count 3
  @default_audio_chapters [1, 2]

  @doc """
  Idempotently seed the e2e fixture book and return its IDs.

  ## Options
    * `:title` — book title (default `"Test Book"`).
    * `:author` — book author (default `"Test Author"`).
    * `:chapters` — chapter count (default `3`; minimum required by
      `accidental-navigation.test.js` and `reader-styles-persist.test.js`).
    * `:audio_for` — chapter numbers that should have a row in
      `chapter_audios` (default `[1, 2]` — `audio-autoplay.test.js`
      requires both a current chapter *and* a next chapter to have audio).
    * `:storage_dir` — directory for content + audio files. Defaults to
      `STORAGE_PATH` env var if set (matches the systemd unit) or
      `System.tmp_dir!()`.

  Writes a 1-second silent WAV (so chromium can `loadedmetadata`) and
  one `<p>Test content N.</p>` HTML file per chapter.

  Returns `%{book_id: integer, chapter_ids: [integer]}`.
  """
  @spec seed!(keyword()) :: %{book_id: integer(), chapter_ids: [integer()]}
  def seed!(opts \\ []) do
    title = Keyword.get(opts, :title, @default_title)
    author = Keyword.get(opts, :author, @default_author)
    chapter_count = Keyword.get(opts, :chapters, @default_chapter_count)
    audio_for = Keyword.get(opts, :audio_for, @default_audio_chapters)

    storage_dir =
      Keyword.get_lazy(opts, :storage_dir, fn ->
        System.get_env("STORAGE_PATH") || System.tmp_dir!()
      end)

    File.mkdir_p!(storage_dir)
    audio_path = Path.join(storage_dir, "e2e-fixture-silent.wav")
    # 30s is long enough for `audio-remount.test.js` to seek to 7.5s
    # without clamping to duration, and short enough to keep the WAV
    # under ~500KB (8kHz mono 16-bit = 16KB/s).
    File.write!(audio_path, silent_wav(30.0))

    {:ok, result} =
      Repo.transaction(fn ->
        from(b in Book, where: b.title == ^title)
        |> Repo.all()
        |> Enum.each(&Repo.delete!/1)

        book =
          %Book{}
          |> Book.changeset(%{
            title: title,
            author: author,
            source_type: :epub,
            total_chapters: chapter_count
          })
          |> Repo.insert!()

        chapter_ids =
          for n <- 1..chapter_count do
            html_path = Path.join(storage_dir, "e2e-fixture-chapter-#{n}.html")
            File.write!(html_path, "<p>Test content #{n}.</p>")

            chapter =
              %Chapter{}
              |> Chapter.changeset(%{
                title: "Chapter #{n}",
                number: n,
                content_path: html_path,
                word_count: 3,
                book_id: book.id
              })
              |> Repo.insert!()

            if n in audio_for do
              %ChapterAudio{}
              |> ChapterAudio.changeset(%{
                chapter_id: chapter.id,
                audio_path: audio_path,
                duration_seconds: 30.0
              })
              |> Repo.insert!()
            end

            chapter.id
          end

        %{book_id: book.id, chapter_ids: chapter_ids}
      end)

    result
  end

  # Minimal valid silent PCM WAV. Mono 8 kHz 16-bit. Chromium parses
  # this and fires `loadedmetadata` with a finite `duration`, which is
  # the only thing the audio-* tests need from the file itself —
  # actual playback is driven by dispatched events.
  defp silent_wav(seconds) when is_number(seconds) and seconds > 0 do
    sample_rate = 8000
    bits = 16
    channels = 1
    block_align = channels * div(bits, 8)
    byte_rate = sample_rate * block_align
    data_bytes = round(sample_rate * seconds) * block_align
    chunk_size = 36 + data_bytes

    <<
      "RIFF",
      chunk_size::little-32,
      "WAVE",
      "fmt ",
      16::little-32,
      1::little-16,
      channels::little-16,
      sample_rate::little-32,
      byte_rate::little-32,
      block_align::little-16,
      bits::little-16,
      "data",
      data_bytes::little-32,
      0::size(data_bytes * 8)
    >>
  end
end
