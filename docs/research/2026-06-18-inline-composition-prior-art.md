# Inline (no-underline) IME composition — prior art & paradigms

Date: 2026-06-18
Method: deep-research harness (5 search angles, 21 sources fetched, 91 claims → 25 adversarially
verified, 20 confirmed / 5 killed). Run ID `wf_e017faaf-0cb`.

## Question

How do IMEs achieve inline, no-underline composition (composing text looks like already-committed
text, not underlined "marked text") reliably across apps, and is there a paradigm smarter than the
"insert real text + track a directRange + replace-in-place" approach we currently use — which drifts
and duplicates the last syllable on commit ("안녕"→"안녕녕") in some apps?

## Bottom line

There is **no free lunch**. Every approach shares one root limitation on macOS:

> **The "glaring hole" in `NSTextInputClient`** — there is no method for an IME to read the host
> document's length / full content / authoritative insertion point. (Rick Schaut, MS Word dev:
> https://learn.microsoft.com/en-us/archive/blogs/rick_schaut/the-glaring-hole-in-the-nstextinputclient-protocol)

So any technique that inserts real text and tracks where it went **cannot fully reconcile** against
the document, because it can't see the document. Windows TSF does not have this hole (the app owns the
composing text in its own `ITextStoreACP`, the underline is just an optional display attribute
`TF_LS_NONE`), but TSF is **not portable to macOS**. Note: the idea that TSF "auto-reconciles drift by
diffing a cached buffer" was **refuted (0-3)** — even TSF is not magic; it just puts the store on the
app side.

## Approaches compared

### 1. Insert real text + replace-in-place (what we / DKST do)
- **Direct prior art: `AlienKevin/hangeul_ime` "seamless mode"** does the exact same thing
  (`insertText(_:replacementRange:)`, range = `selectedRange.location - 1`).
  https://github.com/AlienKevin/hangeul_ime
- It is gated by a per-app **whitelist** (`_supportsTSM`), with **marked-text fallback** for
  Terminal / Notion / WhatsApp / LINE, plus cursor-move invalidation (`clean()` when the cursor
  location changes). This is the reconcile-or-bail family — **not a novel paradigm**.
- **No runtime capability query exists** to detect at runtime whether a client honors
  `replacementRange`; the author explicitly could not find one. → a hand-maintained whitelist is the
  state of the art. (Confirms: our blocklist→allowlist inversion idea matches real practice, but the
  detection itself stays heuristic.)

### 2. Synthetic backspace-and-retype (Vietnamese IMEs: OpenKey/Unikey/EVKey)
- Avoids marked text entirely: injects `CGEvent` key 51 (`kVK_Delete`) via `CGEventTapPostEvent`,
  then re-types. No underline because nothing is "marked".
  https://github.com/tuyenvm/OpenKey
- **Does NOT escape drift.** The backspace count is recomputed every keystroke from the engine
  buffer; apps that autocomplete/corrupt need per-app hacks (inject invisible U+202F / U+200C and
  bump the backspace count). Telex non-selection replacement can delete a whole word. Lost characters
  reported in JetBrains IDEs (Unikey/EVKey). Firefox needed a Gecko fix to dispatch composition
  events instead of keypress events (bug 1312649, fixed FF51/52).
- **Verdict: trades one failure set for another**, requires event-injection/Accessibility
  permission, and is fragile. Not recommended.

### 3. Windows TSF (comparison only)
- Composing text is real text in the app's own store under a `RequestLock`/`OnLockGranted` lock
  handshake; the underline is one optional IME-declared display attribute (`TF_LS_NONE` = no
  underline) that the **app** renders or omits. No-underline composition is first-class.
- Not portable. Documents why macOS is structurally harder.

## 🎯 The promising lead: marked-text WITHOUT the underline

A verified-refuted claim is the key: *"no-underline composition cannot be achieved through standard
`setMarkedText` alone / marked text must render a distinguishing underline"* was **refuted (0-3)**.

