defmodule ReadaloudLibrary.WatermarkTest do
  use ExUnit.Case, async: true

  alias ReadaloudLibrary.Watermark

  describe "strip/1 leaves real text alone" do
    test "ordinary prose and its markup are untouched" do
      html = "<p>He opened the door — slowly, deliberately…</p>"
      assert Watermark.strip(html) == html
    end

    test "accented words that belong to real prose survive" do
      html = "<p>A café, déjà vu, his fiancé, an ingénue, worn clichés.</p>"
      assert Watermark.strip(html) == html
    end

    test "a sentence ending in .me or .co is not read as a domain" do
      html = "<p>\"...Me. Not you.\" The choice was his.co</p>"
      assert Watermark.strip(html) == html
    end

    test "nothing is stripped inside a tag" do
      html = ~s(<a href="http://novel-bin.com/x" class="ᴀ">text</a>)
      assert Watermark.strip(html) == html
    end

    test "a document that is not predominantly Latin is left as-is" do
      html = "<p>これは日本語の文章です。ここには透かしがありません。</p>"
      assert Watermark.strip(html) == html
    end
  end

  describe "strip/1 deletes ad tokens" do
    test "words spelled entirely in small capitals" do
      html = "<p>He opened the door. ʀᴇᴀᴅ ʟᴀᴛᴇsᴛ ᴄʜᴀᴘᴛᴇʀs ᴀᴛ ɴᴏᴠᴇʟ</p>"
      assert Watermark.strip(html) == "<p>He opened the door. </p>"
    end

    test "a word built from mixed junk blocks" do
      assert Watermark.strip("<p>Gone ᴀＮO͍ÊṢ now.</p>") == "<p>Gone now.</p>"
    end

    test "a junk token that opens with a symbol rather than a letter" do
      # ℞ is a symbol, so it satisfies "non-alphanumeric" and used to be
      # mistaken for the punctuation that ends a real sentence.
      assert Watermark.strip("<p>He waited. ℞Äℕò𝖇ЕS</p>") == "<p>He waited. </p>"
    end

    test "a lone leftover junk letter" do
      assert Watermark.strip("<p>Sunny waited. ɴ</p>") == "<p>Sunny waited. </p>"
    end

    test "an obfuscated domain standing on its own" do
      assert Watermark.strip("<p>Home. 𝚏r𝐞𝗲𝚠eb𝚗o𝐯el.com</p>") == "<p>Home. </p>"
    end

    test "an obfuscated domain whose dot was replaced with punctuation" do
      assert Watermark.strip("<p>Home. lіghtnоvеlсаvе~c`оm.</p>") == "<p>Home. </p>"
    end

    test "a paragraph of bare repeated TLDs" do
      assert Watermark.strip("<p>.com.com.com.com</p><p>There</p>") == "<p></p><p>There</p>"
    end

    test "bare domain tokens written in plain ASCII" do
      assert Watermark.strip("<p>Read on novel-bin.com now.</p>") == "<p>Read on now.</p>"
      assert Watermark.strip("<p>Read on n0velbin.NET now.</p>") == "<p>Read on now.</p>"
    end
  end

  describe "strip/1 repairs tampered prose" do
    test "a Cyrillic letter swapped into a real word is folded back" do
      # The c in "choked" and "clothes" is Cyrillic es.
      assert Watermark.strip("<p>He сhoked on his сlothes.</p>") ==
               "<p>He choked on his clothes.</p>"
    end

    test "two homoglyphs in a longer word are folded, not deleted" do
      # The e and a in "great" are Cyrillic.
      assert Watermark.strip("<p>It was a grеаt hall.</p>") == "<p>It was a great hall.</p>"
    end

    test "a dotted-below lookalike is folded back" do
      assert Watermark.strip("<p>The integraṃ held.</p>") == "<p>The integram held.</p>"
    end

    test "a domain glued onto a real word takes only the domain" do
      html = "<p>The fire was extinguished…𝚏𝑟e𝒆𝙬𝒆𝗯𝑛𝙤vel.𝘤o𝑚</p>"
      assert Watermark.strip(html) == "<p>The fire was extinguished…</p>"
    end

    test "a domain glued on after sentence punctuation keeps the sentence" do
      html = "<p>She counted the coins?𝑓𝑟e𝒆𝘄e𝗯𝒏𝙤v𝒆l.𝒄o𝑚</p><p>So,</p>"
      assert Watermark.strip(html) == "<p>She counted the coins?</p><p>So,</p>"
    end
  end

  describe "strip/1 housekeeping" do
    test "removes the <.com> marker glued onto a real word" do
      assert Watermark.strip("<p>He was scared.&lt;.com&gt;</p>") == "<p>He was scared.</p>"
      assert Watermark.strip("<p>He was scared.<.com></p>") == "<p>He was scared.</p>"
    end

    test "keeps surrounding markup when a watermark abuts a tag" do
      html = "<p>It ended.</p><p>ᴘᴀɴᴅᴀ The morning came.</p>"
      assert Watermark.strip(html) == "<p>It ended.</p><p>The morning came.</p>"
    end

    test "collapses the whitespace left behind by a removed token" do
      refute Watermark.strip("<p>One ᴛᴡᴏ three</p>") =~ "  "
    end

    test "is idempotent" do
      html = "<p>He opened the door. ʀᴇᴀᴅ ᴀᴛ freewebnovel.com</p>"
      once = Watermark.strip(html)
      assert Watermark.strip(once) == once
    end
  end
end
