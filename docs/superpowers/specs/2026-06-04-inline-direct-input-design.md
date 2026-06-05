# Inline direct-input (no-underline composition) — design

Date: 2026-06-04. Target: bomi-input (macOS IME, libhangul + InputMethodKit).
Status: P1 (core) + P2 (engines + config) + P3 **UI** implemented (2026-06-05), behind the
default-FALSE `inlineCompositionEnabled` kill-switch. P3 hot-path hardening (first-roman-leak
repair, eager-sync) intentionally deferred — see the P3 note below.

## Goal

Add DKST-style **inline direct-input**: while composing Korean, insert the
composing text directly into the document (real text, no marked-text underline),
replacing it in place as composition evolves — instead of the current IMKit
marked-text (underlined) composition. Falls back to marked text where inline is
unsafe. User-facing result: typing Korean reads as native, underline-free text in
apps that support it.

Scope chosen by user: **full DKST-style** — inline by default, per-app-engine
detection (WebKit/Chromium), plus a user "force marked text" blocklist and a
global "always marked text" toggle.

## Background

### bomi current composition mechanism
- `InputController.updateComposition()` (OSXCore/InputController.swift:255) calls
  `super.updateComposition()`, which is IMKInputController's default: it queries
  `composedString()` (:271 → `receiver.composedString` → `composer.composedString`)
  and renders it as **marked text** (underline) on the client.
- Commit: `InputReceiver.commitCompositionEvent` (InputReceiver.swift:152) →
  `controller.client().insertText(commitString, replacementRange)`.
- The composer (`GureumComposer`/`HangulComposer`, libhangul-backed) separates
  `commitString` (finalized) from `composedString` (in-progress syllable).

### Reference: DKST (DINKIssTyle-IME-macOS)
- **MIT-licensed** → logic is portable into bomi (BSD) with attribution.
- Pure Objective-C, own Hangul engine. Inline engine lives in
  `Sources/InputController.m` (~2,265 LOC). Key pieces ported below:
  - `shouldUseMarkedTextForClient:` (:840) — per-client decision chain.
  - `_directInputComposedText/Length/Range` — tracking of the directly-inserted
    composing text.
  - `directInputRangeIsCurrent:` (:558) / `directInputReplacementRange:` (:597) —
    validate the inserted text is still present (via `attributedSubstringFromRange:`)
    before replacing; recover stale ranges.
  - `bundleIdentifierUsesWebKitTextStack:` (:401),
    `bundleIdentifierUsesChromiumMarkedTextPolicy:` (:430),
    `runningApplicationUsesChromiumTextStack:` (framework scan).
  - `repairFirstMarkedTextLeakForClient:` (:954), `syncInputClient:force:` (:1010),
    `resetCompositionState` (:1033) — edge-case handling (Phase 3).

## Architecture

### A. Composition policy decision (per client)
On composition start (or client change), compute `useMarkedText: Bool` once,
priority order (ported from DKST `shouldUseMarkedTextForClient:`):
1. Global setting "always marked text" → marked.
2. **Apple private API `showsComposingTextAsMarkedText`** — query the IMK
   `textDocument` proxy (KVC/`performSelector`), fallback to the sender. Most
   reliable signal of whether the client wants marked text.
3. User **force-marked-text Bundle ID list** contains the client → marked.
4. WebKit text stack (Safari/`com.apple.WebKit.*`) → **inline**.
5. Chromium text stack (Chrome/Edge/Brave/Whale/Arc/Opera/Vivaldi/Comet/Atlas/
   Electron; bundle-prefix list + `.app` framework scan cache) → marked.
6. `selectedRange` not queryable / `NSNotFound` → marked (safe).
7. Default → **inline**.

Implemented as a **pure, unit-testable** function over an injectable
client-capabilities abstraction (so the bundle-ID/engine logic is tested without a
live IMK client). Side-effecting queries (`showsComposingTextAsMarkedText`,
`selectedRange`) are wrapped behind that abstraction.

### B. Inline render mechanism
Track `directInputComposed: (text: String, range: NSRange)?` per controller.

