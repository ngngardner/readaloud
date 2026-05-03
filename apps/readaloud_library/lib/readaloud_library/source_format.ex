defmodule ReadaloudLibrary.SourceFormat do
  @moduledoc """
  The document format discriminator for imported sources. Single source of
  truth for the `Ecto.Enum` values shared by `ReadaloudLibrary.Book` and
  `ReadaloudImporter.ImportTask`, and for converting raw filename
  extensions into typed atoms at upload boundaries.

  `:import` is a legacy value for books pulled in chapter-by-chapter via
  ln-reader rather than from a single ebook file. ImportTask only ever
  writes `:epub` or `:pdf`; Book may carry `:import` from older rows.
  """

  @values [:epub, :pdf, :import]

  @type t :: :epub | :pdf | :import

  @doc "All format values, in `Ecto.Enum`-compatible order."
  def values, do: @values

  @doc """
  Casts a filename extension (e.g. `"epub"`, `".PDF"`) into a known file-format
  atom. Only `:epub` and `:pdf` are valid here — `:import` is a stored Book
  source, not an extension.

  Returns `{:ok, atom}` for recognized formats and `:error` otherwise. Use this
  at boundaries where untrusted strings (uploads, CLI args) need to become
  typed values before hitting the schema layer.
  """
  @spec cast_extension(String.t()) :: {:ok, :epub | :pdf} | :error
  def cast_extension(ext) when is_binary(ext) do
    normalized = ext |> String.trim_leading(".") |> String.downcase()

    case normalized do
      "epub" -> {:ok, :epub}
      "pdf" -> {:ok, :pdf}
      _ -> :error
    end
  end
end
