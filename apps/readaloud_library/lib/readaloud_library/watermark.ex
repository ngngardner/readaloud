defmodule ReadaloudLibrary.Watermark do
  @moduledoc """
  Strips scraper-site watermarks out of imported chapter HTML.

  Aggregator sites poison their text against scrapers by splicing ads into
  the prose ("read the latest chapters at <site>") spelled with homoglyphs —
  small capitals, mathematical alphanumerics, fullwidth forms, Cyrillic and
  Greek lookalikes. They read as words to a human eye but are unrelated code
  points, so they survive import and reach both the reader and the TTS
  provider, which dutifully sounds them out mid-sentence.

  Measured against the 2721 imported chapters of the worst offender in the
  library: 946 chapters carried at least one injection, spanning 481 distinct
  junk code points across ~30 Unicode blocks.

  ## Two injections, two remedies

  The naive fix — drop every whitespace token containing a junk code point —
  silently eats real prose, because the site uses homoglyphs two ways:

    * **Ad tokens.** Whole words spelled in junk (`ʀᴇᴀᴅ`, `ᴀＮO͍ÊṢ`). These are
      deleted.
    * **Substitution inside real words.** One or two code points swapped into
      ordinary prose (`сhoked` with a Cyrillic *с*), and domains glued
      straight onto the last word of a paragraph (`extinguished…f𝑟ee𝘸eb𝑛ovel.com`).
      Deleting the token would cost a real word, so these are *repaired*:
      homoglyphs are folded back to ASCII and only the domain is excised.

  The two are told apart by how much of the token is junk — an ad is mostly
  junk, a substitution is mostly prose. Hence `@ad_ratio` below.

  ## Scope guard

  The allowlist assumes Latin-script text. `strip/1` therefore no-ops on any
  document that is not predominantly Latin, so importing a chapter written in
  another script can never silently lose text.
  """

  # Latin-1 Supplement + Latin Extended-A cover the accents that show up in
  # real prose (café, déjà, ingénue). Everything past that — Latin Extended
  # Additional, phonetic small caps, math alphanumerics, other scripts — only
  # ever arrived here as a homoglyph. The rest of the class is typography an
  # EPUB legitimately carries: nbsp, middle dot, guillemets, dashes, curly
  # quotes, bullet, ellipsis.
  @allowed "\\x00-\\x7F\\x{A0}\\x{AB}\\x{B7}\\x{BB}\\x{C0}-\\x{17F}" <>
             "\\x{2013}\\x{2014}\\x{2018}\\x{2019}\\x{201C}\\x{201D}\\x{2022}\\x{2026}"

  @junk Regex.compile!("[^" <> @allowed <> "]", "u")

  # A domain is often glued straight onto the last word of a paragraph, with
  # no space between: `extinguished…f𝑟ee𝘸eb𝑛ovel.com`. Splitting the token at
  # the punctuation that ends the real sentence lets the prose half be kept
  # verbatim and the junk half be judged on its own. The prefix must end on a
  # non-alphanumeric so this can never cut a word in half.
  # The lookahead makes the prefix's final character allowed as well as
  # non-alphanumeric. Without it a junk *symbol* (℞ is a symbol, not a letter)
  # satisfies `[^\p{L}\p{N}]` and rides along in the half meant to be prose.
  @glued_split Regex.compile!(
                 "\\A([" <>
                   @allowed <>
                   "]*(?=[" <> @allowed <> "])[^\\p{L}\\p{N}])(.*[^" <> @allowed <> "].*)\\z",
                 "us"
               )

  # A token is a run of non-space characters, bounded by the tag delimiters so
  # a watermark butted against markup (`it.</p><p>ᴘᴀɴᴅᴀ`) can never take the
  # surrounding tags with it. Trailing horizontal space is part of the match,
  # so deleting a token closes the gap it leaves behind.
  @token ~r/[^\s<>]+[ \t]*/u

  @tag ~r/\A<[^>]*>\z/s

  @split_tags ~r/<[^>]*>/

  # `com|net|org|io` only. `me` and `co` produce false positives on ordinary
  # sentences ("...Me." ends a line of dialogue). The leading label keeps the
  # match off the real word in `terrifying.freewebnovel.com`.
  @domain ~r/[\p{L}\p{N}][\p{L}\p{N}\-_()|~]*\.(?:com|net|org|io)\b/iu

  # One watermark is a bare `.com` repeated as a whole paragraph.
  @domain_run ~r/(?:\.(?:com|net|org|io)\b){2,}/i

  # Appended directly to a real word, and entity-encoded in the stored HTML.
  @glued ~r/(?:&lt;|<)\.com(?:&gt;|>)/i

  # A token whose alphanumerics end in a TLD is a domain whose dot the site
  # replaced with junk punctuation (`lіghtnоvеlсаvе~c`om.`). Only applied to
  # tokens that carried a homoglyph, so `sitcom` is never at risk.
  @tld_tail ~r/(?:com|net|org|io)\z/i

  # A token at or above this share of junk is an ad, below it is prose that
  # was tampered with. Every measured ad token sits at 0.5 or higher; the
  # worst measured false positive (a domain glued to a real word) sits at 0.4.
  @ad_ratio 0.5

  @homoglyphs %{
    # Latin letter small capitals (phonetic extensions / IPA / Latin Ext-D)
    "ᴀ" => "a",
    "ʙ" => "b",
    "ᴄ" => "c",
    "ᴅ" => "d",
    "ᴇ" => "e",
    "ꜰ" => "f",
    "ɢ" => "g",
    "ʜ" => "h",
    "ɪ" => "i",
    "ᴊ" => "j",
    "ᴋ" => "k",
    "ʟ" => "l",
    "ᴍ" => "m",
    "ɴ" => "n",
    "ᴏ" => "o",
    "ᴘ" => "p",
    "ǫ" => "q",
    "ʀ" => "r",
    "ᴛ" => "t",
    "ᴜ" => "u",
    "ᴠ" => "v",
    "ᴡ" => "w",
    "ʏ" => "y",
    "ᴢ" => "z",
    # Latin Extended-B / IPA shapes
    "ƒ" => "f",
    "ƥ" => "p",
    "ɐ" => "a",
    "ɑ" => "a",
    "ɔ" => "o",
    "ɛ" => "e",
    "ɡ" => "g",
    "ɩ" => "i",
    "ʋ" => "v",
    "ʍ" => "w",
    "ʒ" => "z",
    # Cyrillic
    "а" => "a",
    "А" => "A",
    "в" => "b",
    "В" => "B",
    "с" => "c",
    "С" => "C",
    "ԁ" => "d",
    "е" => "e",
    "Е" => "E",
    "ё" => "e",
    "Ё" => "E",
    "ғ" => "f",
    "і" => "i",
    "І" => "I",
    "ј" => "j",
    "Ј" => "J",
    "к" => "k",
    "К" => "K",
    "м" => "m",
    "М" => "M",
    "н" => "h",
    "Н" => "H",
    "о" => "o",
    "О" => "O",
    "п" => "n",
    "П" => "N",
    "р" => "p",
    "Р" => "P",
    "ѕ" => "s",
    "Ѕ" => "S",
    "т" => "t",
    "Т" => "T",
    "у" => "y",
    "У" => "Y",
    "ѵ" => "v",
    "х" => "x",
    "Х" => "X",
    # Greek
    "α" => "a",
    "Α" => "A",
    "β" => "b",
    "Β" => "B",
    "γ" => "y",
    "δ" => "d",
    "ε" => "e",
    "Ε" => "E",
    "ζ" => "z",
    "Ζ" => "Z",
    "η" => "n",
    "Η" => "H",
    "θ" => "o",
    "ι" => "i",
    "Ι" => "I",
    "κ" => "k",
    "Κ" => "K",
    "λ" => "l",
    "μ" => "u",
    "Μ" => "M",
    "ν" => "v",
    "Ν" => "N",
    "ο" => "o",
    "Ο" => "O",
    "ρ" => "p",
    "Ρ" => "P",
    "σ" => "o",
    "τ" => "t",
    "Τ" => "T",
    "υ" => "u",
    "Υ" => "Y",
    "φ" => "f",
    "χ" => "x",
    "Χ" => "X",
    "ω" => "w",
    # Runic, Gothic, Armenian, currency and letterlike shapes. The site reaches
    # deep into Unicode for anything that renders like a Latin letter; these
    # are the ones it actually used, ordered by the letter they impersonate.
    "ᛒ" => "b",
    "𐌱" => "b",
    "฿" => "b",
    "₿" => "B",
    "Ꞗ" => "B",
    "Ɛ" => "E",
    "₦" => "N",
    "Ꞑ" => "N",
    "Ɲ" => "N",
    "𐌽" => "n",
    "℞" => "R",
    "℟" => "R",
    "Ꞧ" => "R",
    "Ɽ" => "R",
    "Ɍ" => "R",
    "𐍂" => "R",
    "ᚱ" => "r",
    "ɽ" => "r",
    "ꭆ" => "r",
    "г" => "r",
    "Ἀ" => "A",
    "₳" => "A",
    "ἁ" => "a",
    "Ȿ" => "S",
    "§" => "S",
    "𐌔" => "S",
    "Ꞩ" => "S",
    "ȿ" => "s",
    "ᶊ" => "s",
    "ʂ" => "s",
    "ꞩ" => "s",
    "Ꝋ" => "O",
    "Օ" => "O",
    "Ɵ" => "O",
    "∅" => "o",
    "ɵ" => "o",
    "ꝋ" => "o",
    "օ" => "o",
    # Digits and misc lookalikes
    "૦" => "o",
    "ℓ" => "l",
    "ǀ" => "l",
    # A dot lookalike, so an obfuscated domain still reads as one.
    "․" => "."
  }

  @doc """
  Removes scraper watermarks from a chapter's HTML, leaving markup intact.

  Returns the input unchanged when the document is not predominantly Latin
  (see the scope guard above) or when nothing matches.
  """
  @spec strip(String.t()) :: String.t()
  def strip(html) when is_binary(html) do
    if latin?(html), do: do_strip(html), else: html
  end

  defp do_strip(html) do
    # Ahead of the tag split: undecoded, `<.com>` is shaped exactly like a tag
    # and would be preserved as one.
    html
    |> String.replace(@glued, "")
    |> then(&Regex.split(@split_tags, &1, include_captures: true))
    |> Enum.map_join(fn part ->
      if Regex.match?(@tag, part), do: part, else: clean(part)
    end)
    |> String.replace(~r/[ \t]{2,}/, " ")
  end

  defp clean(text), do: Regex.replace(@token, text, fn match, _ -> token(match) end)

  defp token(match) do
    case Regex.run(@glued_split, match) do
      [_, prose, junk] -> prose <> token(junk)
      nil -> classify(match)
    end
  end

  defp classify(match) do
    junk = Regex.scan(@junk, match) |> length()

    cond do
      junk == 0 -> excise_domain(match)
      ad?(match, junk) -> ""
      true -> match |> fold() |> excise_domain() |> drop_tld_tail()
    end
  end

  # An ad is a token that is mostly junk. The `alnum == 1` arm catches the
  # lone-letter fragments an ad leaves behind (`ɴ`), which the ratio alone
  # would keep.
  defp ad?(match, junk) do
    alnum = junk + (Regex.scan(~r/[A-Za-z0-9]/, match) |> length())

    (junk >= 2 or alnum == 1) and junk / alnum >= @ad_ratio
  end

  defp fold(text), do: Regex.replace(@junk, text, fn char -> fold_char(char) end)

  defp fold_char(char) do
    case Map.fetch(@homoglyphs, char) do
      {:ok, ascii} -> ascii
      :error -> decompose(char)
    end
  end

  # Compatibility normalisation covers the algorithmic blocks — mathematical
  # alphanumerics, fullwidth forms, letterlike symbols. Canonical
  # decomposition then covers the accented shapes (Ṣ, ṃ) that Latin Extended
  # Additional supplies as lookalikes. Anything still unreadable is dropped.
  defp decompose(char) do
    nfkc = :unicode.characters_to_nfkc_binary(char)

    if ascii_alnum?(nfkc), do: nfkc, else: strip_marks(char)
  end

  defp strip_marks(char) do
    bare =
      char
      |> :unicode.characters_to_nfd_binary()
      |> String.replace(~r/\p{Mn}/u, "")

    cond do
      ascii_alnum?(bare) -> bare
      # An accented homoglyph (Greek alpha with tonos, say) is a homoglyph
      # once its marks are gone.
      Map.has_key?(@homoglyphs, bare) -> Map.fetch!(@homoglyphs, bare)
      true -> ""
    end
  end

  defp ascii_alnum?(binary), do: binary != "" and Regex.match?(~r/\A[A-Za-z0-9]+\z/, binary)

  defp excise_domain(text) do
    text
    |> String.replace(@domain_run, "")
    |> String.replace(@domain, "")
  end

  defp drop_tld_tail(text) do
    alnum = String.replace(text, ~r/[^A-Za-z0-9]/, "")
    if Regex.match?(@tld_tail, alnum), do: "", else: text
  end

  # Cheap script check: English prose spliced with homoglyphs still carries a
  # healthy share of plain a-z, while a chapter genuinely written in another
  # script carries almost none.
  defp latin?(html) do
    {latin, other} =
      for <<cp::utf8 <- html>>, reduce: {0, 0} do
        {latin, other} when cp in ?a..?z or cp in ?A..?Z -> {latin + 1, other}
        {latin, other} when cp > 127 -> {latin, other + 1}
        acc -> acc
      end

    latin * 2 >= other
  end
end