- **`updateComposition()`**: if `useMarkedText`, keep `super.updateComposition()`
  (existing marked path). If inline:
  - Compute `replacementRange` via the DKST `directInputReplacementRange` logic
    (validate current range, or backtrack from `selectedRange`, else drop stale).
  - `client.insertText(composedString, replacementRange: replacementRange)`.
  - Update `directInputComposed = (composedString, NSRange(location: start,
    length: composedString.utf16Count))`.
- **Commit**: in inline mode the composing text is already in the document.
  Map bomi's `commitString`/`composedString` split (see Integration challenge):
  the committed prefix becomes permanent (drop it from the tracked range), the new
  composing remainder continues inline. Do NOT re-`insertText` the whole commit.
- **Cancel/backspace**: replace the tracked range with the reduced/empty text.

### C. State management
- Reset `directInputComposed` on client deactivation, mode change, and explicit
  cancel (port `resetCompositionState`).
- `directInputRangeIsCurrent`: before any replace, verify
  `attributedSubstringFromRange(range).string == directInputComposed.text`; if not,
  recover (recompute from `selectedRange`) or drop to a clean state.

## Integration challenge (highest risk)

bomi is libhangul-based with a `commitString` vs `composedString` split; DKST uses
its own engine with a single direct-input buffer. The port must map bomi's
"finalized commit string + in-progress composed string" onto one contiguous
directInput range that is replaced in place. The tricky transitions:
- syllable boundary (e.g. typing ㄴ after 안 → commit "안", start "녀"): the
  committed "안" must become permanent text and the inline range must shift to the
  new "녀".
- This sits in the **input hot-path** (the area just fixed for the rebrand input
  bug), so regression risk is real → marked-text fallback must be the safe default
  and inline must be a strictly additive branch.

## Settings / config

Add to `Configuration` (OSXCore/Configuration.swift):
- `inlineCompositionAlwaysMarked: Bool` (default false) — global "always marked".
- `inlineCompositionForcedMarkedBundleIDs: [String]` (default []) — user blocklist.
- `inlineCompositionEnabled: Bool` — master gate / kill-switch, distinct from the
  per-app policy. Default **false** through P1–P2 dogfooding (inline only when
  explicitly enabled); flipped to **true** once the on-device matrix passes. When
  false, behaviour is exactly today's marked-text path.

UI deferred to Phase 3 (defaults-key driven first). The Preferences pane
(Configuration.storyboard / GureumPreferences target) gets the blocklist editor and
toggles later.

## Safety / fallback

- Every uncertain branch defaults to marked text → worst case equals current
  behavior. Inline is purely additive.
- `inlineCompositionEnabled` master default lets us dogfood before exposing.
- All IMK queries wrapped in try/guard (Swift can't @catch ObjC exceptions from all
  APIs — use respondsToSelector guards + optional casts; for the private API use
  `perform`/KVC defensively).

## Testing

- **Unit**: the pure policy function (`classifyComposition`) over a stub client
  exercising each priority branch (global, showsMarked, blocklist, WebKit, Chromium,
  no-selectedRange, default). Target OSXCoreTests.
- **Manual matrix** (on-device, the only way to validate real clients): 메모/TextEdit,
  Slack, Mail, Notion, Xcode, VS Code (Electron→marked), Safari (WebKit→inline),
  Chrome (Chromium→marked), Terminal/iTerm. Record per-app inline/marked + correctness.
- bomi build/sign/install per CLAUDE.md; the existing 45-test suite must stay green.

## Implementation phases

- **P1 (core)** — DONE (ecd254f): policy decision function (+ unit tests) for native
  Cocoa (showsComposingTextAsMarkedText + selectedRange + default), inline render at
  `updateComposition`, commit/compose mapping, marked-text fallback, master default.
