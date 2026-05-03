defmodule ReadaloudLibrary.SourceFormat do
  @moduledoc """
  The document format discriminator for imported sources. Single source of
  truth for the `Ecto.Enum` values shared by `ReadaloudLibrary.Book` and
  `ReadaloudImporter.ImportTask`, and for converting raw filename
  extensions into typed atoms at upload boundaries.
  """

  @values [:epub, :pdf]

  @type t :: :epub | :pdf

  @doc "All format values, in `Ecto.Enum`-compatible order."
  def values, do: @values

  @doc """
  Casts a filename extension (e.g. `"epub"`, `".PDF"`) into a known format atom.

  Returns `{:ok, atom}` for recognized formats and `:error` otherwise. Use this
  at boundaries where untrusted strings (uploads, CLI args) need to become
  typed values before hitting the schema layer.
  """
  @spec cast_extension(String.t()) :: {:ok, t()} | :error
  def cast_extension(ext) when is_binary(ext) do
    normalized = ext |> String.trim_leading(".") |> String.downcase()

    Enum.find_value(@values, :error, fn value ->
      if Atom.to_string(value) == normalized, do: {:ok, value}
    end)
  end
end
