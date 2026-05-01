defmodule ReadaloudImporter.PdfParser do
  @moduledoc """
  PDF parser. Prefers the PDF outline (bookmarks) for chapter splitting;
  falls back to text heading regex when the document has no outline.
  """

  @chapter_pattern ~r/^(Chapter\s+\d+[^\n]*|CHAPTER\s+\d+[^\n]*|Part\s+\d+[^\n]*)/m
  @outline_section_pattern ~r/<a name="outline"><\/a><h1>Document Outline<\/h1>\s*<ul>(.*?)<\/ul>/s
  @outline_entry_pattern ~r/<li><a href="[^#]*#(\d+)">([^<]+)<\/a>/

  def build_command(pdf_path, output_path) do
    {"pdftotext", ["-layout", pdf_path, output_path]}
  end

  def parse(pdf_path, storage_dir) do
    metadata = read_metadata(pdf_path)

    chapters_result =
      case extract_outline(pdf_path) do
        {:ok, [_, _ | _] = entries} ->
          extract_chapters_by_outline(pdf_path, entries, metadata.page_count)

        _ ->
          extract_chapters_by_regex(pdf_path)
      end

    case chapters_result do
      {:ok, chapters} ->
        cover_image =
          case extract_thumbnail(pdf_path, storage_dir) do
            {:ok, bytes} -> bytes
            {:error, _} -> nil
          end

        {:ok,
         %{
           chapters: chapters,
           metadata: %{title: metadata.title, author: metadata.author},
           cover_image: cover_image
         }}

      {:error, _} = error ->
        error
    end
  end

  # Public for unit tests
  def parse_outline_entries(pdftohtml_html) do
    case Regex.run(@outline_section_pattern, pdftohtml_html, capture: :all_but_first) do
      [section] ->
        Regex.scan(@outline_entry_pattern, section, capture: :all_but_first)
        |> Enum.map(fn [page, title] ->
          %{title: html_decode(String.trim(title)), page: String.to_integer(page)}
        end)

      _ ->
        []
    end
  end

  def extract_chapters(text) do
    case Regex.split(@chapter_pattern, text, include_captures: true, trim: true) do
      parts when length(parts) >= 2 ->
        parts
        |> chunk_by_heading()
        |> Enum.with_index(1)
        |> Enum.map(fn {{title, content}, index} ->
          clean = String.trim(content)
          %{title: title, number: index, content: clean, word_count: word_count(clean)}
        end)

      _ ->
        clean = String.trim(text)
        [%{title: "Full Text", number: 1, content: clean, word_count: word_count(clean)}]
    end
  end

  defp extract_outline(pdf_path) do
    tmp_dir =
      Path.join(System.tmp_dir!(), "readaloud_outline_#{:erlang.unique_integer([:positive])}")

    File.mkdir_p!(tmp_dir)
    stem = Path.join(tmp_dir, "doc")

    try do
      case System.cmd("pdftohtml", ["-i", "-nodrm", "-q", pdf_path, stem], stderr_to_stdout: true) do
        {_, 0} ->
          html_path = stem <> "s.html"

          case File.read(html_path) do
            {:ok, html} -> {:ok, parse_outline_entries(html)}
            {:error, reason} -> {:error, "Failed to read pdftohtml output: #{reason}"}
          end

        {output, code} ->
          {:error, "pdftohtml exited with #{code}: #{output}"}
      end
    after
      File.rm_rf(tmp_dir)
    end
  end

  defp extract_chapters_by_outline(pdf_path, entries, page_count) do
    ranges =
      entries
      |> Enum.with_index()
      |> Enum.map(fn {entry, idx} ->
        start_page = entry.page

        end_page =
          case Enum.at(entries, idx + 1) do
            nil -> page_count
            next -> max(next.page - 1, start_page)
          end

        {entry.title, start_page, end_page}
      end)

    chapters =
      ranges
      |> Enum.with_index(1)
      |> Enum.reduce_while({:ok, []}, fn {{title, first, last}, number}, {:ok, acc} ->
        case extract_text_for_pages(pdf_path, first, last) do
          {:ok, text} ->
            clean = String.trim(text)

            chapter = %{
              title: title,
              number: number,
              content: clean,
              word_count: word_count(clean)
            }

            {:cont, {:ok, [chapter | acc]}}

          {:error, _} = error ->
            {:halt, error}
        end
      end)

    case chapters do
      {:ok, list} -> {:ok, Enum.reverse(list)}
      error -> error
    end
  end

  defp extract_chapters_by_regex(pdf_path) do
    tmp_txt =
      Path.join(System.tmp_dir!(), "readaloud_pdf_#{:erlang.unique_integer([:positive])}.txt")

    try do
      {cmd, args} = build_command(pdf_path, tmp_txt)

      case System.cmd(cmd, args, stderr_to_stdout: true) do
        {_, 0} ->
          case File.read(tmp_txt) do
            {:ok, text} -> {:ok, extract_chapters(text)}
            {:error, reason} -> {:error, "Failed to read extracted text: #{reason}"}
          end

        {output, code} ->
          {:error, "pdftotext exited with #{code}: #{output}"}
      end
    after
      File.rm(tmp_txt)
    end
  end

  defp extract_text_for_pages(pdf_path, first, last) do
    tmp_txt =
      Path.join(System.tmp_dir!(), "readaloud_pdf_#{:erlang.unique_integer([:positive])}.txt")

    try do
      args = ["-layout", "-f", "#{first}", "-l", "#{last}", pdf_path, tmp_txt]

      case System.cmd("pdftotext", args, stderr_to_stdout: true) do
        {_, 0} -> File.read(tmp_txt)
        {output, code} -> {:error, "pdftotext exited with #{code}: #{output}"}
      end
    after
      File.rm(tmp_txt)
    end
  end

  defp read_metadata(pdf_path) do
    case System.cmd("pdfinfo", [pdf_path], stderr_to_stdout: true) do
      {output, 0} ->
        %{
          title: parse_pdfinfo_field(output, "Title") || pdf_title_from_path(pdf_path),
          author: parse_pdfinfo_field(output, "Author"),
          page_count: parse_pdfinfo_int(output, "Pages") || 1
        }

      _ ->
        %{title: pdf_title_from_path(pdf_path), author: nil, page_count: 1}
    end
  end

  defp parse_pdfinfo_field(output, name) do
    case Regex.run(~r/^#{Regex.escape(name)}:\s+(.+)$/m, output) do
      [_, value] ->
        trimmed = String.trim(value)
        if trimmed == "", do: nil, else: trimmed

      _ ->
        nil
    end
  end

  defp parse_pdfinfo_int(output, name) do
    case parse_pdfinfo_field(output, name) do
      nil ->
        nil

      value ->
        case Integer.parse(value) do
          {n, _} -> n
          _ -> nil
        end
    end
  end

  defp pdf_title_from_path(path), do: path |> Path.basename() |> Path.rootname()

  defp chunk_by_heading(parts) do
    parts
    |> Enum.reduce([], fn part, acc ->
      if Regex.match?(@chapter_pattern, String.trim(part)) do
        [{String.trim(part), ""} | acc]
      else
        case acc do
          [{title, existing} | rest] -> [{title, existing <> part} | rest]
          [] -> [{part, ""} | acc]
        end
      end
    end)
    |> Enum.reverse()
  end

  defp extract_thumbnail(pdf_path, storage_dir) do
    File.mkdir_p!(storage_dir)
    output_prefix = Path.join(storage_dir, "cover")

    case System.cmd(
           "pdftoppm",
           [
             "-jpeg",
             "-f",
             "1",
             "-l",
             "1",
             "-scale-to-x",
             "300",
             "-scale-to-y",
             "400",
             pdf_path,
             output_prefix
           ],
           stderr_to_stdout: true
         ) do
      {_, 0} ->
        # pdftoppm appends a page suffix that varies by version: "cover-1.jpg"
        # on older releases, "cover-001.jpg" on newer ones.
        case Path.wildcard(Path.join(storage_dir, "cover-*.jpg")) do
          [cover_file | _] ->
            bytes = File.read!(cover_file)
            File.rm(cover_file)
            {:ok, bytes}

          [] ->
            {:error, :thumbnail_failed}
        end

      {output, _} ->
        {:error, "pdftoppm failed: #{output}"}
    end
  end

  defp word_count(text), do: text |> String.split(~r/\s+/, trim: true) |> length()

  defp html_decode(text) do
    text
    |> String.replace("&amp;", "&")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", "\"")
    |> String.replace("&#39;", "'")
    |> String.replace("&apos;", "'")
  end
end
