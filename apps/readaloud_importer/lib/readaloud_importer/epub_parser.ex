defmodule ReadaloudImporter.EpubParser do
  def build_command(epub_path, output_dir) do
    {"ebook-convert", [epub_path, Path.join(output_dir, "book.htmlz")]}
  end

  def parse(epub_path, storage_dir) do
    tmp_dir = Path.join(System.tmp_dir!(), "readaloud_import_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(tmp_dir)

    try do
      {cmd, args} = build_command(epub_path, tmp_dir)

      case System.cmd(cmd, args, stderr_to_stdout: true) do
        {_output, 0} ->
          htmlz_path = Path.join(tmp_dir, "book.htmlz")
          extract_from_htmlz(htmlz_path, storage_dir)

        {output, code} ->
          {:error, "ebook-convert exited with #{code}: #{output}"}
      end
    after
      File.rm_rf!(tmp_dir)
    end
  end

  defp extract_from_htmlz(htmlz_path, storage_dir) do
    File.mkdir_p!(storage_dir)

    case :zip.unzip(String.to_charlist(htmlz_path), [{:cwd, String.to_charlist(storage_dir)}]) do
      {:ok, _files} ->
        html_path = Path.join(storage_dir, "index.html")

        case File.read(html_path) do
          {:ok, html} ->
            chapters = extract_chapters(html)
            metadata = extract_metadata(storage_dir)
            {:ok, %{chapters: chapters, metadata: metadata}}

          {:error, reason} ->
            {:error, "Failed to read extracted HTML: #{reason}"}
        end

      {:error, reason} ->
        {:error, "Failed to unzip HTMLZ: #{inspect(reason)}"}
    end
  end

  def extract_chapters(html) do
    parts = Regex.split(~r/<h[12][^>]*>(.*?)<\/h[12]>/s, html, include_captures: true, trim: true)

    parts
    |> chunk_by_heading()
    |> Enum.with_index(1)
    |> Enum.map(fn {{title, content}, index} ->
      clean_content = String.trim(content)
      word_count = clean_content |> String.replace(~r/<[^>]+>/, " ") |> String.split(~r/\s+/, trim: true) |> length()
      %{title: title, number: index, content: clean_content, word_count: word_count}
    end)
  end

  defp chunk_by_heading(parts) do
    parts
    |> Enum.reduce([], fn part, acc ->
      case Regex.run(~r/<h[12][^>]*>(.*?)<\/h[12]>/s, part) do
        [_, title] ->
          [{String.trim(title), ""} | acc]

        nil ->
          case acc do
            [{title, existing} | rest] -> [{title, existing <> part} | rest]
            [] -> acc
          end
      end
    end)
    |> Enum.reverse()
  end

  defp extract_metadata(dir) do
    opf_path = Path.join(dir, "metadata.opf")

    if File.exists?(opf_path) do
      case File.read(opf_path) do
        {:ok, content} ->
          title = extract_tag(content, "dc:title") || "Unknown"
          author = extract_tag(content, "dc:creator")
          %{title: title, author: author}

        _ ->
          %{title: "Unknown", author: nil}
      end
    else
      %{title: "Unknown", author: nil}
    end
  end

  defp extract_tag(xml, tag) do
    case Regex.run(~r/<#{Regex.escape(tag)}[^>]*>(.*?)<\/#{Regex.escape(tag)}>/s, xml) do
      [_, value] -> String.trim(value)
      _ -> nil
    end
  end
end
