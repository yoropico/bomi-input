## Session state (devmode)
- **2026-06-18 (latest) — secure-input 한/영 토글 REAL FIX shipped + committed `db07625`: detect via flagsChanged keyCode.**
  Rigorous on-device diag (fresh-pid-verified builds) found: device-dependent left/right modifier BITS are NOT
  delivered to the IME (only device-independent 0x100000) → the prior device-bit fix was INERT (toggle always rode
  the IOKitty fallback). BUT `event.keyCode` (right Cmd=54) IS delivered under Secure Event Input (verified secure=true
  in Terminal+TextEdit) → so the earlier "bomi gets zero events under secure → unfixable" was a STALE-BUILD artifact,
  refuted. Fix replaces deviceModifierMask/rightToggleKeyDidPress with toggleKeyVirtualKeyCode/rightToggleKeyPressedByKeyCode
  (keyCode-based); user confirmed toggle now works under secure. ~1s post-switch delay = macOS selectMode switching
  bomi's SEPARATE Hangul/Roman input sources (timing diag: bomi processes in <1ms; pre-existing, NOT this fix; user
  accepted). Clean Release 1.15.1 installed (diag reverted; verified). Tests 94/1-baseline. Memory
  [[secure-input-toggle-limit]] CORRECTED. Open follow-up: reduce selectMode switch latency = single-input-source
  architecture (big change, unsolved). git: committed db07625, pushing.
