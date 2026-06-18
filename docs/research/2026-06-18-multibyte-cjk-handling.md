# Multibyte / CJK (Hangul) character handling — pitfalls & best practices

Date: 2026-06-18
Method: deep-research harness. ⚠️ **The adversarial verification phase was fully RATE-LIMITED**
(Anthropic server temporary limit from running 3 research workflows back-to-back), so all 25 claims
came back "0-0 abstain" = unverified, NOT refuted. The underlying SOURCES are top-tier (Apple docs,
Mozilla Bugzilla, openradar, Unicode.org, kitty, Markus Kuhn's wcwidth, research.swtch.com), so treat
these as HIGH-QUALITY LEADS to confirm, not established facts. Run ID `wf_7a30276f-438`.

## The units, pinned down
- **IMK / NSTextInputClient ranges are UTF-16 code units** (NSString units): `setMarkedText`,
  `insertText`, `markedRange`, `selectedRange`, `attributedSubstring` all take/return `NSRange`
  ({location,length} in UTF-16). → A tracked `directRange` MUST be kept in UTF-16 units; mixing Swift
  `String.count` (grapheme clusters) or UTF-8 byte offsets causes off-by-N drift.
  (Source: IMKTextInput-Protocol.h)
- **PTY/terminal = UTF-8 bytes; libhangul = Unicode scalars/jamo; Swift String = graphemes.** Every
  boundary between these needs an explicit unit conversion.

## 🔴 Two findings that directly explain our bugs

### A. The `replacementRange` reference frame is genuinely ambiguous — Apple's docs are WRONG
- Apple docs say `replacementRange` is "relative to the marked text."
- **Mozilla (Firefox bug 875674) found it's actually a range into the FULL text storage**
  (document-absolute), and had to correct against Apple's sample code.
- → If bomi computes `replacementRange`/`directRange` in the wrong reference frame, that is a prime
  suspect for the inline directRange drift / last-syllable duplication. **Action: verify which frame
  bomi's inline path uses.**

### B. IMK's `selectedRange` can return BOGUS values during CJK composition
- openradar **FB13789916**: for Pinyin on macOS 14, the `selectedRange` location jumps 16→11 with no
  valid reason while typing marked CJK text.
- → "directRange drift" is partly an **Apple IMK bug**, not only ours. **Implication for hardening:**
  a "validate-or-bail by reconciling against `selectedRange()`" strategy is itself unreliable because
  the reconciliation source can lie. Prefer committing the existing composition when the range looks
  inconsistent (Mozilla's pattern) over trusting a queried range.
- Mozilla's concrete pattern: when `replacementRange` differs from the current marked range, COMMIT the
  existing composition with the latest string BEFORE applying the new range.

## 🟡 Terminal visual-duplicate / garble mechanisms (NFC vs NFD + cells)
- Precomposed Hangul (NFC, U+AC00–U+D7A3) = **2 terminal cells** (`wcwidth` = 2). Decomposed conjoining
  jamo (NFD) compute DIFFERENT widths: initial U+1100–115F = width 2, medial/final U+1160–11FF = width 0.
- **kitty #8433: Hangul conjoining jamo (U+1100–11FF) have NO Unicode combining class** → terminals that
  merge glyphs by combining-class FAIL to combine decomposed jamo into one syllable cell, rendering each
  jamo in its own cell + extra blank cells (a 3-jamo syllable spans 3 cells).
- → **Strong hypothesis for the Apple Terminal "duplicate last syllable" visual artifact:** if bomi's
  MARKED (composing) text is emitted as NFD conjoining jamo, the terminal mis-cells it, and on commit
  (NFC precomposed) the cell layout shifts → a duplicate-looking ghost. **Action: check whether bomi's
  marked + commit strings are NFC precomposed syllables or NFD jamo.** libhangul's commit string is
  typically NFC; verify the *preedit* path too. Emitting NFC everywhere is the terminal-safe choice.

## UTF-8 byte-slicing (the BCT preedit "?<0095><009c>긐" garble)
- UTF-8 is self-synchronizing: continuation bytes are `10xxxxxx` (0x80–0xBF); lead bytes encode length.
  Hangul precomposed = 3-byte (`1110xxxx`-led). **Byte-truncating a Hangul sequence** surfaces stray
  continuation bytes as the C1/replacement garbage seen in BCT. Fix belongs in the renderer: slice on
  codepoint/grapheme boundaries (skip continuation bytes), never on a byte count. (This was a BCT-side
  render bug, not bomi.)

## insertText can be an NSAttributedString
- `insertText:replacementRange:` may receive an `NSAttributedString`, not just `NSString`; calling a
  string-only selector (`UTF8String`) on it crashes (Flutter PR 176329). Type-check and pull `.string`
  first. (Relevant to any client-side or test-harness handling.)

## Key sources
- IMKTextInput-Protocol.h (range unit = UTF-16): https://github.com/w0lfschild/macOS_headers/blob/master/macOS/Frameworks/InputMethodKit/365.16.13/IMKTextInput-Protocol.h
- setMarkedText docs: https://developer.apple.com/documentation/appkit/nstextinputclient/setmarkedtext(_:selectedrange:replacementrange:)
- Firefox bug 875674 (replacementRange frame correction): https://bugzilla.mozilla.org/show_bug.cgi?id=875674
- openradar FB13789916 (bogus selectedRange for CJK): https://openradar.appspot.com/FB13789916
- kitty #8433 (Hangul jamo no combining class → extra cells): https://github.com/kovidgoyal/kitty/issues/8433
- wcwidth (East Asian Width): https://www.cl.cam.ac.uk/~mgk25/ucs/wcwidth.c , https://github.com/jquast/wcwidth
- UTF-8 self-sync: https://research.swtch.com/utf8 , https://www.cl.cam.ac.uk/~mgk25/unicode.html
- Unicode normalization / Korean FAQ: https://www.unicode.org/standard/reports/tr15/ , https://www.unicode.org/faq/korean
- NFD/NFC on Apple filesystems: https://eclecticlight.co/2021/05/08/explainer-unicode-normalization-and-apfs/

## Next concrete check for bomi
Verify the normalization form of bomi's marked (preedit) AND commit strings (NFC precomposed vs NFD
jamo). If anything emits NFD jamo, normalize to NFC — likely the real fix for the Terminal visual
duplicate, and harmless elsewhere.
