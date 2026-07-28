# AGENTS.md — Bomi

Guidance for AI coding agents working in this repository. Read this before making changes.

## Project overview

Bomi is a native macOS input method (IME) implementing the **Sebeolsik-final (세벌식 최종, 3f)** Korean keyboard layout, built on InputMethodKit (IMK) with a pure-Swift Hangul composition engine (no libhangul dependency). It runs as a background-only `.app` installed into `~/Library/Input Methods/`.

- Bundle id: `com.bomi.inputmethod.bomi`; IMK connection name: `com.bomi.inputmethod.bomi_Connection`.
- Two input modes declared in `Resources/Info.plist`: `com.bomi.inputmethod.bomi.korean` (default) and `com.bomi.inputmethod.bomi.roman`. Han/Eng switching is done by switching the active input mode (macOS/TIS owns the truth), not by an internal boolean.
- Toggle key defaults to Right Command (kVK_RightCommand, 0x36), fires on **press**, with an 80 ms duplicate-press debounce (the source switch and Chromium apps emit double press events).
- Composition strategy: per-syllable immediate commit (not eojeol-keep), chosen for robustness in Terminal/Electron hosts.
- Requirements: macOS 14+, Swift 6.2+ toolchain (developed against Swift 6.3.3). SwiftPM-only — no Xcode project, no external dependencies.

## Repository layout

