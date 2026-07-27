# Bomi — Sebeolsik-final (3f) Hangul Input Method for macOS

Bomi is a native macOS Input Method Kit (IMK) input source implementing the
Sebeolsik-final (세벌식 최종, `3f`) Korean keyboard layout, with a pure-Swift
Hangul composition engine (no libhangul dependency at runtime).

**Status: MVP implemented, builds clean, GUI verification pending (see
"Manual verification" below).** The pure-Swift engine (jamo tables,
combination rules, syllable composition) has 15/15 automated unit tests
passing and was cross-checked against the canonical Unicode Hangul
composition formula. The IMK integration layer (key translation, preedit/
commit, han/eng toggle, per-app memory, input-source menu) builds and
assembles cleanly but has not yet been exercised interactively — that needs
a human with a logged-in GUI session.

## Features

- Sebeolsik-final (3f) layout: dedicated choseong/jungseong/jongseong keys,
  no 도깨비불 (jongseong never migrates onto the following syllable's
  choseong).
- Per-syllable immediate commit (not eojeol-keep) — robust in demanding
  host apps (Terminal, Electron).
- In-IME Han/Eng toggle, default key **Right Command**, with per-app
  language memory.
- Menu-bar input-source menu: current mode indicator, per-app-memory
  toggle.

## Requirements

- macOS 14+ (Sonoma or later).
- Xcode 26 / Swift 6.2+ toolchain (developed against Swift 6.3.3).

## Build

```bash
swift build -c release
```

## Run the engine's unit tests

```bash
swift test
```

## Assemble the `.app` bundle

```bash
./Scripts/assemble-app.sh
```

This runs a release build, assembles `Bomi.app` at the repo root
(`Contents/MacOS/Bomi`, `Contents/Info.plist`,
`Contents/Resources/*.png` plus the localized `*.lproj` strings), and
ad-hoc code-signs it.

## Install

```bash
./Scripts/install.sh
```

Copies `Bomi.app` into `~/Library/Input Methods/`. Then, to activate it:

1. Open **System Settings > Keyboard > Input Sources**, click **+**.
2. Find and add **Bomi**. If it doesn't appear in the list, log out and
   back in (or reboot) — macOS often needs a fresh session to pick up a
   newly installed `~/Library/Input Methods/*.app`.
3. Switch to Bomi via the menu-bar input switcher (or its shortcut).

## Manual verification (human, interactive GUI session required)

The steps below cannot be automated from a headless/non-interactive
environment and must be run by a human after `./Scripts/install.sh`:

1. **Add the input source**: System Settings > Keyboard > Input Sources >
   **+** > find and add **Bomi**. Log out/in if it doesn't appear.
2. **Basic composition**: switch to Bomi, open TextEdit, type `kfs` (US
   keys) — expect `간` (underlined preedit while composing, committed on
   the next syllable boundary). Try `kkf` → `까`, `kvf` → `과`.
3. **Backspace**: mid-syllable, press Delete — expect the syllable to
   revert one jamo at a time (compound jamo revert to their base, e.g.
   ㄺ → ㄹ).
4. **Han/Eng toggle**: tap Right Command alone (no other key) — expect the
   mode to flip between Korean and English; type a few letters after each
   toggle to confirm. Also confirm the chord guard: **Right Command + C
   (copy) then release Right Command must NOT toggle Han/Eng; a lone Right
   Command tap MUST toggle.**
5. **Per-app memory**: set one app to Korean and another to English, then
   switch between them (Cmd-Tab) — expect each app to remember its own
   mode.
6. **Input-source menu**: click the Bomi item in the menu bar — expect a
   menu showing the current mode (disabled indicator) and a checkable
   "앱별 한/영 기억" (per-app memory) item; toggling it should persist.
7. **Hard apps**: repeat steps 2–4 in **Terminal**, **iTerm2**, a
   **VS Code**/Electron window, and a password field — check for dropped
   or garbled preedit, and composition surviving (or correctly flushing
   on) focus loss / app switch mid-syllable.

Record pass/fail per app and step; report back anything that diverges so
it can be triaged as a real defect rather than silently worked around.

## Architecture

- `Sources/BomiEngine/` — pure-Swift, dependency-free Hangul composition
  engine (jamo tables, combination rules, syllable rendering,
  `HangulComposer` automaton). Fully unit-tested (`Tests/BomiEngineTests/`).
- `Sources/Bomi/` — the IMK integration layer: `KeyTranslator`
  (keyCode → 3f ASCII), `BomiInputController` (IMKInputController subclass:
  preedit/commit/backspace, han/eng toggle, per-app state), `LanguageMode`
  + `Preferences` (toggle key, per-app memory), `MenuBuilder` (input-source
  menu), `main.swift` (`IMKServer` bootstrap).
- `Resources/` — `Info.plist` (bundle id `com.bomi.inputmethod.bomi`,
  connection name `com.bomi.inputmethod.bomi_Connection`), the input-method
  icon (`bomi-input.png`), the menu-bar mode icons (`statusbomi_eng/han.png`
  + `@2x`), and localized input-source names (`en.lproj`/`ko.lproj`).
- `Scripts/` — `assemble-app.sh` (build + bundle + codesign),
  `install.sh` (copy to `~/Library/Input Methods`).

## Known follow-ups (out of MVP scope)

- Hanja conversion, symbol layer, Dubeolsik layout, eojeol-keep mode.
- A real Preferences window (currently the toggle key and per-app-memory
  flag are `UserDefaults`-backed with sane defaults, but there's no UI to
  change the toggle key).
- A per-client marked-text fallback (commit immediately instead of showing
  preedit) for host apps that don't honor `setMarkedText` — not yet
  implemented because it hasn't been confirmed necessary; add it to
  `BomiInputController.showPreedit` (guarded by a `canMark` check) only if
  the manual Electron/hard-app test above shows garbled or invisible
  preedit text.
