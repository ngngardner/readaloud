defmodule ReadaloudImporter.PdfParser do
  @chapter_pattern ~r/^(Chapter\s+\d+[^\n]*|CHAPTER\s+\d+[^\n]*|Part\s+\d+[^\n]*)/m

  def build_command(pdf_path, output_path) do
    {"pdftotext", ["-layout", pdf_path, output_path]}
  end

  def parse(pdf_path, storage_dir) do
    tmp_txt = Path.join(System.tmp_dir!(), "readaloud_pdf_#{:erlang.unique_integer([:positive])}.txt")

    try do
      {cmd, args} = build_command(pdf_path, tmp_txt)

      case System.cmd(cmd, args, stderr_to_stdout: true) do
        {_output, 0} ->
          case File.read(tmp_txt) do
            {:ok, text} ->
              chapters = extract_chapters(text)

              cover_image =
                case extract_thumbnail(pdf_path, storage_dir) do
                  {:ok, bytes} -> bytes
                  {:error, _} -> nil
                end

              {:ok, %{chapters: chapters, metadata: %{title: pdf_title(pdf_path), author: nil}, cover_image: cover_image}}

            {:error, reason} ->
              {:error, "Failed to read extracted text: #{reason}"}
          end

        {output, code} ->
          {:error, "pdftotext exited with #{code}: #{output}"}
      end
    after
      File.rm(tmp_txt)
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

    case System.cmd("pdftoppm", [
      "-jpeg", "-f", "1", "-l", "1",
      "-scale-to-x", "300", "-scale-to-y", "400",
      pdf_path, output_prefix
    ], stderr_to_stdout: true) do
      {_, 0} ->
        # pdftoppm adds page number suffix: cover-1.jpg
        cover_file = Path.join(storage_dir, "cover-1.jpg")

        if File.exists?(cover_file) do
          {:ok, File.read!(cover_file)}
        else
          {:error, :thumbnail_failed}
        end

      {output, _} ->
        {:error, "pdftoppm failed: #{output}"}
    end
  end

  defp word_count(text), do: text |> String.split(~r/\s+/, trim: true) |> length()
  defp pdf_title(path), do: path |> Path.basename() |> Path.rootname()
end