Combined with the open question the research surfaced:

> **Set `markedTextAttributes` to remove the underline (`NSUnderlineStyle` = none / 0) — keep using
> `setMarkedText` (framework-owned composition region, no directRange, structurally drift-free) but
> hide the underline.**

This is the genuinely simpler paradigm:
- The **OS owns** the composition range → we never track a `directRange` → **drift and the
  duplicate-last-syllable bug are structurally impossible**.
- We get inline's *appearance* (no underline) with marked's *stability*.
- It would let us **delete the entire directRange machinery** (classifyComposition / inlineReplaceRange
  / expectedCaret / learnedAppendOnly), not just harden it.

**Unverified risk (must test on-device):** whether apps (Terminal, Word, Slack, Chromium) actually
honor a no-underline marked attribute. Worst case for an app that ignores it = the underline simply
reappears — **no duplication**, so the failure mode is safe/cosmetic, not corrupting. This is cheap to
prototype: set the attribute and eyeball each app.

## Open questions (from the research)
1. Any private property to detect `replaceText`/`replacementRange` support at runtime (vs whitelist)?
   — hangeul_ime author couldn't find one.
2. Does transparent `markedTextAttributes` (underline 0) suppress the underline while keeping the
   framework-managed composition range — and do Terminal / Word / Slack honor it?
3. Can `AXUIElement` read document length + insertion point to partly close the "glaring hole" at
   acceptable per-keystroke latency? (Latency-sensitive here — see memory keystroke-hotpath-latency.)
4. Which app behavior actually triggers the duplication: ignoring `replacementRange` (append), or
   `selectedRange` not updating synchronously after `insertText`, or async autocomplete between keys?

## Connection to the 2026-06-18 Terminal dup
On-device diag logging showed the reported Terminal duplication happens in **marked mode** (the inline
path / `inlineBranch` never executed; Apple Terminal always classified `marked`). So the
marked-without-underline paradigm would **not** introduce that dup — but that marked-mode dup is a
**separate** bug still under investigation (keystroke-level diag) and must be root-caused regardless of
which composition paradigm we pick.

## Key sources
- AlienKevin/hangeul_ime (primary, our exact approach + whitelist): https://github.com/AlienKevin/hangeul_ime
- NSTextInputClient.insertText (primary): https://developer.apple.com/documentation/appkit/nstextinputclient/1438258-inserttext
- setMarkedText (primary): https://developer.apple.com/documentation/appkit/nstextinputclient/setmarkedtext(_:selectedrange:replacementrange:)
- "Glaring hole in NSTextInputClient" — Rick Schaut (primary): https://learn.microsoft.com/en-us/archive/blogs/rick_schaut/the-glaring-hole-in-the-nstextinputclient-protocol
- OpenKey (primary, Vietnamese backspace synthesis): https://github.com/tuyenvm/OpenKey
- Firefox Gecko Vietnamese IME fix (primary): https://bugzilla.mozilla.org/show_bug.cgi?id=1312649
- TSF document locks / display attributes (primary): https://learn.microsoft.com/en-us/windows/win32/tsf/document-locks ,
  https://learn.microsoft.com/en-us/windows/win32/api/msctf/ne-msctf-tf_da_linestyle
- kitty marked-text + event suppression (primary): https://github.com/kovidgoyal/kitty/pull/1586
- Firefox IME handling guide (primary): https://firefox-source-docs.mozilla.org/editor/IMEHandlingGuide.html

## Refuted (do NOT rely on these)
- "Apple warns insertText is off-label for non-user text" → refuted 0-3.
- "marked text must be rendered underlined / no-underline impossible via setMarkedText" → refuted 0-3
  (this is what opens the markedTextAttributes lead).
- "TSF auto-reconciles drift via cached-buffer diff" → refuted 0-3.
- "OpenKey uses Shift+Left selection-replace for Chromium" → unverified (1-2).
