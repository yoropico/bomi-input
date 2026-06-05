## Session state (devmode)
- Updated: 2026-06-05. Inline P1+P2+P3-UI pushed (`5102d16`). **Dogfood fix: terminals→marked (`33a2be2`)
  committed LOCAL — local ahead 2, UNPUSHED** (33a2be2 + devmode 72b8366). Built signed Release + installed.
  `main` tracks `origin/main`; re-check `git log`/`git status` on resume. Only `main`.
- Project: **bomi-input** (macOS IME, rebranded from Gureum). Durable build/sign/install commands,
  signing identity, git hazards, and the xib-module gotcha live in **CLAUDE.md — read it on resume.**

### DIAGNOSIS — where things stand
- The bomi-input rebrand is **functional and shipped**. Korean input works. UI is fully de-Gureum'd.
- **DKST inline direct-input** is at **P1 + P2 + P3-UI done, still DORMANT** behind the default-FALSE
  kill-switch `inlineCompositionEnabled`. P1 (ecd254f) + P2 (3b36d95) + **P3 UI (5102d16) all pushed**.
  The settings pane now exposes the master toggle, so the **next on-device step is: open
  환경설정 → "인라인 직접 입력 (실험적)" → enable → dogfood** (P3 hot-path hardening deferred by decision).
  No other DKST feature (Shift+jamo, user dictionary) is started.

### DONE & SHIPPED (origin/main == a14dc5d)
- **Rebrand → bomi-input**: bundle id `com.yoropico.inputmethod.bomi-input`, input-source ids,
  `bomi-input.xcodeproj`. Korean input FIXED (root cause: MainMenu.xib app-delegate `customModule="Gureum"`
  missing `customModuleProvider="target"` → module Gureum→bomi_input broke delegate/IMKServer; e67b01d).
- **Menu-bar input-source icons**: ㅂ/B brand glyphs (de6ef3e). These are the SYSTEM input-menu icons; STAY.
- **Inline direct-input P1** (DKST port, MIT): committed `ecd254f`, spec `c3230ca`. Behind default-FALSE
  kill-switch `inlineCompositionEnabled`. NEW OSXCore/InlineComposition.swift (classifyComposition decision),
  InputController (directRange/LiveClientCapabilities/useMarkedText), InputReceiver (renderInline +
  inline-aware commit). OSXTests 55 pass/1 baseline, reviewer APPROVE. Built via devmode TEAM mode.
- **DKST research**: docs/research/2026-06-04-dkst-source-analysis.md (80a921d). DKST is MIT → portable.
- **UI cleanup** (this session, committed `bfe31e9` + `a14dc5d`):
  - Removed CloudStatusItemController (the separate NSStatusItem ㅂ/B menu-bar indicator) + unused import Carbon.
  - Removed 4 input modes from registration (Info.plist + ko/en InfoPlist.strings): deprecated roman
    qwerty/dvorak/colemak + test han3layout2. 12 modes remain; English = `system` ("로마자"). The Swift
    GureumInputSource/RomanComposer enum cases are KEPT (qwerty is the composer's reference layout) — just
    not user-selectable.
  - Rebranded all user-visible "구름"→bomi-input (Configuration.storyboard window title, Preferences.xib,
    MainMenu.xib, GureumMenu.swift alerts).
  - Trimmed the input-menu web links: removed 웹사이트/도움말/후원하기 (gureum URLs); kept 소스 코드 →
    github.com/yoropico/bomi-input and 버그 알리기 → .../issues.

### DKST FEATURE ROADMAP (the "다른 입력기 기능 추가" work)
1. **Inline direct-input** — 🟡 P1 + P2 DONE (dormant). P2 (3b36d95, pushed): WebKit/Chromium
   engine policy + user force-marked blocklist + global always-marked. Files: OSXCore/InlineComposition.swift
   (pure classifiers bundleIdentifierUsesWebKitTextStack / …ChromiumMarkedTextPolicy / …MatchesForcedMarkedList,
   classify chain steps 3–5 wired), OSXCore/InputController.swift (LiveClientCapabilities.forcedMarkedBundleIDs +
   usesChromiumFrameworkTextStack — NSRunningApplication + Contents/Frameworks scan, cached by bundle ID),
   OSXCore/Configuration.swift (key inlineCompositionForcedMarkedBundleIDs, default []), GureumTests/
   InlineCompositionTests.swift. **P3 UI (5102d16, pushed)**: Preferences/PreferenceViewController.swift adds
   "인라인 직접 입력 (실험적)" section built PROGRAMMATICALLY, appended to settings stack via ONE new xib
   outlet (inlineSettingsStackView→kLe-bm-FOO; no control XML in Preferences.xib). Controls: master enable,
   global always-marked, newline NSTextView blocklist editor. parse/format helpers live in Configuration.swift
   (NOT InlineComposition.swift) — prefpane USE_PREFPANE target compiles Configuration.swift in-module but not
   InlineComposition.swift. OSXTests 69/1-baseline pass (testPreferencePane OK), Release BUILD + install OK.
   **P3 hot-path hardening DEFERRED** (first-roman-leak, eager-sync): DKST's are engine-specific + speculative
   for bomi; port only if dogfooding shows real problems. Spec has the full P3 note.
   PENDING: flip kill-switch ON (now via UI) + on-device dogfood matrix. Spec:
   docs/superpowers/specs/2026-06-04-inline-direct-input-design.md (P1/P2/P3 phasing).
2. **Shift+jamo → custom string/emoji** — ⬜ not started.
3. **User custom dictionary (snippet expansion)** — ⬜ not started. (bomi already has hanja/emoji/MS-symbol
   search via SearchComposer + OSXCore/data/hanja/*; only the user-editable dict is new.)

### BCT (separate repo: /Users/bglee/Project/claude-terminal)
- Korean Enter latency FIXED — commit **36e700f** (master, local; user finished via another session).
  Root cause: stale `IME_RETURN_DETECTED` (per-Return-keyDown flag, only consumed by IME commit → a raw
  Return left it stale → next Hangul syllable-break commit fired a phantom \r). Fix: reset on every raw
  keyDown + immediate \r at commit (drop the 20ms timer). Needs a release build/install for daily use.

### DOGFOOD STATUS (inline ON)
- BCT terminal: inline→LAST-WORD DUP on commit → FIXED by terminals→marked (33a2be2, verified on-device).
- BCT then shows garbled PREEDIT in marked mode ("?<0095><009c>긐" = U+FFFD + C1 bytes = byte/char-sliced
  UTF-8). Diagnosed BCT-side preedit RENDER bug (NOT bomi — marked path is standard, works elsewhere; BCT
  commit path writes bytes to PTY fine). Confirm with Apple 2벌식 in BCT. Fix in claude-terminal repo
  (src/app/event_loop/ime.rs + preedit renderer char-indexing), out of scope for bomi.

### NEXT (pick one)
- Push local commits (ahead 2: 33a2be2 + 72b8366; needs fresh per-instance auth).
- Continue dogfood in NON-terminal apps (메모/Slack/Mail/Notion/Xcode/Safari) — verify inline is
  underline-free + correct there.
- Fix BCT preedit renderer (separate repo: claude-terminal).
- Shift+jamo custom output. / User custom dictionary.

### Notes
- Removing input modes: on-device, the 4 vanish from the input-source picker; if previously added, a
  logout/login forces clean re-registration.
- MCP session sync ON (.claude/devmode.json sessionProject=gureum). Build/sign/install + git rules in CLAUDE.md.
