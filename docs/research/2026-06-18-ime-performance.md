# macOS Hangul IME performance / per-keystroke latency

Date: 2026-06-18
Method: deep-research harness. Core claims verified 3-0 / 2-1 against PRIMARY source code
(libhangul C, Mozc incl. its macOS controller, fcitx5-macos master, McBopomofo design wiki).
Some secondary claims (threading/caching/signpost specifics) were rate-limited during verification
(0 votes) — flagged below as unverified. Run ID `wf_48cc9488-789`.

## Headline: the hot path is IPC-bound, not computation-bound

- **libhangul is NOT the bottleneck (verified 3-0).** Per keystroke it does ZERO dynamic allocation
  (one `malloc` only at `hangul_ic_new`; fixed inline buffers `preedit_string[64]`/`commit_string[64]`),
  and jamo combination is an O(log n) `bsearch` over a tiny sorted table. Optimise the IMK/client-call
  path, NOT the automaton.
  - Sources: libhangul `hangulinputcontext.c`, `hangulkeyboard.c`.
- **The real per-key cost = synchronous cross-process client calls** (`selectedRange`, `markedRange`,
  `attributedSubstring`, `firstRect`, `setMarkedText`, `insertText`). Each is an IPC round-trip to the
  focused app on the main thread.

## Prioritised, implementable wins

### 🥇 1. Single input source for 한/영 (biggest UX win; the ~1s toggle)
The ~1s 한/영 delay is because bomi registers Hangul and Roman as SEPARATE macOS input sources, so
toggling routes through the OS `selectMode`/`TISSelectInputSource` switch (bomi calls
`(sender as IMKTextInput).selectMode(mode)` at `InputReceiver.swift:288`).
- Fast CJK IMEs toggle mode INTERNALLY inside one engine. **Mozc / Google Japanese Input** (verified
  against its actual macOS controller `GoogleJapaneseInputController.mm`): `switchMode:` /
  `switchModeInternal:` change an in-engine `CompositionMode` and update only the UI via
  `[client selectInputMode:]` — **NO `TISSelectInputSource` in the mode-switch path**.
- **Open question (NOT empirically confirmed for a Hangul IME on macOS):** does replacing `selectMode`
  with an internal mode flag + `client.selectInputMode:` actually eliminate the delay, or does IMK still
  route Hangul mode changes through a slow path? → run a small SPIKE before committing to the migration
  (which is a real architectural change: input-source registration in Info.plist, mode handling).
- Sources: Mozc `commands.proto` (`enum CompositionMode`), `GoogleJapaneseInputController.mm`.

### 🥈 2. Remove dead / speculative per-key client IPC (DONE — commit 6cd9219)
The marked path queried `controller.selectionRange()` (sync IPC) every key only to set
`hasSelectionRange`, which was read nowhere. Removed it + the unused property, and reordered the
`updateComposition()` guard so cheap local checks come first and the remaining `selectionRange()` IPC
is short-circuited on the common composing key. Rule: **never query the client speculatively per key;
query only at the moment the value is consumed (commit/anchor).**
- fcitx5-macos corroborates the IPC-cost framing (synchronous key→commit is the norm; keep the sync
  body lean rather than going async).

### 🥉 3. Keep the synchronous keystroke body lean (hygiene)
- fcitx5-macos (verified 3-0) processes keys SYNCHRONOUSLY and commits inline on the same call — async
  is NOT the answer; a lean synchronous body is.
- **McBopomofo (verified 3-0)** structures the hot path as a pure `(event, state) -> state` transition,
  decoupled from IMK and unit-testable, with UI/output pushed to the controller edge. Maps to bomi's
  `InputController → InputReceiver → GureumComposer/HangulComposer` split — keep the per-key core a
  cheap pure function, push all client/UI side effects to the edge.
- Per-client capability caching at `activateServer` (bomi already does this: `classifyComposition` /
  `useMarkedText` computed once at activation, not per key).

### 🔬 0. Measure first
No absolute keyDown→insertText latency number was verified for any IME. Before deeper optimisation, add
`os_signpost` intervals (keyDown→insertText) and read them in Instruments to get a baseline (median/p99
under fast typing) and to attribute time (libhangul vs client round-trip). (signpost recipe was
blog-sourced/unverified — confirm against Apple docs.)

## Unverified (rate-limited or blog-only) — treat as LEADS, not facts
- "All IMK client methods except setMarkedText/insertText can be dispatched async on the MainActor" — 0
  votes. Do NOT rely on a clean async/sync partition without Apple docs + experiment.
- NSMapTable-weak-key autoreleasepool-drain hazard / fixed-capacity LRU-by-address caching — 0/split
  votes. Don't change per-client storage structure on this basis alone.
- "macOS creates a new IMKInputController per rapid switch → ARC-cleanup lag" — 1-0, under-verified.
- os_signpost begin/end measurement recipe — 0 votes (plausible, standard, but unverified here).

## Key sources
- libhangul: https://github.com/libhangul/libhangul (`hangul/hangulinputcontext.c`, `hangulkeyboard.c`)
- Mozc: https://github.com/google/mozc (`src/mac/GoogleJapaneseInputController.mm`, `src/protocol/commands.proto`)
- fcitx5-macos: https://github.com/fcitx-contrib/fcitx5-macos
- McBopomofo architecture: https://github.com/openvanilla/McBopomofo/wiki
- os_signpost (unverified): https://www.donnywals.com/measuring-performance-with-os_signpost/
