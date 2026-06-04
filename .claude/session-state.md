## Session state (devmode)
- Updated: 2026-06-05. **origin/main == `a14dc5d`; local main = a14dc5d + UNCOMMITTED P2 work** (4 files,
  see below). Tree otherwise clean. Only `main`.
- Project: **bomi-input** (macOS IME, rebranded from Gureum). Durable build/sign/install commands,
  signing identity, git hazards, and the xib-module gotcha live in **CLAUDE.md — read it on resume.**

### DIAGNOSIS — where things stand
- The bomi-input rebrand is **functional and shipped**. Korean input works. UI is fully de-Gureum'd.
- **DKST inline direct-input** is now at **P1 + P2 done, still DORMANT** behind the default-FALSE kill-switch
  `inlineCompositionEnabled`. P1 (ecd254f) is committed/pushed; **P2 (engine policy + blocklist) is implemented
  but UNCOMMITTED** (this session). Still NOT usable on-device until P3 + flipping the switch + dogfood.
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
1. **Inline direct-input** — 🟡 P1 + P2 DONE (dormant). P2 (UNCOMMITTED this session): WebKit/Chromium
   engine policy + user force-marked blocklist + global always-marked. Files: OSXCore/InlineComposition.swift
   (pure classifiers bundleIdentifierUsesWebKitTextStack / …ChromiumMarkedTextPolicy / …MatchesForcedMarkedList,
   classify chain steps 3–5 wired), OSXCore/InputController.swift (LiveClientCapabilities.forcedMarkedBundleIDs +
   usesChromiumFrameworkTextStack — NSRunningApplication + Contents/Frameworks scan, cached by bundle ID),
   OSXCore/Configuration.swift (key inlineCompositionForcedMarkedBundleIDs, default []), GureumTests/
   InlineCompositionTests.swift (9 new tests). OSXTests 65/1-baseline pass, Release BUILD SUCCEEDED.
   PENDING: **P3** (first-roman leak repair, eager-sync, settings UI). Then flip kill-switch ON + dogfood.
   Spec: docs/superpowers/specs/2026-06-04-inline-direct-input-design.md (P1/P2/P3 phasing).
2. **Shift+jamo → custom string/emoji** — ⬜ not started.
3. **User custom dictionary (snippet expansion)** — ⬜ not started. (bomi already has hanja/emoji/MS-symbol
   search via SearchComposer + OSXCore/data/hanja/*; only the user-editable dict is new.)

### BCT (separate repo: /Users/bglee/Project/claude-terminal)
- Korean Enter latency FIXED — commit **36e700f** (master, local; user finished via another session).
  Root cause: stale `IME_RETURN_DETECTED` (per-Return-keyDown flag, only consumed by IME commit → a raw
  Return left it stale → next Hangul syllable-break commit fired a phantom \r). Fix: reset on every raw
  keyDown + immediate \r at commit (drop the 20ms timer). Needs a release build/install for daily use.

### NEXT (pick one)
- **Commit P2** (4 files, uncommitted) — then push (needs fresh per-instance auth).
- Inline **P3** (first-roman leak repair, eager-sync, Preferences UI for toggles + blocklist editor) — last
  step before flipping the kill-switch ON.
- Shift+jamo custom output.
- User custom dictionary.
- Or flip inline kill-switch ON + on-device manual matrix now (P1+P2 in place; P3 hardening still missing).

### Notes
- Removing input modes: on-device, the 4 vanish from the input-source picker; if previously added, a
  logout/login forces clean re-registration.
- MCP session sync ON (.claude/devmode.json sessionProject=gureum). Build/sign/install + git rules in CLAUDE.md.
