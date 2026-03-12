defmodule ReadaloudImporter.EpubParser do
  @moduledoc """
  EPUB parser that reads the epub spine directly.

  EPUBs are zip files containing XHTML documents. The OPF manifest
  defines the reading order (spine). Each spine item is typically a chapter.
  Short items (<100 chars of text) are skipped as navigation/title pages.
  """

  @min_content_length 100
  @max_title_length 200

  def parse(epub_path, _storage_dir) do
    with {:ok, files} <- read_epub_zip(epub_path),
         {:ok, opf_path} <- find_opf(files),
         {:ok, opf_content} <- get_file(files, opf_path),
         {:ok, metadata} <- parse_metadata(opf_content),
         {:ok, spine_ids} <- parse_spine(opf_content),
         {:ok, manifest} <- parse_manifest(opf_content, Path.dirname(opf_path)),
         chapters <- extract_chapters(files, spine_ids, manifest) do
      {:ok, %{chapters: chapters, metadata: metadata}}
    end
  end

  defp read_epub_zip(path) do
    case :zip.unzip(String.to_charlist(path), [:memory]) do
      {:ok, files} ->
        file_map =
          files
          |> Enum.map(fn {name, content} -> {List.to_string(name), content} end)
          |> Map.new()

        {:ok, file_map}

      {:error, reason} ->
        {:error, "Failed to read EPUB: #{inspect(reason)}"}
    end
  end

  defp find_opf(files) do
    # Check META-INF/container.xml for the OPF path
    case Map.get(files, "META-INF/container.xml") do
      nil ->
        # Fallback: find any .opf file
        case Enum.find(Map.keys(files), &String.ends_with?(&1, ".opf")) do
          nil -> {:error, "No OPF file found in EPUB"}
          path -> {:ok, path}
        end

      container_xml ->
        case Regex.run(~r/full-path="([^"]+\.opf)"/s, container_xml) do
          [_, path] -> {:ok, path}
          _ -> {:error, "Could not find OPF path in container.xml"}
        end
    end
  end

  defp get_file(files, path) do
    case Map.get(files, path) do
      nil -> {:error, "File not found in EPUB: #{path}"}
      content -> {:ok, content}
    end
  end

  defp parse_metadata(opf) do
    title = extract_tag(opf, "dc:title") || "Unknown"
    author = extract_tag(opf, "dc:creator")
    {:ok, %{title: title, author: author}}
  end

  defp parse_spine(opf) do
    ids =
      Regex.scan(~r/<itemref\s+idref="([^"]+)"/s, opf)
      |> Enum.map(fn [_, id] -> id end)

    {:ok, ids}
  end

  defp parse_manifest(opf, opf_dir) do
    # Match each <item .../> or <item ...></item> tag, then extract attributes
    {:ok, item_regex} = Regex.compile(~S'<item\s+([^>]+)/>', "s")

    items =
      Regex.scan(item_regex, opf)
      |> Enum.map(fn [_, attrs] ->
        id = extract_attr(attrs, "id")
        href = extract_attr(attrs, "href")
        media_type = extract_attr(attrs, "media-type")

        if id && href && media_type do
          full_path =
            if opf_dir == "" or opf_dir == ".",
              do: URI.decode(href),
              else: Path.join(opf_dir, URI.decode(href))

          {id, %{href: full_path, media_type: media_type}}
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> Map.new()

    {:ok, items}
  end

  defp extract_attr(attrs_str, name) do
    case Regex.run(~r/#{Regex.escape(name)}="([^"]+)"/, attrs_str) do
      [_, value] -> value
      _ -> nil
    end
  end

  defp extract_chapters(files, spine_ids, manifest) do
    spine_ids
    |> Enum.map(fn id -> Map.get(manifest, id) end)
    |> Enum.reject(&is_nil/1)
    |> Enum.filter(fn item -> String.contains?(item.media_type, "html") end)
    |> Enum.map(fn item -> {item.href, Map.get(files, item.href)} end)
    |> Enum.reject(fn {_, content} -> is_nil(content) end)
    |> Enum.map(fn {href, content} ->
      html = to_string(content)
      body = extract_body(html)
      text = strip_html(body)
      title = extract_chapter_title(html, href)
      %{title: title, content: body, text_length: String.length(text), word_count: word_count(text)}
    end)
    |> Enum.filter(fn ch -> ch.text_length >= @min_content_length end)
    |> Enum.with_index(1)
    |> Enum.map(fn {ch, idx} -> ch |> Map.put(:number, idx) |> Map.delete(:text_length) end)
  end

  defp extract_body(html) do
    case Regex.run(~r/<body[^>]*>(.*)<\/body>/s, html) do
      [_, body] -> String.trim(body)
      _ -> html
    end
  end

  defp extract_chapter_title(html, href) do
    # Try h1, h2, h3 (skip <title> — often just the book title, not the chapter)
    for tag <- ["h1", "h2", "h3"], reduce: nil do
      nil ->
        case Regex.run(~r/<#{tag}[^>]*>(.*?)<\/#{tag}>/s, html) do
          [_, raw_title] ->
            clean = strip_html(raw_title)

            if clean != "" and String.length(clean) < @max_title_length,
              do: clean,
              else: nil

          _ ->
            nil
        end

      found ->
        found
    end
    |> case do
      nil ->
        # Fallback to filename
        href
        |> Path.basename()
        |> Path.rootname()
        |> String.replace(~r/[-_]/, " ")
        |> String.trim()
        |> then(fn name -> if name == "", do: "Untitled", else: name end)

      title ->
        title
    end
  end

  defp strip_html(html) do
    html
    |> String.replace(~r/<[^>]+>/, " ")
    |> String.replace(~r/&[^;]+;/, " ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp word_count(text) do
    text |> String.split(~r/\s+/, trim: true) |> length()
  end

  defp extract_tag(xml, tag) do
    case Regex.run(~r/<#{Regex.escape(tag)}[^>]*>(.*?)<\/#{Regex.escape(tag)}>/s, xml) do
      [_, value] -> String.trim(value)
      _ -> nil
    end
  end
end
