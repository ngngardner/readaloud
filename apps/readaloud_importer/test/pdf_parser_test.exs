defmodule ReadaloudImporter.PdfParserTest do
  use ExUnit.Case, async: true

  alias ReadaloudImporter.PdfParser

  describe "build_command/2" do
    test "constructs pdftotext command" do
      assert PdfParser.build_command("/tmp/test.pdf", "/tmp/output.txt") ==
               {"pdftotext", ["-layout", "/tmp/test.pdf", "/tmp/output.txt"]}
    end
  end

  describe "extract_chapters/1" do
    test "splits text by chapter headings" do
      text = """
      Chapter 1: The Beginning

      This is the first chapter content.

      Chapter 2: The Middle

      This is the second chapter.
      """

      chapters = PdfParser.extract_chapters(text)
      assert length(chapters) == 2
      assert Enum.at(chapters, 0).title == "Chapter 1: The Beginning"
      assert Enum.at(chapters, 1).title == "Chapter 2: The Middle"
    end

    test "handles CHAPTER uppercase headings" do
      text = "CHAPTER 1 Introduction\nSome text.\nCHAPTER 2 Methods\nMore text."
      chapters = PdfParser.extract_chapters(text)
      assert length(chapters) == 2
    end

    test "falls back to single chapter when no headings found" do
      text = "Some text without any chapter headings at all."
      chapters = PdfParser.extract_chapters(text)
      assert length(chapters) == 1
      assert Enum.at(chapters, 0).title == "Full Text"
    end

    test "counts words correctly" do
      text = "Chapter 1 Test\nOne two three four five."
      chapters = PdfParser.extract_chapters(text)
      assert Enum.at(chapters, 0).word_count == 5
    end
  end
end