- **P2 (engines + config)** — DONE (2026-06-05): WebKit/Chromium detection (+ framework
  scan cache), user force-marked blocklist defaults-key, global always-marked toggle.
  Pure bundle-ID classifiers (`bundleIdentifierUsesWebKitTextStack` / `…ChromiumMarkedTextPolicy`
  / `…MatchesForcedMarkedList`) + the framework scan behind `LiveClientCapabilities`
  (`usesChromiumFrameworkTextStack`, cached by bundle ID). Config key
  `inlineCompositionForcedMarkedBundleIDs`. classifyComposition chain steps 3–5 wired.
  Unit tests cover every branch (OSXTests 65/1-baseline). Defaults-key driven; UI still P3.
- **P3 (edges + UI)** — UI DONE (2026-06-05); hot-path hardening DEFERRED by decision.
  - **Done — Preferences UI**: the in-app settings pane (Preferences/PreferenceViewController.swift)
    gained an "인라인 직접 입력 (실험적)" section, built PROGRAMMATICALLY and appended to the settings
    stack view via a single new xib outlet (`inlineSettingsStackView` → `kLe-bm-FOO`) — no fragile
    control XML added to Preferences.xib. Controls: master enable (`inlineCompositionEnabled`),
    global always-marked (`inlineCompositionAlwaysMarked`), and a newline-separated bundle-ID editor
    (NSTextView) for `inlineCompositionForcedMarkedBundleIDs`. Editor text↔[String] normalization
    (`parseForcedMarkedBundleIDList`/`formatForcedMarkedBundleIDList`) lives in Configuration.swift
    (NOT InlineComposition.swift) because the legacy prefpane target (USE_PREFPANE) compiles a subset
    of OSXCore in-module that includes Configuration.swift but not InlineComposition.swift. Unit-tested.
  - **Deferred — hot-path hardening** (first-roman-leak repair, eager-sync avoidance, extra reset
    hardening): DKST's `repairFirstMarkedTextLeakForClient:`/`syncInputClient:force:`/`resetCompositionState`
    are tied to DKST's own engine and are SPECULATIVE for bomi (libhangul + IMKit) — the leak/eager-sync
    problems may not even manifest. Porting them would touch the input hot-path (the rebrand-bug area)
    for problems unconfirmed on-device. Decision: enable inline (now possible via the UI), dogfood, and
    only port these if real on-device problems appear. P1 already handles the reset cases its tests cover.

