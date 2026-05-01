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

  describe "parse_outline_entries/1" do
    test "parses pdftohtml outline section into title/page entries" do
      html = """
      <html><body>
      <a name="outline"></a><h1>Document Outline</h1>
      <ul>
      <li><a href="docs.html#7">INTRODUCTION</a></li>
      <li><a href="docs.html#10">Chapter One: Aspects of Wholeness</a></li>
      <li><a href="docs.html#33">Chapter Two: Another View of Evolution</a></li>
      </ul>
      </body></html>
      """

      entries = PdfParser.parse_outline_entries(html)
      assert length(entries) == 3
      assert Enum.at(entries, 0) == %{title: "INTRODUCTION", page: 7}
      assert Enum.at(entries, 1).title == "Chapter One: Aspects of Wholeness"
      assert Enum.at(entries, 1).page == 10
      assert Enum.at(entries, 2).page == 33
    end

    test "decodes HTML entities in titles" do
      html = """
      <a name="outline"></a><h1>Document Outline</h1>
      <ul>
      <li><a href="docs.html#5">Vernadsky&#39;s &amp; Holistic Science</a></li>
      </ul>
      """

      [entry] = PdfParser.parse_outline_entries(html)
      assert entry.title == "Vernadsky's & Holistic Science"
    end

    test "returns empty list when no outline section present" do
      assert PdfParser.parse_outline_entries("<html><body>no outline here</body></html>") == []
    end
  end
end
