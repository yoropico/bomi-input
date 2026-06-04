# Inline direct-input (no-underline composition) — design

Date: 2026-06-04. Target: bomi-input (macOS IME, libhangul + InputMethodKit).
Status: approved design, pre-implementation.

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

- **P1 (core)**: policy decision function (+ unit tests) for native Cocoa
  (showsComposingTextAsMarkedText + selectedRange + default), inline render at
  `updateComposition`, commit/compose mapping, marked-text fallback, master default.
- **P2 (engines + config)**: WebKit/Chromium detection (+ framework scan cache),
  user force-marked blocklist defaults-key, global always-marked toggle.
- **P3 (edges + UI)**: first-roman-leak repair, eager-sync avoidance, full state
  reset hardening, Preferences UI for toggles + blocklist editor.

## Attribution

Port adapts logic from DKST (DINKIssTyle-IME-macOS), MIT © 2025 DINKIssTyle.
Retain an MIT attribution note in the inline source file and CREDITS/README.

## Out of scope (this spec)

Shift+jamo custom output, user text-expansion dictionary (separate DKST features),
and any change to the BCT terminal path (handled separately in claude-terminal).
