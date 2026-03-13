defmodule ReadaloudImporter.CoverResolver do
  @moduledoc "Resolves cover images for books via extraction or external APIs."

  def storage_path, do: System.get_env("STORAGE_PATH", "priv/static/files")

  def covers_dir, do: Path.join(storage_path(), "covers")

  def cover_path(book_id), do: Path.join(covers_dir(), "#{book_id}.jpg")

  @min_cover_bytes 1_000

  @doc "Save raw cover bytes for a book. Returns {:ok, path} or {:error, reason}."
  def save_cover(book_id, image_bytes)
      when is_binary(image_bytes) and byte_size(image_bytes) >= @min_cover_bytes do
    path = cover_path(book_id)
    File.mkdir_p!(covers_dir())

    case File.write(path, image_bytes) do
      :ok -> {:ok, path}
      {:error, reason} -> {:error, reason}
    end
  end

  def save_cover(_book_id, _image_bytes), do: {:error, :image_too_small}

  @doc "Generate a deterministic gradient CSS string from a title hash."
  def gradient_placeholder(title) do
    hash = :erlang.phash2(title, 360)
    h1 = hash
    h2 = rem(hash + 120, 360)
    "background: linear-gradient(145deg, oklch(30% 0.15 #{h1}), oklch(15% 0.10 #{h2}))"
  end

  @doc "Fetch cover from Open Library by title and author. Returns {:ok, image_bytes} or {:error, reason}."
  def fetch_from_open_library(title, author) do
    query = URI.encode_query(%{title: title, author: author || "", limit: "1", fields: "cover_i"})
    search_url = "https://openlibrary.org/search.json?#{query}"

    with {:ok, %{status: 200, body: body}} <- Req.get(search_url, receive_timeout: 10_000),
         [%{"cover_i" => cover_id} | _] when is_integer(cover_id) <- body["docs"] do
      fetch_cover_image(cover_id)
    else
      _ -> {:error, :no_cover_found}
    end
  end

  defp fetch_cover_image(cover_id) do
    Enum.find_value(["L", "M"], {:error, :cover_download_failed}, fn size ->
      url = "https://covers.openlibrary.org/b/id/#{cover_id}-#{size}.jpg"

      case Req.get(url, receive_timeout: 10_000, redirect: true) do
        {:ok, %{status: 200, body: bytes}}
        when is_binary(bytes) and byte_size(bytes) >= @min_cover_bytes ->
          {:ok, bytes}

        _ ->
          nil
      end
    end)
  end
end
