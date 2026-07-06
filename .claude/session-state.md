## Session state (devmode)
- **2026-07-01 (RESOLVED — right-Cmd 한/영 double-fire fixed via time-debounce; committed a4bcfab, clean 1.15.3 installed).**
  Root cause CONFIRMED via on-device file log (bomi_toggle_diag.log): Chromium apps (Edge = com.microsoft.edgemac) emit **TWO**
  flagsChanged PRESS events (identical changed/current, 2–11ms apart) per ONE physical right-Cmd press → toggle fires twice →
  한→영→한 instant revert = "안됨". Terminal emits ONE → works. Edge intermittently 1 or 2 → "되는 필드/안되는 필드". (Same
  double-toggle the 06-25 diag11 asymmetric-HID-dedup fixed, which was REVERTED in the 06-30 consolidation — this is a simpler
  flagsChanged-side fix that does NOT depend on IOKitty.) FIX (branch `fix/hanyoung-toggle-double-fire`, commit a4bcfab):
  time-debounce toggle fires (`isDuplicateToggleFire`, 80ms window) — dup within window suppressed, human re-toggle ≥150ms passes;
  robust to BOTH dup-fire AND missed-key-up wedge. Also: `ModifierFlagsTracker` reset on activate/deactivate/fire (wedge fix, the
  old "no response, refocus fixes it"); keyCode path sole authority, IOKitty fallback disabled when a right-modifier is configured
  (removes a 2-detector race). Diag logging (toggleDiagLog) REMOVED before commit. RightToggleKeyTests 17/17. Clean Release
  **1.15.3** installed, diag log deleted. INCIDENT mid-session: `xcodebuild test` launched a Debug host that popped a debug alert;
  my killall+`open` cycle WEDGED bomi (input dead everywhere; "완전 종료 후 재실행" un-wedged); restored via clean reinstall.
  LESSON (worklog): NEVER run `xcodebuild test` against the live IME while the user types; cp+killall+`open` reinstall can wedge,
  a full process restart un-wedges. NEXT: user "올려" → push branch + PR; optional FULL OSXTests (only focused toggle tests run);
  on-device dogfood. `.claude/*` (worklog+session-state) = this save.