- **2026-06-18 — (superseded by above) device-flag attempt + version display + install-race fixes** (commits 68134e0,
  6c14731, 5353b13, 38812b1). Version now shows in 정보/About (build with `VERSION=1.15.1`); install must cp-first
  then killall (race). Per-keystroke dead IPC removed (typing faster, user-confirmed).
  File-logging diagnostic proved: while `IsSecureEventInputEnabled()` and focus is in the secure context (Terminal),
  bomi receives ZERO events → IME fully bypassed → unfixable in-IME for that case (the user's real scenario). Same
  root as the 2026-06-16 BCT secure-input lag report. The committed device-flag fix (`68134e0`) only helps the
  narrow non-secure-field-focus case; harmless + bundles the user-confirmed per-key perf win. CHANGELOG `[1.15.1]`
  reworded honestly + CLAUDE.md documents `VERSION=` (committed `5353b13`). **Version display fixed**: builds now
  pass `VERSION=1.15.1` (+ `CURRENT_PROJECT_VERSION=1.15`) so Info.plist `${VERSION}` → `CFBundleShortVersionString`
  is populated and the **정보/About panel shows "버전 1.15.1"** (was empty before). Installed clean build (no
  diagnostic). See memory [[secure-input-toggle-limit]]. Possible follow-ups: macOS-native input-source switch
  shortcut as a secure-input workaround (untested); enrich CFBundleVersion with git hash for build-level verify.
- **2026-06-17 — FIX SHIPPED + COMMITTED `68134e0` + PUSHED to origin/main: right-Command (한/영) toggle
  intermittently dead, fixed by refocus; + per-keystroke IPC removal (typing latency, user-confirmed faster).**
  CHANGELOG.md `[1.15.1]` recorded. Installed (Release) and dogfooding. Root cause (code-confirmed): right-toggle detection depended SOLELY on the global IOHIDManager monitor
  (IOKitty `rightKeyPressed`, `InputController` flagsChanged:383), decoupled from the IME's own event stream —
  blocked system-wide when ANOTHER process holds macOS Secure Event Input, while normal IMK delivery to the focused
  non-secure field keeps working (Korean still types, but 한/영 toggle + menu-bar icon never fire; refocus releases
  the other app's secure input → recovers). FIX (TDD): detect the right toggle from the IME's OWN `flagsChanged`
  device-dependent modifier bits (`deviceModifierMask`/`rightToggleKeyDidPress` in InputMethodServer.swift, mapping
  HID usage→`NX_DEVICE*_KEYMASK`); IOKitty consumed on toggle-key bit-change to avoid double-fire, kept as fallback
  when device bits absent (no regression). Diagnostic `NSLog` fires when the device path rescues a toggle IOKitty
  missed (`log show … | grep "device flags"`). Files: OSXCore/InputMethodServer.swift, OSXCore/InputController.swift,
  GureumTests/RightToggleKeyTests.swift (12/12 pass; full OSXTests 94 run/1 known baseline), pbxproj (+4 entries).
  Release built + installed (clean load), COMMITTED `68134e0` + pushed. Assumption: AppKit delivers device-dependent
  modifier bits in flagsChanged (standard); else safe fallback to old IOKitty path. PENDING: real-world confirm of
  the secure-input scenario (couldn't reproduce on demand; diagnostic NSLog `… | grep "device flags"` will show it).
  (Distinct from the 2026-06-16 latency report below — that refuted per-keystroke churn; this is the toggle path.)
- **2026-06-16 — Secure-input lag report (`/Users/bglee/bomi-ime-secure-input-conflict-report.md`): bomi EXONERATED.**
  Report claimed bomi does per-keystroke input-source churn under macOS Secure Event Input (SecureField). REFUTED by
  code (no `TISSelectInputSource` anywhere, no input-source-change observer — CloudStatusItemController removed; key
  hot-path uses cached `useMarkedText`; Release `dlog`=no-op) AND by live test. Harness `/tmp/securetest.swift`
  (AppKit `NSSecureTextField` + control `NSTextField`; logs inter-keystroke delta + `IsSecureEventInputEnabled` +
  current TIS source). User typed ASCII fast, `secure=YES` confirmed → **bomi FAST**: deltas 15–90ms bursts, steady
  ~83ms autorepeat runs; spikes (19741/1790/775ms) = pauses/backspaces, not per-key lag. TIS src stayed
  `com.yoropico…bomi-input.system` (NO ABC coercion); bomi-input PID 993 same etime before/after (no relaunch),
  0% CPU. Differentiator = BCT's **SwiftUI `SecureField`** (or BCT terminal env), NOT bomi. Report's bomi-side
  fixes (#1 secure-detect / #2 TIS-debounce / #3 passthrough) NOT implemented — nothing to fix in bomi. BCT: keep
  TextField+mask workaround. Optional next: minimal SwiftUI `SecureField` test to nail SwiftUI-vs-AppKit (needs
  on-device typing). No bomi code/commits changed.
- Updated: 2026-06-05. **Inline PHASE 2 (③ non-invasive gate + ② cursor-move) IMPLEMENTED + committed LOCAL
  `2a34871`, behind kill-switch (inline still OFF/default-FALSE).** Built via devmode TEAM mode (planner step
  skipped — used the committed writing-plans plan; implementer→tester→reviewer). OSXTests **PASS** (82 run, 1
  known IMK-env baseline `testIPMDServerClientWrapper`), reviewer **APPROVE**. NOT installed/dogfooded yet.
  git: local **ahead of origin/main(`6949e8c`)** by 555e081 + 2217d5a(spec) + 9abab73(plan) + 2a34871(feat) —
  UNPUSHED (push needs per-instance auth). Build/sign/install + git rules + sandbox-defaults gotcha in CLAUDE.md.
- **PHASE 2 decision: invasive probe REJECTED** (data-loss on selection / reactive-field side effects / undo
  pollution / clean repair impossible in true append-only). Chose **non-invasive 2-layer**: A = pure seed list
  `bundleIdentifierUsesAppendOnlyTextStack` (Office/HWP → marked from key 1, zero artifact); B = runtime learning
  in renderInline (caret-landing validation after a real replace → on mismatch demote client to marked + record
  bundle id in session `learnedAppendOnlyCache` (queried via `ClientCapabilities.learnedAppendOnly`) + best-effort
  delete leak + marked re-render). ② = `expectedCaret` tracked; stale `directRange` dropped on cursor move, gated
  to `action == .none` so the ① commit fail-safe survives. Spec/plan: docs/superpowers/{specs,plans}/…inline….
- **NEXT for inline**: install build → flip UI switch ON → on-device matrix (Word/Excel/한글→marked seed;
  Notes/Safari/Slack→inline; unknown append app→B learns) → then decide flip default ON. Tiny non-blocking
  follow-up (reviewer note): `commitCompositionEvent` inline branch clears directRange but not expectedCaret
  (harmless — ② guard requires directRange!=nil; renderInline always re-sets it). Verify seed bundle IDs on-device.
- **OPEN (BCT-side, NOT bomi)**: BCT garbled PREEDIT in marked mode ("?<0095><009c>") — BCT preedit handling;
  bomi marked path is standard. `[ime-diag]` logs in BCT `src/app/event_loop/ime.rs` → ~/.config/bomi-claude-terminal/bct.log.
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
- **2026-06-18 RECURRENCE → DOGFOOD RESUMED (inline ON, DIAG build live)**: user reported "랜덤하게
  마지막단어 중복"; root cause = inline was RE-ENABLED (container plist `InlineCompositionEnabled=true`;
  read the REAL sandboxed plist, not the code default). User confirmed INTENTIONAL (의도하였음) → wants
  inline working. Re-enabled inline. Reported dup location = **Apple Terminal** (com.apple.Terminal), but
  INTERMITTENT (single tests + user's own live msgs all clean) → "랜덤". Installed FILE-logging diagnostic
  build **1.15.1-diag2** (pid 62015): logs per-activateServer classification (bundle/shows/selQ/mode/marked)
  + per-commit (inlineBranch/commitString) with timestamps to ~/Library/Containers/.../Data/bomi_inline_diag.log.
  HYPOTHESIS: useMarkedText cached once at activateServer; if bundleIdentifier()==nil or Apple-signal
  (chain step 2, precedes step-6 terminal allowlist) misbehaves at that instant → Terminal mis-cached as
  inline that focus session → dup until refocus. AWAITING: user reproduces dup → read log tail → confirm +
  fix. **DESIGN DECISION (user, 2026-06-18): KEEP default=inline; switch to marked only for specific cases
  (= current blocklist + learnedAppendOnly auto-demote). Do NOT invert to default-marked (spec ③ rejected).**
  So the fix = make the "specific case → marked" RELIABLE (stop the terminal intermittent leak; likely
  reorder known-marked lists before the Apple-signal step OR fix nil-bundleID-at-activate), NOT a wholesale
  inversion. DIAG CODE UNCOMMITTED (InputController.swift + InputReceiver.swift) — `git checkout` both
  before any commit.

### NEXT
- **Inline PHASE 2 (paused, resume when ready)**: invasive pre-composition probe → glitch-free ③
  capability gate (auto-marks Word/non-standard apps); then ② cursor-move invalidation; then re-enable
  inline + on-device matrix. Spec "PHASE 2" section has the design. (Inline OFF until then = stable.)
- Push local ahead 3 (`2e9cea1`+`aee41d6`+`3e3bee6`) — phase-1 checkpoint; needs fresh per-instance auth.
- **Shift+jamo → custom output** (⬜ not started) — independent, no hot-path risk; good parallel feature.
- **User custom dictionary** (⬜ not started).
- BCT preedit garbled-marked bug — separate repo (claude-terminal), out of scope for bomi.

### Notes
- Removing input modes: on-device, the 4 vanish from the input-source picker; if previously added, a
  logout/login forces clean re-registration.
- MCP session sync ON (.claude/devmode.json sessionProject=gureum). Build/sign/install + git rules in CLAUDE.md.