- **Dogfood fix — terminals → marked** (2026-06-05): first on-device dogfooding (BCT, the user's native
  Rust/winit terminal `com.yoropico.bct`) showed inline duplicates the LAST WORD on commit (space/enter):
  terminals expect the standard marked-text composition flow, and inline-inserting the composing text then
  committing re-emits it. Root cause = inline is incompatible with terminals. Fix: new pure classifier
  `bundleIdentifierUsesTerminalTextStack` (BCT + Terminal.app/iTerm2/Ghostty/kitty/Alacritty/WezTerm/Warp/
  Hyper) + a classifyComposition step 6 (terminal → marked). Verified on-device: duplication gone.
  NOTE: BCT then showed garbled preedit (`?<0095><009c>…`) in MARKED mode — that is a BCT-side preedit
  RENDER bug (byte- vs char-slicing of the winit `Ime::Preedit` string; commit path writes bytes to the PTY
  and is fine), NOT a bomi bug (bomi's marked path is standard and works in every other app). Fix belongs in
  claude-terminal (`src/app/event_loop/ime.rs` + its preedit renderer), out of scope for bomi.

## STATUS 2026-06-05 — inline DISABLED by user; needs fundamental hardening before re-enable

On-device dogfooding surfaced a cascade of inline failures, all with ONE root cause:
**the IME's tracked `directRange` drifts out of sync with the real document** (cursor moved,
commit boundary, non-standard text engine) → it then appends / operates on the wrong location.
Observed: commit dup "안녕"→"안녕녕" (Finder + all apps); Word cursor-jump on move-then-delete
(stale directRange); terminals (PTY can't replace); Word custom text engine. The user turned
inline OFF (`InlineCompositionEnabled=false`) → back to the years-stable marked path.

Partial fixes landed: terminals→marked (`33a2be2`, pushed); commit-path directRange-preserve
(`2e9cea1`, local — fixes ONE append path but Finder still dup'd via the delete/validate gap, and
inline is now off so it's dormant).

**Fundamental fix (required before re-enabling) — the deferred robustness layer DKST spends ~2,265 LOC on:**
1. **validate-or-bail on EVERY inline op** (insert / commit / backspace): before any replace, confirm
   `directRange` still holds the expected text via `attributedSubstring`; else recover from
   `selectedRange`, else FALL BACK to marked — never blindly append. (bomi has `directRangeIsCurrent`
   but not on all paths; the delete/backspace path doesn't validate at all.)
2. **cursor-move invalidation**: remember last `selectedRange`; if the cursor moved unexpectedly
   (arrows/click) between inputs, drop `directRange`. (DKST `rememberSelectedRangeForClient` +
   `resetCompositionState` — the deferred P3 hardening; fixes Word move-then-delete jump.)
3. **capability gate, NOT a hand-maintained blocklist**: prove the client actually honours an inline
   replace, else fall back to marked — auto-handling Word/terminals/non-standard apps. The MECHANISM is
   resolved in the PHASE 2 section below: a static seed list (known append-only apps → marked from
   keystroke 1) plus NON-INVASIVE post-write learning (validate the first real replace landed via caret
   check; on violation, demote the client to marked and remember it). The invasive composition-start
   probe once sketched here is REJECTED — see PHASE 2 for why.

Realistic recommendation: ③(strong capability gate) + ①(validate-or-bail) is the highest-leverage,
lowest-risk path; ② on top. Residual app-compat risk always remains (why DKST keeps a big override
list) — so also weigh whether inline's underline-free aesthetic is worth the perpetual compat tax vs
just shipping the rock-solid marked default.

### PHASE 1 (done — shipped behind kill-switch, inline currently OFF)
- ① fail-safe **DONE** (`3e3bee6`, verified on-device in Finder): in renderInline, when a tracked
  directRange can't be located at commit (validation+backtrack fail) AND composedString is empty, skip
  the append (combined is already-inline text) → commit duplication structurally impossible on that path.
  Earlier `2e9cea1` preserved directRange into renderInline (cancelCompositionEvent vs cancelComposition)
  and fixed a MockInputController.cancelComposition infidelity that hid the bug.
- terminals→marked (`33a2be2`) + Chromium/WebKit (P2) already in.
- KNOWN-OPEN, deferred to phase 2: **MS Word** still dups — its engine PASSES attributedSubstring
  validation but IGNORES insertText's replacementRange (appends), so ① (which only triggers on validation
  FAILURE) can't catch it; ② (cursor-move invalidation) not implemented; ③ not implemented.

### PHASE 2 (next — capability gate done right, NON-INVASIVE; design 2026-06-05)

**Decision (2026-06-05): the invasive pre-composition probe is REJECTED.** Inserting + reading back +
deleting a probe char before showing any composition writes a synthetic char into the user's document at
composition start, which (a) replaces and destroys an active selection = data loss, (b) fires
onChange/onInput in reactive fields (web/Electron chat, search, React controlled inputs) — side effects
the later delete cannot undo, (c) pollutes undo history and risks a first-keystroke flicker. Clean repair
in a true append-only app is impossible anyway (it ignores insertText's replacementRange, so it ignores
the cleanup delete too), so an invasive probe buys risk without buying guaranteed cleanliness.

**Chosen approach — NON-INVASIVE post-write validation + a static seed list (two-layer defense).**
This subsumes ③ (capability gate) as post-hoc LEARNING rather than upfront classification, and extends
① (validate-or-bail), which already lives in renderInline.

- **A. Seed list (static, pure, first-line defense).** New pure classifier
  `bundleIdentifierUsesAppendOnlyTextStack` (InlineComposition.swift), wired into `classifyComposition`
  (after the terminal step, before the default → inline). Known apps that ignore insertText's
  replacementRange → marked from keystroke 1 → ZERO artifact. Seed candidates (verify real bundle IDs
  on-device): `com.microsoft.Word`/`Excel`/`Powerpoint`/`Outlook`/`onenote.mac`, Hancom 한글
  (`com.hancom.*` / `com.haansoft.hwp`). This is what actually guarantees correctness for the apps users
  hit.
- **B. Runtime learning (safety net for UNKNOWN append-only apps).** In `renderInline`, ONLY after an
  insert with a real (non-NSNotFound) replaceRange — i.e. the first replace of a composition, the
  keystroke that exposes append-vs-replace — validate by **caret landing**: expected caret =
  `replaceRange.location + combined.utf16len`; if `selectedRange().location` differs (an append-only app
  leaves the old glyph and appends, so the caret is further right) → VIOLATION. On violation: clear
  `directRange`/`directText`, set `controller.useMarkedText = true` (this session), record the bundle ID
  in a per-bundle learned-append cache (static, session-scoped, same pattern as `chromiumDetectionCache`)
  so future activations classify it marked, best-effort delete the leaked span via replacementRange, and
  continue in marked mode. The FIRST keystroke (replaceRange == NSNotFound, append == correct for
  everyone) is NOT validated. Wire a `ClientCapabilities.learnedAppendOnly() -> Bool` query
  (LiveClientCapabilities reads the cache) as a `classifyComposition` step so the learning persists across
  re-activations within the session.

**Honest limitation.** A true append-only app ignores replacementRange for the cleanup delete too, so an
UNKNOWN append-only app may leave a small one-time residue on its first composition before it is learned.
Cleanliness is guaranteed by the seed list (A); runtime learning (B) is a degrade-gracefully net (learn
once → marked forever after) — the same reason DKST keeps a large override list. Perfect retroactive
repair is fundamentally impossible.

### ② cursor-move invalidation (this phase, with the gate)
Problem: if the user moves the caret mid-composition (arrows/click), `directText` is still at the OLD
location so `directRangeIsCurrent` returns TRUE → the next jamo replaces at the stale spot (Word
move-then-delete jump). Fix: remember the expected caret after each inline render
(= `directRange.location + directRange.length`) on the controller (new state, e.g. `expectedCaret: Int?`);
at the start of the next inline op, if `selectedRange().location != expectedCaret` the user moved → clear
`directRange`/`directText` to RE-ANCHOR (the next insert lands fresh at the current caret; the
already-inline text stays as correct real text). Guard sits at `renderInline` entry / before
`inlineReplaceRange`.

### Scope + re-enable (decided 2026-06-05)
PHASE 2 ships ③ (non-invasive gate, A + B) AND ② together, all behind the unchanged default-FALSE
`inlineCompositionEnabled` kill-switch. The user flips it ON via the Preferences UI to run the on-device
matrix; whether to flip the DEFAULT to true is decided after that matrix passes. The learned-append cache
is session-scoped for now (persistent via config is a possible follow-up).

### Testing (PHASE 2)
- **Unit (pure)**: `bundleIdentifierUsesAppendOnlyTextStack` per bundle ID; the `learnedAppendOnly` branch
  in `classifyComposition` — same pattern as the existing `InlineCompositionTests`.
- **Unit (runtime)**: NSTextView honours replacementRange so it cannot reproduce Word; add an append-only
  fake IMK client double (ignores insertText's replacementRange) to unit-test the demote/learn path and
  the ② re-anchor. The existing 55+ suite must stay green (regression gate).
- **On-device matrix** (once, after enabling): Word/Excel/Hancom (seed → marked), Notes/Safari/Slack
  (stay inline), an unknown append app (B-layer learns).

Fallback if on-device shows the seed list is insufficient: widen the seed list; the runtime net already
catches the rest.

## Attribution

Port adapts logic from DKST (DINKIssTyle-IME-macOS), MIT © 2025 DINKIssTyle.
Retain an MIT attribution note in the inline source file and CREDITS/README.

## Out of scope (this spec)

Shift+jamo custom output, user text-expansion dictionary (separate DKST features),
and any change to the BCT terminal path (handled separately in claude-terminal).