- `Package.swift` — the only build configuration. Three library/executable targets + two test targets.
- `Sources/BomiEngine/` — pure-Swift, dependency-free composition engine: `Jamo.swift` (jamo ranges/slots), `Combination.swift` (compound jamo rules), `SebeolsikFinal.swift` (ASCII→jamo map + compat table), `Syllable.swift` (Unicode composition formula), `HangulComposer.swift` (the stateful automaton: `inputASCII`, `backspace`, `flush`, `preedit`). No IMK imports; fully unit-tested.
- `Sources/BomiCore/` — IMK-free app logic, split out of the executable **specifically so `swift test` can cover it** (an `executableTarget` with top-level `main` can't be `@testable`d). Contains `KeyTranslator` (keyCode→US-QWERTY ASCII), `InputMode`, `ModeState` (the process-wide `@MainActor` mode cache), `ToggleGate` (press-based toggle detection), `Preferences` (UserDefaults-backed toggle key, incl. per-app substitution for Royal TSX which delivers Right-Cmd as Right-Option).
- `Sources/Bomi/` — the executable, IMK integration layer: `main.swift` (`BomiApplication` + `IMKServer` bootstrap), `BomiInputController.swift` (the `IMKInputController` subclass), `ModeSwitcher.swift` (TIS/IMK mode switching + verification), `MenuBuilder.swift` (input-source menu), `DebugLog.swift` (file logging). This target builds with `.defaultIsolation(MainActor.self)`.
- `Tests/BomiEngineTests/`, `Tests/BomiCoreTests/` — swift-testing suites mirroring the two library targets.
- `Resources/` — `Info.plist` (input-mode declarations, icons), PNG icons, `en.lproj`/`ko.lproj` localized input-source display names (without these the input-source list shows raw mode identifiers).
- `Scripts/` — `assemble-app.sh` (release build + bundle + ad-hoc codesign), `install.sh` (kill running IME, copy to `~/Library/Input Methods/`), `analyze-debug-log.py` (per-app health report from the debug log), `bomi-log-snapshot.sh` (launchd job preserving `/tmp` logs across reboots).
- `docs/superpowers/specs/`, `docs/superpowers/plans/` — design specs and implementation plans (notably the Han/Eng mode-switching design, which records the on-device evidence behind the toggle architecture).

## Build, test, install

```bash
swift build                 # debug build
swift build -c release      # release build
swift test                  # all unit tests (currently 35, all must pass)
./Scripts/assemble-app.sh   # -> Bomi.app at repo root (ad-hoc signed)
./Scripts/install.sh        # -> ~/Library/Input Methods/Bomi.app
```

There is no linter/formatter config and no CI in the repo; `swift build` (warnings-clean) and `swift test` are the gates. Both pass clean as of this writing.

**The IMK layer cannot be verified headlessly.** `BomiInputController`/`ModeSwitcher` behavior (preedit display, toggle, per-app behavior) requires a logged-in GUI session with the IME installed and added in System Settings > Keyboard > Input Sources. The README's "Manual verification" section is the checklist (basic composition, backspace revert, toggle + chord guard, per-app memory, hard apps: Terminal/iTerm2/Electron/password fields). Don't claim an IMK-layer change "works" from `swift build` alone — say it builds and state what still needs on-device verification.

## Testing conventions

- Framework is **swift-testing** (`import Testing`, `@Test func`, `#expect`) — not XCTest. Match this in new tests.
- Test only `BomiEngine` and `BomiCore`. Keep new logic in those targets when it can be expressed IMK-free; that split exists to keep the code testable.
- Engine tests type ASCII strings through `HangulComposer` and compare committed Hangul (see `ComposerTests.swift`'s `type(_:)` helper). `ToggleGate`'s debounce clock is injected (`now:`) precisely so it's deterministic under test.
- `Preferences` takes an injectable `UserDefaults` suite so tests never touch the standard store.

## Code style and conventions

- Swift 6 concurrency is real here: the `Bomi` executable target defaults to `MainActor` isolation; IMK callbacks are `nonisolated` and hop via `MainActor.assumeIsolated`; an `UncheckedSendableBox` carries the non-Sendable ObjC `sender` across. Preserve these patterns rather than fighting them.
- Comment style: dense, explains **why** (often with on-device measured evidence), not what. Many hard-won IMK quirks are documented inline — e.g. why `TISSelectInputSource` must not be used for toggling (leaves IMK event routing stale; use IMK's `selectMode` via `ModeSwitcher.selectViaIMK`), why the toggle fires on press (the source switch eats the key-up), why `ModeState` is a single process-wide optimistic cache repaired from TIS in `activateServer`. **Treat these comments as load-bearing** — don't "clean them up" or revert the decisions they record without on-device evidence.
- Passthrough key set (Enter/Tab/Escape/arrows/space) lives in `BomiInputController.passthroughKeys`; backspace reverts one jamo at a time via the composer's stack (compound jamo revert to their base).
- Git history uses conventional-commit-style prefixes (`fix:`, `tools:`, `chore(session):`).
- Localization: UI strings (menu, input-source names) are Korean-facing; code, comments, docs, and this file are English.

## Debug logging and diagnostics

`DebugLog` is permanent infrastructure (os_log/NSLog output from an IME never surfaces in Console.app):

```bash
touch /tmp/bomi-debug.on   # enable  (takes effect within ~5s)
rm /tmp/bomi-debug.on      # disable (same)
# log file: /tmp/bomi-debug.log ; per-app report:
Scripts/analyze-debug-log.py [path]
```

The switch file is re-checked at most once every 5s behind a lock; writes are serialized off the input thread. **Never `killall Bomi` to bounce logging (or for anything else while it is the selected input source):** a selected-but-dead IME until the next keystroke is how Bomi got dropped from `AppleEnabledInputSources` on 2026-07-28, causing intermittent reverts to the default input source. `bomi-log-snapshot.sh` (via launchd) preserves the log across reboots into `~/Library/Application Support/Bomi/` and logs each run whether Bomi is still in the persisted enabled list (`maintenance.log`).

## Security and privacy considerations

- The debug log records keystroke-level data (keyCodes, preedit/commit text) into a world-readable `/tmp` file while enabled. Never ship a build that logs without the switch file, and never log more content than the existing instrumentation.
- The IME handles text in password fields like any other input source; do not add telemetry, network calls, or persistence of typed text.
- Preferences are `UserDefaults`-backed; an out-of-range stored `toggleKeyCode` must never crash the IME (use `UInt16(exactly:)`, see `Preferences`).
- The app is ad-hoc code-signed; `install.sh` kills any running `Bomi` process before replacing the bundle.

## Known follow-ups (out of current scope)

Hanja conversion, symbol layer, Dubeolsik layout, eojeol-keep mode, a real Preferences window, and a per-client marked-text fallback for hosts that don't honor `setMarkedText` (add only if manual hard-app testing shows garbled preedit — see README).
