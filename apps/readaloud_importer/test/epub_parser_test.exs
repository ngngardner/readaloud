defmodule ReadaloudImporter.EpubParserTest do
  use ExUnit.Case, async: true

  alias ReadaloudImporter.EpubParser

  describe "build_command/2" do
    test "constructs ebook-convert command" do
      assert EpubParser.build_command("/tmp/test.epub", "/tmp/output") ==
               {"ebook-convert", ["/tmp/test.epub", "/tmp/output/book.htmlz"]}
    end
  end

  describe "extract_chapters/1" do
    test "splits HTML content into chapters by heading tags" do
      html = "<h1>Chapter 1</h1><p>First chapter content.</p><h1>Chapter 2</h1><p>Second chapter content.</p>"
      chapters = EpubParser.extract_chapters(html)
      assert length(chapters) == 2
      assert Enum.at(chapters, 0).title == "Chapter 1"
      assert Enum.at(chapters, 0).number == 1
      assert Enum.at(chapters, 1).title == "Chapter 2"
      assert Enum.at(chapters, 1).number == 2
    end

    test "handles h2 headings" do
      html = "<h2>Part One</h2><p>Content here.</p><h2>Part Two</h2><p>More content.</p>"
      chapters = EpubParser.extract_chapters(html)
      assert length(chapters) == 2
      assert Enum.at(chapters, 0).title == "Part One"
    end

    test "counts words excluding HTML tags" do
      html = "<h1>Chapter 1</h1><p>One <b>two</b> three four five.</p>"
      chapters = EpubParser.extract_chapters(html)
      assert Enum.at(chapters, 0).word_count == 5
    end
  end
end