- **2026-06-26 (SUPERSEDED by 07-01 — diag13 running, inline OFF). Toggle fix solid; chasing app-specific input symptoms, mostly transient.**
  Running: bomi 1.15.2-diag13. **InlineCompositionEnabled=false** (user-set, to test terminal; KEPT per user choice). Active code
  changes vs HEAD (all UNCOMMITTED): (1) inline-reclassify (pre-session), (2) IOKitty toggle fix — performRightToggle(viaHID:)
  asymmetric dedup (HID authoritative + flagsChanged defers 0.4s; toggle-press always returns true to consume the right-Cmd so
  the app can't make a Cmd+key shortcut; old resolveRightKeyPressed fallback removed), activeInputController tracking, (3) all
  the [DIAG-BOMITGL] logging (diagLog file + currentInputSourceIDForDiag + flags/rCmd/IOKitty-HID/changeLayout/TIS/per-key
  k/mod/proc/act/comp/commit-str). Logs: bomi_toggle_diag.log + secure_input_trace.log (sampler pid 16366). Symptom status:
  toggle 씹힘 = FIXED for everything bomi receives (35/35, 39 wild rescues); residual no-trace misses = system-level (secure
  input) — sampler watching. "input floods at once" (Terminal) = NOT bomi (keys processed real-time, CPU 0.1%) = terminal render.
  Edge double-toggle = FIXED (asymmetric dedup). shortcut-while-toggle = fix attempt (return true). Safari 오타 (after inline
  OFF, WebKit→marked) = NOT reproducible, typing fine. NEXT/PENDING when user ready: CONSOLIDATE — keep IOKitty toggle fix,
  restore inline ON + force terminals→marked (design-intended, not global off), strip ALL diag, clean build + OSXTests gate.
  User declined consolidation for now (wants inline OFF + keep debugging). Revert map: git checkout InputController.swift +
  InputReceiver.swift + InputMethodServer.swift, re-apply inline-reclassify + IOKitty toggle fix only; re-enable inline in plist.
- **2026-06-25 (diag11 verified working; residual = bomi receives NOTHING → Secure Input hypothesis) — secure-input sampler running.**
  diag11 37-min log: **35 HID presses = 35 toggles = 35 TIS(ret=0), ZERO orphan HID, ZERO desync** (→han3final then keys comp
  false->true = Korean correctly). So the fix works for EVERY right-Cmd press bomi receives. User still reports "한영전환 계속
  안됨" → those failures leave NO trace in bomi's log at all (no HID, no flags) = the press reaches NEITHER bomi's IOHID monitor
  NOR the NSEvent path → bomi is blind, can't rescue from inside. LEADING HYPOTHESIS: Secure Event Input ON in the failing
  terminal/TUI moment blocks IOKitty AND right-Cmd flagsChanged (refocus-fixes-it fits). To confirm without burdening the user
  (who naturally retypes): background sampler `scratchpad/secure_input_sampler.sh` (pid 16366) logs secure-input state CHANGES +
  holding app to `~/Library/Containers/.../Data/secure_input_trace.log`. On next failure → correlate failure time vs trace: if
  SECURE_ON → confirmed system-level (bomi can't get event under secure input; Ctrl+Opt+Space is the reliable fallback; or find
  which app holds secure input). If secure_off at failure → different cause, dig further. diag11 + sampler both running; logging
  continues per user request. Clean build + OSXTests gate still pending final toggle sign-off.
  2-day diag10 log verification: 1521 toggles, **39 IOKitty-RESCUED** (HID press, no flagsChanged within 0.3s = the fix firing
  in the wild, all post-06-23). Toggle reliability problem SOLVED. BUT user reported BCT "한영 전환해도 영어만 입력" =
  double-toggle: HID→rcmdY gap median 7ms / p95 20ms / **max 156ms once**, and the 0.1s symmetric debounce let that 1 lagged
  flagsChanged through → single tap toggled twice → back to English. (Most "doubles within 0.5s" were actually 2 separate user
  taps; true single-tap-double = 1 in 2 days.) FIX (diag11, pid 20056 @ 05:27): asymmetric dedup in performRightToggle(viaHID:):
  HID authoritative (every tap toggles, 0.05s hw-double guard only); flagsChanged DEFERS if a HID press happened ≤0.4s ago
  (covers the 156ms lag w/ margin) and only toggles itself when HID is silent (Secure Event Input). Fast intentional re-taps
  (≥150ms) still all toggle via HID. ALSO removed the obsolete `resolveRightKeyPressed` IOKitty fallback (was a stale-flag
  source of 2nd toggle when release flagsChanged wasn't delivered). Files: InputController.performRightToggle(viaHID:) +
  lastHidRightPressUptime; flagsChanged path viaHID:false; fallback block deleted. InputMethodServer IOKitty callback viaHID:true.
  NEXT: user validates diag11 (rescue still works + no more double); then OSXTests regression gate + clean build.
- **2026-06-23 (ROOT CAUSE CONFIRMED via user 10-click test) — flagsChanged not delivered; HID(IOKitty) is. FIX = toggle from IOKitty.**
  diag9 log 05:59:02–10: user pressed right-Cmd ~25× in Terminal → EVERY press logged as `IOKitty HID rightToggle pressed=true/
  false`, but ZERO `flags kc=54`/`rCmd`/`TIS` in that window → flagsChanged (NSEvent the toggle depends on) was NOT delivered to
  the IME at all. At 05:59:14 flagsChanged finally arrived → toggle worked. So: keypress reaches bomi via HID every time, but the
  flagsChanged/IMK handle() path intermittently doesn't deliver right-Cmd (Secure Input was OFF, so not secure-input; possibly
  IME session idle / focus e.g. iPhone Mirroring frontmost earlier). FIX being implemented: drive the toggle from IOKitty's HID
  callback (reliable, on main runloop) via `InputMethodServer.activeInputController?.performRightToggle()`, debounced (static
  lastRightToggleUptime, 0.1s) so the same physical tap's HID-press + flagsChanged-press (~5ms apart) toggle only once. Keep
  flagsChanged path for Secure-Input case (IOKitty blocked there). Files: InputController (performRightToggle + activeController
  tracking in activate/deactivate + route flagsChanged toggle through it), InputMethodServer (weak activeInputController + IOKitty
  callback calls performRightToggle on press). Build keeps diag logging to VERIFY, then clean build after confirm.
- **2026-06-22 (diag9) — toggle miss confirmed = right-Cmd press not reaching IME's flagsChanged. Testing IOKitty HID rescue.**
  diag8 full-log scan: 105 tap-clusters, 104 had pressed=Y, ALL TIS ret=0 with correct src alternation → **toggle works 100%
  when the press reaches the IME** (e.g. 11:43:26 Terminal system→han3final OK). The 씹힘 = some right-Cmd presses produce NO
  `flags kc=54`/`rCmd` at all = not delivered to IME. Secure Event Input was OFF at the time, so it's not (only) secure-input.
  Frontmost app showed "iPhone Mirroring" at one check (possible event grabber?). HYPOTHESIS for fix: bomi's IOKitty
  (IOHIDManager, InputMethodServer.swift, callback on main runloop) is a SEPARATE HID-level stream; if it catches the presses
  that flagsChanged misses, we can toggle directly from it. BUT current code only consumes IOKitty's rightKeyPressed flag
  INSIDE the flagsChanged handler (gated on a flagsChanged arriving) → useless when no flagsChanged comes. diag9 adds
  `IOKitty HID rightToggle pressed=` log to compare HID vs flagsChanged delivery. NEXT: controlled test (tap right-Cmd N times,
  count switches) → if HID logs presses that flagsChanged missed → implement direct-toggle-from-IOKitty (main-thread, with
  dedup vs flagsChanged path to avoid double-toggle). diag9 pid 75347 @ 11:46. SAFE logging (no off-main TIS). Revert: git
  checkout 2 files + re-apply inline-reclassify; InputMethodServer.swift also has 1 diag line now (git checkout it too).
- **2026-06-22 (REOPENED) — toggle 씹힘 recurs on CLEAN 1.15.2 (no crash, IME healthy 1h49m). REAL bug, not crash artifact.**
  User: "한영 토글이 안 됨" on clean build (no .ips since 07:23, pid stable). So a genuine intermittent toggle miss exists
  independent of my old diag-crash. Redeployed SAFE logging diag8 (pid 49978 @ 10:28) — CRASH-FREE: all TIS/client values
  precomputed on MAIN thread, only primitives/Strings inside diagLog's bg autoclosure (audited; see [[bomi-tis-main-thread-only]]).
  Logs (file bomi_toggle_diag.log): `flags kc/chg/cur` (every flagsChanged — does rCmd reach IME?), `rCmd pressed/chg/cur/prev/
  bundle/src` (precomputed src+bundle), `changeLayout`, `TIS cached|fresh|FALLBACK target/before/ret`, per-key `key k/proc/act/
  comp`. DETECTORS for the miss: (a) right-Cmd tap with NO flags kc=54 = press never reached IME (system delivery gap); (b)
  rCmd pressed=Y + TIS ret=0 to target X but NEXT event src!=X = TIS silent no-op; (c) per-key comp shows user typing in wrong
  mode after a toggle. NOTE prior clean-log analysis: 65/65 toggles that REACHED the IME fired correctly → miss is most likely
  (a) delivery gap. AWAITING repro on diag8 → auto-scan log (don't need exact user timing). All diag UNCOMMITTED; revert via
  git checkout + re-apply inline-reclassify (InputController +22/-1, InputReceiver +6) as before.
- **2026-06-22 (was RESOLVED, now reopened) — clean stable 1.15.2 installed (pid 22511 @ 08:26, no logging, BOMITGL=0).** All my diag code removed
  via `git checkout` of both files + re-applied ONLY the pre-session inline-reclassify (working tree now == pre-session state:
  InputController +22/-1, InputReceiver +6, verified no diag remnants). Diag log files deleted. The toggle-crash (off-main TIS
  in my diag) is gone because that code never existed in real bomi. NET on real bomi this session: ZERO code changes (inline-
  reclassify remains uncommitted WIP, unchanged from session start). Remaining real/open: rare original toggle 씹힘 (system-
  level press-delivery gap, not bomi logic — 65/65 toggles worked in logs) + Edge dup was NOT reproduced (202/202 commits clean)
  → both likely were crash artifacts. If a symptom recurs on clean 1.15.2, re-instrument with SAFE (main-thread-only) file
  logging — NEVER call TIS/client APIs inside diagLog's @autoclosure (runs on bg queue → off-main → SIGABRT). 
- **2026-06-22 (DEFINITIVE) — the cascade of symptoms was MY DIAG CRASHING THE IME, not bomi bugs. Clean-build resolution.**
  After diag7 crash fix, analyzed full `bomi_toggle_diag.log`: (a) **65/65 right-Cmd tap-clusters fired a correct toggle**
  (pressed=Y→changeLayout→TIS ret=0→src switched); ZERO clusters with cmd-activity-but-no-press. Toggle detect+action logic
  is FLAWLESS. (b) **202/202 Edge commits are clean single syllables, ZERO back-to-back dups.** So the reported 토글 씹힘 +
  Edge 마지막단어중복 + Terminal 입력불가 + 첫글자 드롭 do NOT appear as IME-side bugs in clean (post-crash-fix) logs →
  overwhelmingly CRASH ARTIFACTS of my diag (currentInputSourceIDForDiag off-main TIS in diag2–6 crashing on toggle).
  Observed but harmless: right-Cmd taps emit DUPLICATE flagsChanged (chg=0 cur=cmd ~11ms after the real press), heavy in
  Edge/1Password/ScreenContinuity — current `(changed&cmd)&&(current&cmd)` press-detect handles them fine (real press fires
  first). Theoretical residual miss only if a RELEASE flagsChanged is dropped (stale lastFlags) — NOT observed (0 orphan
  releases). Original pre-session 씹힘 (1.15.1, no diag, no crash) is real but RARE (not in 65 taps) → likely system-level
  event-delivery gap (press never reaches IME = invisible to IME log), not bomi logic. PLAN: remove ALL my diag code → clean
  stable build; keep pre-existing inert inline-reclassify (user's uncommitted, never fired since bundleID always present).
  If a symptom truly recurs on clean build, re-instrument with the SAFE (main-thread-only) logging. Diag arc:
  diag2–6 crashed on toggle (off-main TIS); diag7 fixed it (precompute srcDiag/bundleDiag on main).
- **2026-06-22 — ROOT CAUSE of "한영 전환 안됨": MY DIAG BUILD CRASHED THE IME ON TOGGLE. FIXED in diag7.**
  Caught live: user "지금 한영 전환 안됨" + "다른 곳 포커스 갔다 오면 정상" = classic IME-crash + IMK-relaunch signature.
  Crash reports (~/Library/Logs/DiagnosticReports/bomi-input-*.ips) BOTH ver=1.15.2-diag6: **SIGABRT, HIToolbox: "TIS/TSM
  API is being called in two threads concurrently ... must call on main thread."** Stack: abort → TSMCurrentKeyboardInput
  SourceRefCreate → GureumCore.currentInputSourceIDForDiag() → selectInputSourceFast → InputReceiver.input(event:). CAUSE:
  my rCmd diag log `src=\(currentInputSourceIDForDiag())` was INSIDE diagLog's `@autoclosure @escaping`, which runs on the
  background diagLogQueue → called TIS (TISCopyCurrentKeyboardInputSource) OFF-MAIN, racing the main-thread TIS calls in
  selectInputSourceFast on every toggle → SIGABRT. So diag2–6 (all file-logging builds) crashed the IME on toggle; MANY
  "씹힘/입력불가/첫글자 드롭" reports during diag are likely CRASH ARTIFACTS, not separate bugs. FIX (diag7, pid 4289 @ 07:27):
  precompute srcDiag + bundleDiag on MAIN thread in the rCmd branch, pass strings to diagLog. Audited all diagLog calls: only
  rCmd had off-main TIS/client access; activate/reclassify/commit/key/changeLayout all precompute on main. NEXT: user re-tests
  toggle on diag7 (must NOT crash); monitor .ips for new crashes; then see which symptoms (Edge dup likely real & separate)
  actually persist on a STABLE build. Original pre-diag "씹힘" (1.15.1, no diag code) is a separate open question — 1.15.1 had
  no off-main TIS so not this crash.
- **2026-06-21 — 한/영 토글 "씹힘" 조사 (open).** Symptom (user): 한/영 toggle intermittently dropped.
  Narrowed via on-device evidence: running IME = framework GureumCore mtime 06-19 10:42 → DOES contain the TIS fast-toggle
  fix (nm confirms `_TISSelectInputSource`/`_TISCreateInputSourceList` + `selectInputSourceFast` symbol present; my first
  check looked at the WRONG binary — main app exe `bomi_input` module, engine lives in GureumCore.framework). So 씹힘 happens
  WITH TIS toggle live. RightToggleKey=231 (right-Cmd, kVK=54). Both toggle targets (han3final Korean, system English) are
  ENABLED system input sources → "slow selectMode fallback every time" hypothesis FALSIFIED. User answers: (1) symptom =
  menubar 한/A icon does NOT change (switch never happens; not desync, not 1s-slow), (2) app-specific = **Terminal**, bomi
  active. Prior verified fact: right-Cmd keyCode=54 DOES reach IME in Terminal even under Secure Event Input. LEADING
  HYPOTHESIS: under Terminal's Secure Event Input, `TISSelectInputSource` intermittently no-ops but returns noErr → code
  thinks it succeeded, never falls back to selectMode → composer flips but system source doesn't → icon unchanged = 씹힘
  (worse with cached ref). NEW since selectMode→TIS change (6eb3d48/41e595d). NEXT: behavior-preserving NSLog diag build
  (tag BOMITGL) logs flagsChanged detect + changeLayout action + TISSelectInputSource ret code + current-source before, to
  confirm detect-drop vs TIS-no-op. Diag is UNCOMMITTED (InputController+InputReceiver) — also note pre-existing uncommitted
  inline-diag reclassify changes in those files (inlineCompositionEnabled=true). `git checkout` all before any commit.
  **STATUS 2026-06-22: FILE-LOGGING DIAG BUILD LIVE + VERIFIED.** NSLog is `<private>`-redacted in unified log → switched to
  FILE logging: `diagLog()` appends to `~/Library/Containers/com.yoropico.inputmethod.bomi-input/Data/bomi_toggle_diag.log`
  (survives IME restart/reboot; tag fields). Build `1.15.2-diag2` installed+running (pid 81622 @ 05:04). Logs: (a) every
  flagsChanged compact `flags kc/chg/cur`, (b) rich `rCmd kc=.. pressed=Y/N chg/cur/prev bundle src` on right-Cmd events,
  (c) `changeLayout .. action=`, (d) `TIS cached|fresh|FALLBACK target before ret`. KEY: the NEXT event's `src=` field reveals
  if the prior TIS switch actually took effect. Baseline GOOD toggle captured (system→han3final, ret=0, next src=han3final).
  Failure signatures documented in chat. AWAITING user repro of 씹힘 → read log tail → confirm F1(detect-drop)/F2(TIS-noop)/
  fallback/event-missing → fix. User wants logging left ON continuously.
  **STATUS 2026-06-22 b: TOGGLE 씹힘 NOT yet reproduced in logs — ALL captured toggles SUCCEEDED** (pressed=Y→changeLayout→TIS
  ret=0, next src= switched; no FALLBACK/desync). User then reported 2 NEW symptoms: (2) Terminal/SSH "입력 안됨", (3) Edge
  "마지막 단어 중복". Added classification diag (diag3): activate logs bundle/apple-signal/term/selQ/useMarked/needsReclassify;
  per-key `key-INLINE` (only when useMarked=false); reclassify fire. **DECISIVE NEGATIVE: classification is CORRECT — Edge(23)/
  Terminal(11)/bct(8) activations ALL useMarked=true; ZERO useMarked=false; only com.apple.mail hit key-INLINE. So inline-
  misclassification theory is DEAD for Edge/Terminal.** => Edge dup + Terminal input-fail are MARKED-path bugs, NOT inline, and
  pre-existing in 1.15.1 (my diag adds only logging + inert reclassify; marked path == inline-off behavior when useMarked=true).
  Edge dup leading hypothesis: Chromium marked commit — `commitCompositionEvent` inserts via `insertText(commitString,
  replacementRange: selectionRange())` (NSNotFound when sel len 0); if Chromium doesn't replace active marked text → last
  syllable duplicated. diag4 LIVE (pid 29731 @ 06:47): logs `commit str= sel= marked= bundle=` at each commit. AWAITING Edge
  repro with known word (e.g. "안녕 안녕") → read `grep commit.*edge` → see if marked range non-empty/insert doesn't replace.
  NOTE 69efde9 (NFC marked preedit) already shipped to address Terminal ghost; Edge is a browser so different mechanism (real
  double-commit, not NFD/NFC cell ghost).
  **STATUS 2026-06-22 c: 4th symptom + COMPREHENSIVE diag build diag6 LIVE (pid 54126 @ 06:57).** 4 symptoms now tracked:
  (1) 토글 씹힘 — NOT yet repro'd (all logged toggles OK); (2) Terminal/SSH 입력 안됨; (3) Edge 마지막단어 중복; (4) 랜덤
  첫글자 씹힘 (= worklog's deferred "first-roman-leak" family). All 4 are base/marked-path (classification confirmed correct),
  independent of inline-on. diag6 logging (file `bomi_toggle_diag.log`, old rotated to .diag1-4.bak): `flags`/`rCmd` (toggle),
  `activate` (classify breakdown), `changeLayout`/`TIS` (toggle action), `commit str/sel/marked` (Edge dup), `key k/proc/act/
  comp` per char key (first-char drop + Terminal). IMPORTANT: per-key log does NOT call client IPC (no bundleIdentifier per
  key) — avoid latency/timing contamination of the timing-sensitive first-char bug; app context read from preceding activate.
  Signatures: ① rCmd pressed=Y w/o TIS+src-switch or prev has stale cmd bit; ② Terminal key proc/comp not progressing; ③ commit
  marked!=empty not replaced; ④ activate then key proc=Y act=none comp false->false. AWAITING user repro (symptom+time+app);
  Edge best with known word "안녕 안녕". Then ONE comprehensive log analysis across all 4. All diag UNCOMMITTED; git checkout
  InputController.swift+InputReceiver.swift before any commit. Builds: diag(NSLog,private-redacted)→diag2(file)→diag3(classify)
  →diag4(commit)→diag5(per-key+bundle IPC, superseded)→diag6(per-key no IPC, CURRENT).
- **2026-06-18 — secure-input 한/영 토글 REAL FIX shipped + committed `db07625`: detect via flagsChanged keyCode.**
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
