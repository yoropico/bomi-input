## Session state (devmode)
- Updated: 2026-06-05. **INLINE DISABLED by user** (`InlineCompositionEnabled=false` in sandbox container)
  after a dogfood failure cascade → back to the years-stable MARKED path everywhere. Clean Release rebuilt
  (debug NSLog removed) + reinstalled (pid live), inline OFF confirmed. git: origin `55d3b5b`; **local ahead 1
  (`2e9cea1`, dormant)**. Built/sign/install + git rules + sandbox defaults gotcha in CLAUDE.md.
- **Inline status: shelved.** P1+P2+P3-UI + terminals→marked (`33a2be2`) all pushed. Dogfooding found inline
  fails broadly — ONE root cause: tracked `directRange` drifts out of sync with the real document. Symptoms:
  commit dup "안녕"→"안녕녕" (Finder + all apps, space/enter); Word cursor-jump on move-then-delete (stale
  directRange); terminals (PTY); Word custom engine. `2e9cea1` fixed ONE commit append-path + a mock infidelity
  (MockInputController.cancelComposition was missing `directRange=nil`) but Finder still dup'd via the
  delete/validate gap. **Fundamental fix written in the spec** (validate-or-bail everywhere / cursor-move
  invalidation / capability-probe→marked). Re-enabling inline REQUIRES that hardening (or drop inline).
- **OPEN (BCT-side, NOT bomi)**: BCT garbled PREEDIT in marked mode ("?<0095><009c>") — BCT preedit handling;
  bomi marked path is standard. `[ime-diag]` logs in BCT `src/app/event_loop/ime.rs` → ~/.config/bomi-claude-terminal/bct.log.
- Project: **bomi-input** (macOS IME, rebranded from Gureum). Durable build/sign/install commands,
  signing identity, git hazards, and the xib-module gotcha live in **CLAUDE.md — read it on resume.**

### DIAGNOSIS — where things stand
- The bomi-input rebrand is **functional and shipped**. Korean input works. UI is fully de-Gureum'd.
- **DKST inline direct-input** — P1+P2+P3-UI+terminal-fix DONE but **SHELVED (disabled)**: dogfooding
  proved it's not robust (directRange-drift cascade, see top). Re-enabling needs the fundamental hardening
  documented in the spec STATUS section (validate-or-bail / cursor-move invalidation / capability-probe→marked),
  or a decision to drop inline. Marked mode (default) is stable.
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

### DOGFOOD RESULT (inline now OFF)
- Inline failed broadly (directRange-drift): commit dup "안녕→안녕녕" (Finder + all apps); Word move-then-
  delete cursor jump; terminals; Word custom engine. User DISABLED inline → marked stable. Re-enable needs
  the fundamental hardening (spec STATUS 2026-06-05 section): ①validate-or-bail ②cursor-move invalidation
  ③capability-probe→marked. `2e9cea1` (local) = partial commit-dup fix, dormant.

### NEXT (pick one)
- **Inline fundamental hardening** (only if pursuing inline) — implement spec STATUS ①②③, then re-enable.
  Else: drop inline (marked is the stable default) — could revert/retire the inline code later.
- Push `2e9cea1` (local ahead 1; or hold until inline hardening lands).
- **Shift+jamo → custom output** (⬜ not started) — independent, no hot-path risk; good next feature.
- **User custom dictionary** (⬜ not started).
- BCT preedit garbled-marked bug — separate repo (claude-terminal), out of scope for bomi.

### Notes
- Removing input modes: on-device, the 4 vanish from the input-source picker; if previously added, a
  logout/login forces clean re-registration.
- MCP session sync ON (.claude/devmode.json sessionProject=gureum). Build/sign/install + git rules in CLAUDE.md.
