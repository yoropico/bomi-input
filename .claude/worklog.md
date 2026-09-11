# Bomi IME — Worklog

Append one line per decision (the WHY). Newest at bottom.

## 2026-07-14 — Brainstorming & design

- **IMK as base API**: only official macOS IME API, not deprecated on macOS 26; CGEventTap can't render preedit and breaks in secure fields → unusable for Hangul composition.
- **Pure-Swift automaton** (not libhangul embed): zero deps, license-free, Swift6/macOS26 native, full NFC control; libhangul kept only as reference + test oracle.
- **Sebeolsik-final (`3f`) first**: user's daily layout; separate cho/jung/jong keys → clean automaton, no 도깨비불 (jong never migrates to next cho).
- **In-IME han/eng toggle** (Gureum-style), default Right Command, per-app memory: consistent feel across apps.
- **Per-syllable immediate commit** (not eojeol-keep): matches Apple/Gureum feel, robust in hard apps (long preedit would break Terminal/Electron).
- **SwiftPM + assembly script** (not Xcode project): CLI/git-friendly, keeps Engine a clean pure module.
- **Automaton data** taken verbatim from libhangul `3f` keymap + `combination-default` (see spec Appendix A/B) — ingest, don't invent.
- **Research note**: parallel research workflow partially failed (sebeolsik finder hit StructuredOutput retry cap; two finders returned dummy). Recovered by fetching libhangul source directly for the authoritative mapping.
- **Spec approved**: `docs/superpowers/specs/2026-07-14-bomi-sebeolsik-ime-design.md`. Build order puts a minimal "does IMK load on macOS 26" spike first (highest risk), before the automaton.
- **Implementation plan written**: `docs/superpowers/plans/2026-07-14-bomi-sebeolsik-ime.md` — 11 tasks, TDD, full Swift code inline. Automaton is a verbatim port of libhangul `hangul_ic_process_jaso` (fetched from source, not invented). Concurrency approach fixed: `.defaultIsolation(MainActor.self)` on the app target; Engine target stays pure/non-isolated.

## 2026-07-14 — Implementation (SDD, branch `sebeolsik-mvp`)

- **Task 1 (IMK load spike) done**: SwiftPM bundle compiles clean on Swift 6.3, assembles + installs to `~/Library/Input Methods`. `.defaultIsolation(MainActor.self)` alone was insufficient — needed `nonisolated` on `handle`/`init` + `MainActor.assumeIsolated` with an `@unchecked Sendable` box (IMK ships no `@MainActor` overlay). Review caught a Critical (empty `Tests/BomiEngineTests` dir untracked → fresh-checkout build failure); fixed with `.gitkeep` (219faff), verified via `git archive` clean-build. **GUI verification (add input source + type in TextEdit) still pending the user.** Minor follow-ups deferred to final review: `main.swift` force-unwraps, `codesign --deep` no-op.

## 2026-07-14 — Task 1: IMK load spike

- **Builds clean** on Swift 6.3.3 / Xcode 26.6 / macOS 26.5.2 with `.defaultIsolation(MainActor.self)`, but `BomiInputController` needed extra concurrency bridging beyond the brief's snippet: `init()`, `init(server:delegate:client:)`, and `handle(_:client:)` all had to be marked `nonisolated` (they override `nonisolated` ObjC declarations), and `handle`'s body hops to `MainActor.assumeIsolated { }` to call `insertText`. Sending the non-`Sendable` `sender: Any!` into that closure additionally required a small `nonisolated`, `@unchecked Sendable` box type — plain `MainActor.assumeIsolated { }` alone wasn't enough to satisfy Swift 6's region-based "sending" check. Confirms spec §10.1 risk was real, and the escalation path the brief allowed (nonisolated override + assumeIsolated bridge) was sufficient without changing the tools-version or the overall isolation strategy.
- Also had to `mkdir -p Tests/BomiEngineTests` (empty) — `swift build` errors on the declared `BomiEngineTests` test target with "overlapping sources" if that directory doesn't exist yet; Task 2 will populate it.
- `swift build -c release`, `./Scripts/assemble-app.sh`, `./Scripts/install.sh` all succeed. `Bomi.app` is adhoc-codesigned, installs identically to `~/Library/Input Methods/Bomi.app`, and the standalone binary launches and stays alive (IMKServer registration doesn't crash) when run directly from the terminal.
- **Not yet verified** (needs interactive GUI/login session, handed to the human): adding Bomi in System Settings > Keyboard > Input Sources, switching to it, and typing in TextEdit to confirm `보미` commits on keypress.

## 2026-07-14 — Tasks 7-11: IMK integration layer (KeyTranslator, composition, toggle, menu, hardening)

- **Task 7 (KeyTranslator)**: US-ANSI keyCode->3f ASCII table, verbatim from brief. Builds clean, no concurrency concerns (pure enum, no IMK overrides).
- **Task 8 (wire automaton into controller)**: merged the plan's composition logic (`showPreedit`/`commit`/`flush`/`handleKeyEvent`) into the *actual* Task-1 concurrency scaffolding rather than the plan's idealized plain-MainActor version. `commitComposition` and `deactivateServer` also override `nonisolated` ObjC declarations (same as `handle`/`init` from Task 1) — Swift 6 rejected them as implicitly MainActor-isolated overrides; fixed with the same `nonisolated override` + `MainActor.assumeIsolated { }` + `UncheckedSendableBox` bridge. `event.keyCode`/`event.modifierFlags` (Sendable value types) are extracted *before* entering `assumeIsolated`, so only the non-Sendable `sender`/`self` needed boxing — `self` itself crossed into the closure without a box (last-use "sending" was accepted by the compiler for `self`, unlike the ObjC `sender` parameter in Task 1).
- **Task 9 (han/eng toggle + per-app memory)**: `Preferences`/`LanguageMode` are plain classes, no isolation surprises. `recognizedEvents` and `activateServer` also override `nonisolated` ObjC declarations — same nonisolated+assumeIsolated pattern applied preemptively and it compiled first try. `handle` now branches on `event.type` (`.flagsChanged` -> toggle logic, `.keyDown` -> composition), both still routed through one `UncheckedSendableBox`-wrapped `sender`.
- **Task 10 (input-source menu)**: `menu()` also overrides a `nonisolated` ObjC declaration. New wrinkle: the *return value* `NSMenu` isn't `Sendable` either (`@_nonSendable(_assumed)`), so returning it straight out of `MainActor.assumeIsolated { }` failed the same "sending" check as parameters — fixed by boxing the *result* in `UncheckedSendableBox<NSMenu>` too, unboxing after the closure. Extended `MenuBuilder` beyond the brief's literal code block to match its own "Produces" bullet list (added the disabled "toggle key: Right Command" info item and the disabled "환경설정…" no-op item) since the prose spec enumerated them but the code snippet omitted them.
- **Task 11 (hardening)**: Step 1 (test matrix) and Step 3 (Electron marked-text fallback) require an interactive GUI session this environment doesn't have — documented as manual steps in README.md instead of guessed at. Step 2 (flush wired on both `commitComposition`/`deactivateServer`) verified already correct by inspection, no change needed. Step 3's conditional fallback (`canMark`) intentionally *not* added speculatively — no observed garbled-preedit defect to fix; left as a documented follow-up gated on the human's manual test. Step 4 (oracle cross-check): ran a **temporary, uncommitted** test pass cross-checking all 14 reachable choseong x jung=ㅏ, all 14 reachable jungseong x cho=ㄱ, and all 27 reachable jongseong x "가" base (55 codepoints total) against the canonical Unicode Hangul formula `S = 0xAC00 + (cho*21+jung)*28+jong`, independent of the engine's own `Jamo`/`Syllable` index math. Zero divergences — reverted the temp test additions afterward since Task 11's file scope didn't include test-file changes. `swift test` still 15/15 after revert. Step 5: wrote `README.md` (build/install/architecture + the full manual GUI verification checklist for the human).
- **GUI verification for Tasks 8-11 (composition, backspace, toggle, per-app memory, menu, hard-app behavior) is entirely pending the human** — see README.md "Manual verification" section for the exact steps.

## 2026-07-14 — IMK-layer re-review + fixes (commit b6c8f3d)

- **Re-review** (fresh reviewer, e079230..46db7e0): chord-toggle fix (46db7e0) is logically correct and well-placed. Two substantive findings survived verification against spec/plan, chosen for fixing over deferral:
- **Per-app memory was a real spec violation, root-caused to the plan.** Spec §6.5 requires the `bundleId→mode` map (and global) in `UserDefaults` and restored in `activateServer`; plan Task 9 supplied an *in-memory* `LanguageMode` code block, which the implementer followed verbatim. Consequence: state lost on restart AND — since IMK creates one controller per client — not shared across apps, so the headline "each app remembers its mode" feature didn't work. **Fix: move storage to `UserDefaults`.** No singleton needed — the store is already process-wide + persisted, so distinct `LanguageMode` instances converge for free. This is why the fix is "change the backing store," not "add a shared instance."
- **Made the app layer testable (was the reason #2/#4 could only be manually checked).** Pure logic (`KeyTranslator`/`LanguageMode`/`Preferences`/new `ToggleGate`) split out of the executable target into a `BomiCore` library target so `swift test` can `@testable import` it — an executableTarget with top-level `main` can't be. +12 tests; total 27/27.
- **Toggle logic extracted to a pure `ToggleGate` value type** (TDD): fixes #4 (a pre-held Shift/Ctrl/Opt no longer arms a spurious toggle) and makes the whole down→up/chord state machine unit-testable without IMK.
- **Minor #5/#6/#7** folded in: flush composer on commit/deactivate even when the client cast is nil; passthrough set → `static let`; `Preferences.toggleKeyCode` via `UInt16(exactly:) ?? 0x36` (no trap on a bad stored value).
- **Still open, on-device only:** re-review Important #1 — AppKit `performKeyEquivalent` may consume a menu-shortcut keyDown (Right-Cmd+C) before it reaches `handle()`, in which case `chordInterrupt()` never runs and the toggle could still fire on release. Logic is correct *if* the keyDown is delivered; confirm via README manual step 4. This is the last item gating "chord bug fixed."

## 2026-07-14 — Bundle rebrand + localized display name (commit 02bdec1)

- **GUI-check finding:** the input-source list showed the raw mode identifier (`com.rsautomation.inputmethod.bomi.korean`) — two causes: (1) no `*.lproj/InfoPlist.strings`, so macOS falls back to the mode key; (2) the company domain was baked into the id. User asked to drop `rsautomation`.
- **Fix:** rebranded id/connection/mode-key/TISInputSourceID to `com.bomi.inputmethod` (single string replace covered all — suffixes `.korean`/`_Connection` preserved). Added `en`/`ko` `InfoPlist.strings` mapping the mode key to `Bomi`/`보미`; `assemble-app.sh` now copies `*.lproj` into the bundle (verified present after assemble). Docs (spec/plan/README) updated. `swift test` still 27/27 (no Swift code touched).
- **Note for verification:** macOS caches input-source registration + localized names, so a bundle-id change + new localization needs a log-out/in (or reboot) to show up; the old `com.rsautomation.*` source may need removing from Input Sources first.

## 2026-07-14 — HARD-WON: bundle id must not END in "inputmethod" (commit 80aeaaa)

- **Symptom chain:** raw mode-key label -> blank label -> input source vanished entirely after logout/login. The blank-label stage was a **stale TIS cache row**; the logout/login that was supposed to "fix the label" actually revealed the truth — the bundle was never registered.
- **Root cause (confirmed, not guessed):** a TIS probe (`TISCreateInputSourceList` + `kTISPropertyLocalizedName`, run over all 318 installed sources) found **zero** sources for our bundle. macOS registers an input method only if its bundle id has a **name component AFTER `inputmethod`** — i.e. `com.<vendor>.inputmethod.<name>`. `com.bomi.inputmethod` (ending in `inputmethod`) is silently ignored: no registration, no console log, nothing.
- **Evidence for the rule:** every working IME on the box matches it — Apple `com.apple.inputmethod.Ainu`, the Gureum fork `com.yoropico.inputmethod.bomi-input`, and our own pre-rebrand `com.rsautomation.inputmethod.bomi` (which DID register). Rebranding away from the company domain accidentally deleted the trailing name component as well.
- **Fix:** `com.bomi.inputmethod.bomi` (+ connection name, mode key, TISInputSourceID, InfoPlist.strings keys). Probe now: registered, `Enabled=true`, `SelectCapable=true`, `LocalizedName="Bomi"`. User confirms it shows in Input Sources.
- **Method note:** the TIS probe is the tool that ended a guess-loop — when the GUI lies (stale cache), query the API that the GUI reads. Keep `tis-probe.swift` in mind for any future input-source debugging.
- **Localization (settled):** `Resources/<lang>.lproj/InfoPlist.strings` maps the **mode key** to the display name, plus `CFBundleName`/`CFBundleDisplayName`. Verified against the Gureum fork's own strings file. `assemble-app.sh` copies `*.lproj` into the bundle.

## 2026-07-14 — Han/Eng via system input modes (spec 876993c, plan d20aed6, impl a621738..07669b5)

- **Why the redesign:** the menu bar can't show Han/Eng with our old design at all. The indicator is driven by which input SOURCE is active, not by IME-internal state — so a single mode + a `korean` boolean could never move it, no matter what icon we shipped. Confirmed by reading Gureum (`OSXCore/InputReceiver.swift`), whose own comment says `TISSelectInputSource` is what makes the menu-bar 한/A icon refresh.
- **Design:** declare TWO input modes (`…bomi.korean` ko / `…bomi.roman` en), switch the system input source on a bare Right-Command tap. **Keeping our own Roman mode is load-bearing** — switching to system ABC would deactivate our IME, so Right-Command would never reach us again and the toggle would be one-way. Gureum keeps its own `.system` Roman mode for exactly this reason.
- **Source of truth moved to macOS.** `mode` changes only in `setValue(forTag: kTextServiceInputModePropertyTag)`; the toggle does NOT set it optimistically (two sources of truth would drift). Consequence: `LanguageMode` (the UserDefaults per-app state fixed earlier today) is **deleted** — per-app memory is macOS's job now. Ironic but correct: the earlier fix was right for the old architecture, and the architecture was wrong.
- **Icons** taken from the user's own Gureum fork: `statusbomi_han` (ㅂ) / `statusbomi_eng` (B) for the modes, `bomi-input.png` for the input method. Gureum points Menu/AlternateMenu/Palette at the same light PNG per mode; we do the same (dark variants deliberately out of scope).
- Gate green throughout: 27/27 (LanguageMode's 3 tests replaced by InputMode's 3).
- **Pending:** logout/login so the new Roman mode registers, then the manual matrix (menu bar flips ㅂ↔B both ways, mid-syllable toggle commits, Right-Cmd+C does not toggle).

## 2026-07-14 — HARD-WON #2: the toggle must fire on PRESS, not release (commit 8612611)

First real on-device test of the Right-Cmd toggle failed ("한글 입력 중 한영변환이 안됨", then "안 되는 경우가 발생"). Our whole down→arm/up→fire model was wrong. All three fixes were read off Gureum's `OSXCore/InputMethodServer.swift` (§"Right toggle key detection"), which had already solved each one on-device — do not re-derive these:

1. **Fire on PRESS (0→1 transition of the modifier bit), never on release.** The toggle switches the input source, and *that switch makes the following key-up get delivered to a different controller* — it never comes back to us. A release-based toggle therefore leaves the command bit stuck "down" in the accumulated flags, so every later press cancels out as "no transition" and the toggle is silently eaten. **Symptom: Right-Cmd does nothing, only refocusing the field recovers.** Exactly what the user saw.
2. **Debounce duplicate presses (80ms).** The source switch — and Chromium-based apps (Edge etc., 2–11ms apart) — emit TWO `flagsChanged` presses for ONE physical press. Toggling on both flips 한→영→한, which reads as "the toggle intermittently does nothing" (and explains why it works in some apps/fields and not others).
3. **Reset the modifier tracker on BOTH the fire and the suppress path**, and on activate/deactivate/mode change. Resetting only on fire (and forgetting the suppress path) re-introduces the wedge.

- **Left/right modifiers:** `modifierFlags` carries NO left/right information to an IME (device-dependent `NX_DEVICER*KEYMASK` bits never arrive; only the device-independent `.command` bit). The `flagsChanged` **keyCode** does carry it (Right-Command = 0x36) and survives Secure Event Input. Key off keyCode, never off flags.
- **Consequence, accepted:** Right-Command is now a dedicated Han/Eng key — `Right-Cmd+C` toggles, because it fires on press. Use LEFT Command for shortcuts. Inherent to using a modifier as the toggle key; Gureum behaves the same. This retires the earlier code-review finding "Right-Cmd+C must not toggle" — that requirement is incompatible with a working toggle.
- `ToggleGate` rewritten as a pure `ModifierFlagsTracker` + press detection + debounce; the wedge and duplicate-press cases are now unit tests. Gate 28/28.

- **Also settled (asked during testing): a SINGLE input mode cannot show Han/Eng in the menu bar.** The InputMethodKit headers expose no icon/image/menu-bar API at all — the menu-bar icon is the *active input source's* Info.plist icon, fixed at registration. Hence two modes (보미 / 보미 로마자). The only alternative, a self-drawn `NSStatusItem`, would leave the system icon showing anyway (two icons) and was already excluded by the spec (macOS 26 NSWindow leak).

## 2026-07-14 — THE actual toggle bug: IMK's setValue is unreliable (commit cd5c6af) ✅ WORKS

The press-model rewrite (8612611) did NOT fix it; the toggle still died. Two of my hypotheses (release-vs-press, Secure Event Input) were **wrong**. What settled it was instrumenting the IME and reading its own event log — and note: **`NSLog`/os_log shows NOTHING for this background IME process**, so the debug build wrote straight to `/tmp/bomi-debug.log`. That file ended the guess-loop.

What the log showed:

```
fire mode=korean -> select ok=true (current=roman)  -> setValue(roman) ARRIVES
fire mode=roman  -> select ok=true (current=korean) -> setValue NEVER ARRIVES
fire mode=roman  <- STILL roman -> re-selects korean, already active -> nothing happens
```

- **`TISSelectInputSource` is fine** and the switch really happens (proved by reading the current source back; `secure=false` even in Terminal — the Secure-Event-Input theory was wrong).
- **The bug: IMK delivers `setValue(forTag: kTextServiceInputModePropertyTag)` for korean→roman but NOT for roman→korean.** Our `mode` was updated *only* from `setValue`, so it stuck on the stale value permanently; every later toggle then re-selected the source that was already active. Dead toggle, no error anywhere.
- **Fix: TIS is the source of truth, not the IMK callback.** After switching, read the active source back (`ModeSwitcher.currentMode()`) and adopt it; `activateServer` does the same. `setValue` is now only a corroborating hint. The plan's rule "never update `mode` optimistically, wait for setValue" was itself the defect.
- On-device: 18/18 fires, 18/18 verified switches, korean↔roman 9/9 alternating, 0 fallbacks. User confirms it works. Gate 28/28.
- **Method note that generalizes:** when a system callback is the only thing you trust and the symptom is "nothing happens", verify the callback actually fires. Don't theorize — log the boundary. Also `TISSelectInputSource`'s return code alone is not proof; read the current source back.

## 2026-07-14 — Royal TSX rewrites Right-Cmd → Right-Option (commit 7ca2367) ✅

"한/영 전환이 안 되는 앱이 있음". Logging every `flagsChanged` **with its client bundle id** ended it in one round:

```
RoyalTSX                       : keyCode=61 (Right Option) x24,  keyCode=54 x0
Notes / Terminal / ScreenCont. : keyCode=54 (Right Command), normal
```

- **Royal TSX rewrites the physical modifier before the IME sees it** — a Right-Command press arrives as Right-Option. App-wide: the log above came from its own settings field with **no RDP session connected**, so this is not its documented "send Command as Alt to the remote host" feature.
- **This also explains why Gureum "just worked" there**: Gureum's default toggle key is `kHIDUsage_KeyboardRightAlt` (Right **Option**, Configuration.swift:113), so it accidentally matched the substituted key. Our default is Right Command — correct for the user, but it meant Royal TSX's substitution broke us where it silently helped Gureum.
- **Fix:** `Preferences.toggleKeyCode(forApp:)` maps key-rewriting apps to the code that actually arrives (`com.lemonmojo.RoyalTSX.App` → 0x3D). Applies **only** while the user is on the default Right-Command; a deliberately chosen toggle key is respected (tested).
- **My own misstep, recorded so it isn't repeated:** I first concluded "the user has always used Right-Option" from Gureum's default, and changed our default to match. Wrong — the user pressed Right-**Command** all along. Reading a config default is not evidence about what a person's fingers do. Ask, or measure the key that actually arrives per app.
- Verified: RoyalTSX 61 → fire → switch ok; Terminal 54 → fire → switch ok; 0 failures, 0 fallbacks. Gate 32/32.
2026-07-15 04:04 | [session end] reason=clear
2026-07-15 04:04 | [compact auto] context compacted at 4339e59
2026-07-15 04:04 | [session end] reason=other
2026-07-15 14:33 | [session end] reason=prompt_input_exit
2026-07-15 14:34 | [session end] reason=resume
2026-07-15 14:35 | [session end] reason=other
2026-07-16 13:54 | [session end] reason=other
2026-07-16 13:54 | [session end] reason=other
2026-07-16 13:58 | [session end] reason=other

## 2026-07-15 — toggle-fail-terminal: Han/Eng toggle wedges (investigation)

- **Symptom (user):** in Terminal, Right-Cmd sometimes does nothing at all — stuck in
  one language until the app is refocused. Also "the first letter is eaten when I switch
  han→eng while typing fast". Same bug, two faces.
- **Instrumentation is back, permanently.** `DebugLog` (Sources/Bomi/DebugLog.swift) writes
  to /tmp/bomi-debug.log, gated on `/tmp/bomi-debug.on` existing (read once at startup).
  os_log still shows NOTHING for this process; a file is the only way to see anything.
  Kept in-tree instead of re-adding it each time this breaks.
- **What the log proves:** in the wedged state, `keyDown` keeps arriving but `flagsChanged`
  does NOT — zero events, indefinitely. So the toggle never even gets a chance to run:
  this is NOT a ToggleGate/debounce bug. Refocusing the app (activateServer) restores it.
- **Also observed at the wedging FIRE:** IMK's `setValue` and the key-up `flagsChanged`
  both fail to arrive, whereas a healthy FIRE gets both within ~10-90ms. So the toggle's
  own input-source switch is what breaks the event routing.
- **Hypothesis killed (recorded so it isn't re-tried):** "toggling mid-composition (open
  marked-text session) wedges it". Gureum does close the session first
  (InputReceiver.swift:322 `cancelComposition()` → commit → `selectInputSourceFast`) and we
  do not — a real difference, worth fixing on its own — but a wedge was then observed with
  `preedit=''`, so an open marked session is NOT the cause.
- **Real difference vs Gureum, still unexplained:** their `recognizedEvents` asks for a much
  wider mask (`.keyDown, .flagsChanged, mouse up/down/dragged, .appKitDefined,
  .applicationDefined, .systemDefined`); ours asks for `.keyDown | .flagsChanged` only.
- **Next:** log now tags every line with the controller instance (IMK makes one per text
  client) and records every `recognizedEvents` call. Suspicion: the events go to an instance
  that never got the flagsChanged mask applied — which looks exactly like "no events at all".
- **Instance tagging paid off.** Every log line now carries the controller instance
  (IMK makes one per text client; a second Terminal window = a second instance).
  With it: of 12 FIREs, 11 got their key-up back in 60-85ms; exactly ONE was followed by
  that instance never seeing a flagsChanged again. So it is a race, not a deterministic
  path — which is why it reads as "sometimes the toggle just dies".
- **The contradiction that pointed at the cause:** after wedging, IMK still calls
  `recognizedEvents` on that same instance before every keyDown, and we still answer
  `.keyDown | .flagsChanged` — yet only keyDown is delivered. The mask is not the problem;
  the app-side IMK client has stopped *sending* modifier events to us.
- **Fix #1 (kept, but did NOT fix it):** move the input-source switch out of the
  `flagsChanged` callback (`DispatchQueue.main.async`). Switching TIS while IMK is still
  dispatching the event we are handling is wrong regardless, but the wedge recurred.
- **Fix #2 (under test):** never return `true` from a flagsChanged. Consuming a modifier
  event is what plausibly breaks the app-side modifier/session tracking, and a bare
  Right-Command does nothing in the app anyway, so there is nothing to consume. Gureum
  consumes it and — per the user — has the identical bug.
- **If #2 fails:** stop patching and question the architecture. Switching the system input
  source is the ONLY trigger for the wedge; the alternative is to keep one input source and
  hold Han/Eng as internal state (cost: the menu-bar ㅂ/B icon stops reflecting the mode).
- **Fix #2 REVERTED — it made things strictly worse.** Returning `false` from flagsChanged
  cost *every* FIRE its key-up, where before only ~1 in 12 lost it. Consuming the modifier
  event was never the problem. Both branches of the `switch` consume again, and the code
  says so at the `.suppressed` case so it isn't "simplified" back.
- **Fix #3 (the actual fix): switch via IMK's own `selectMode`, not `TISSelectInputSource`.**
  TIS replaces the active input source *behind IMK's back*, and IMK's per-client event
  routing is then left stale — the controller keeps getting `keyDown` but never another
  `flagsChanged`. `selectMode` is the same switch, announced, so routing stays coherent.
  Still deferred off the callback (`DispatchQueue.main.async`), and `mode` is set
  optimistically to the target because `selectMode` is asynchronous and the next keystroke
  can beat it.
- **The claim that made us avoid `selectMode` for weeks was never measured.** "It's a ~1
  second slow path" — `ModeSwitcher.pollUntilLanded` now times every switch. Real numbers
  over 2814 toggles: **min 1ms, p50 34ms, p95 42ms, max 67ms.** Nothing close to a second.
  Remembered performance folklore is not evidence; measure before designing around it.

## 2026-07-22 — toggle-fail-terminal: verification from 6 days of real use

- The build under test has been the installed IME since 2026-07-15 05:46 (source mtimes ==
  build time, so binary == this working tree). `/tmp/bomi-debug.log` covers **145 hours**.
- **2814 FIREs, 0 wedges.** Wedge test: after a FIRE, does that controller instance ever
  see another `flagsChanged` while keyDowns keep arriving? Zero instances where it did not.
- 0 `did NOT land`, 0 TIS fallbacks, 0 `DROPPED` (sender not IMKTextInput). 246 duplicate
  presses correctly suppressed.
- "First letter eaten on han→eng" is gone too: of 2744 first-keystroke-after-a-toggle cases,
  0 were handled in the pre-toggle mode (the single apparent hit was an app-switch in
  between, not a lost keystroke).
- Gate 32/32 green. `DebugLog` stays in-tree, off unless `/tmp/bomi-debug.on` exists — it is
  what proved every one of these numbers.
- **Landed** as d8cd3bc (merge --no-ff into main), gate 32/32 after the merge. Desk and
  branch removed; debug logging turned back off (`/tmp/bomi-debug.on` gone, IME restarted).
- **The spec-gate earned its keep here.** It blocked the merge because `Sources/` changed
  with no spec update — and the spec still said "`TISSelectInputSource` — the fast path"
  and "(Gureum notes `selectMode` alone is a ~1s slow path)". That second sentence, taken
  on faith from another project and never measured, is the whole reason this bug survived
  weeks of patching. The spec is corrected in place, with the measurement and an explicit
  do-not-reinstate note, so the next reader cannot re-derive the wrong design from it.

## 2026-07-22 — per-app coverage tooling (follow-up)

- **Why:** the fix was verified on TOTALS only (2814 toggles, 0 wedges) and then the log
  was deleted, so "which apps did those toggles actually cover?" became unanswerable. A
  green total across one app is not evidence about the others. Logging is back on and
  `Scripts/analyze-debug-log.py` now reports **per app**: toggles, wedges, suppressed
  duplicates, keystrokes, switch-landing p50/p95/max, and failures.
- **The tool is verified, not just written.** Its FIRE/wedge/landing logic was exercised
  against a fixture containing a real captured session plus an injected wedge, a
  `did NOT land`, a suppressed duplicate, and a typed-in-but-never-toggled app. All five
  cases were reported correctly; the wedge is reported with the log's own HH:MM:SS so it
  can be grepped for.
- **Correction to an earlier note: "IMK makes one controller per text client" is not quite
  right — instances are REUSED across apps.** Observed directly: instance `c401` served
  `com.yoropico.bct`, then `com.apple.dt.Xcode` after a focus change. So an instance tag
  does not identify an app, and `keyDown` lines carry no `app=` at all: the app must be
  carried forward from the last `activateServer`/`flagsChanged` on that instance, and any
  per-instance reasoning must break at activate/deactivate. The analyzer does both.
- Not yet answered: the per-app numbers themselves. The log is hours old; it needs days of
  ordinary use across Terminal/Royal TSX/browsers/Electron before it can say anything.
2026-07-22 07:17 | [session end] reason=other
2026-07-22 07:18 | [session end] reason=other
2026-07-22 07:20 | [session end] reason=other
- [ime-enabled-drop] Root cause of the "IME reverts to macOS default" reports: our own
  com.bomi.logsnapshot LaunchAgent ran `killall Bomi` when the /tmp debug switch vanished
  (/tmp reaper, 2026-07-28 06:10:40). The selected IME stayed dead for 6m19s; macOS dropped
  Bomi from AppleEnabledInputSources while keeping it selected, and every input-menu
  rebuild since could flip the selection to ABC/Apple-390. Evidence: unified log (only Bomi
  death in 36h, SIGTERM from launchd), zero foreign-mode setValue in 383k debug-log lines,
  repo has no TIS enable/disable code at all.
- [ime-enabled-drop] State repaired live: TISEnableInputSource reported all Bomi sources
  already enabled (runtime/persistence split), churn didn't persist, so the two mode dicts
  were written into AppleEnabledInputSources via `defaults write` (modeled on the Apple
  Korean entry) and TextInputMenuAgent restarted; entries survived the restart.
- [ime-enabled-drop] Fix decision: DebugLog switch is re-checked every 5s (OSAllocatedUnfairLock,
  keystroke path stays ~lock-only) so the script never needs to restart the IME; snapshot
  script now touch-only + logs bomi-present/MISSING in AppleEnabledInputSources each run
  (4h-resolution watchdog for recurrence). Deploy of the DebugLog change needs one
  attended install.sh run (it kills the IME) -- deferred to yoros's go.
2026-07-29 05:01 | [push] ime-enabled-drop @ 418cd5e -- fix: never kill the live IME to re-arm debug logging
2026-07-29 05:01 | [PR] https://github.com/yoropico/bomi-input/pull/8
2026-07-29 05:01 | [land] ime-enabled-drop -> main (merge) -- fix: never kill the live IME to re-arm debug logging
2026-07-29 05:39 | [session end] reason=exit
- [sebeolsik-mvp] 2026-08-03 "input sources multiply" report investigated end to end.
  Persisted AppleEnabledInputSources was clean the whole time (5 entries; bomi korean
  and roman once each); only the runtime TIS list ever carried one extra korean entry,
  and deleting a single duplicate row in System Settings cleared both that and the
  on-screen list. Ruled out by experiment: app code (no TIS enable/register call
  anywhere), reinstall via install.sh (count unchanged), and the repo-root Bomi.app
  copy that LaunchServices had registered under the same bundle id (unregistered it;
  no effect -- left unregistered since nothing should register a build artifact).
  The 8+ identical rows on screen never matched any store, so the remaining suspect is
  Settings' own list rendering rather than real registrations -- not proven, so it
  goes to monitoring instead of a fix.
- [sebeolsik-mvp] Snapshot watchdog now records the bomi mode count (modes=N, healthy
  is 2) next to the present/MISSING flag, so a recurrence that actually reaches
  persistence is datable to a 4h window instead of being argued from screenshots.
- [ime-drop-selfheal] 2026-08-06 the enabled-list drop recurred and went unrepaired for
  three days (2026-08-03 08:35 through 08-06 03:34 -- 19 watchdog runs at modes=0),
  surfacing to yoros as the IME reverting to the default source on leaving password
  fields: secure input forces an ASCII source on entry and restores the previously
  selected one on exit, which cannot work once Bomi is gone from
  AppleEnabledInputSources. Repaired the live domain by hand (backup of the pre-repair
  HIToolbox export kept in the session scratchpad), then made the snapshot watchdog
  repair what it already detects instead of only logging it.
- [ime-drop-selfheal] Repair adds back only the modes actually absent, so a partial drop
  does not duplicate the survivor, and it declines to act in three cases that would each
  do harm: an unreadable list (defaults -array-add CREATES the key, so the array would
  end up holding only Bomi and ABC plus the Apple layouts would be lost), more than two
  modes (that is the duplicate-rows incident class, which adding entries only worsens),
  and a missing ~/Library/Input Methods/Bomi.app (the documented teardown must stick
  rather than be undone every four hours).
- [ime-drop-selfheal] Scripts/test-enabled-list-selfheal.sh drives the real script against
  a throwaway defaults domain and a temporary HOME via four env overrides that launchd
  never sets, so the check covers all six branches without touching com.apple.HIToolbox;
  7/7 pass. The launchd job runs the script straight out of the main worktree, so merging
  to main IS the deploy and there is no staging step.
- [ime-drop-selfheal] 2026-08-03 05:06's install.sh run ruled out as the trigger: the 05:16
  watchdog still read modes=2, and the 2026-07-28 kill-to-drop delay was ~6 minutes, so it
  would have been caught by that run. The only other recorded action in the 05:16-08:35
  window was deleting a duplicate row in System Settings during the sebeolsik input-source
  investigation, and exactly the two Bomi entries went missing. The unified log no longer
  covers that date, so the attribution rests on the watchdog timeline, not a system record.
2026-08-06 05:38 | [push] ime-drop-selfheal @ 9f2fc0e -- fix(watchdog): repair the enabled-list drop instead of only logging it
2026-08-06 05:38 | [PR] https://github.com/yoropico/bomi-input/pull/9
2026-08-06 05:39 | [land] ime-drop-selfheal -> main (merge #9) -- watchdog self-heal deployed via the main checkout the launchd job runs
- [ime-drop-selfheal] 2026-08-06 ran the TIS disable/repair experiment to settle what the
  Input Sources pane's "-" button actually does. Result: NEITHER TISDisableInputSource on a
  single korean-mode instance NOR on the parent input method changed
  AppleEnabledInputSources at all -- the persisted list stayed at both modes throughout.
  So the 08-03 drop was not an API-level disable; System Settings must rewrite the
  persisted list wholesale when a row is removed, which is why an already-inconsistent
  on-screen list can take out entries nobody selected.
- [ime-drop-selfheal] The same experiment DID reproduce the user-visible symptom: disabling
  the parent bounced the selection to ABC while the persisted list still looked healthy.
  That is the mechanism behind "reverts to the default IME" -- selection can be lost with
  the enabled list intact, so maintenance.log showing `present (modes=2)` does not by
  itself prove the symptom is gone.
- [ime-drop-selfheal] The duplicate rows are real, not a rendering artifact: the enabled
  runtime list carries com.bomi.inputmethod.bomi.korean and .roman TWICE, both instances
  backed by the same ~/Library/Input Methods/Bomi.app, alongside the parent
  com.bomi.inputmethod.bomi. Disabling one instance removes just that instance and
  re-enabling the mode does NOT bring it back -- only toggling the PARENT off and on
  regenerates the pair, which places the duplication in the parent-activation path.
- [ime-drop-selfheal] Corroborating leftover state: Apple's Korean input method currently
  has parent enabled=NO while its 390Sebulshik mode is still listed in
  AppleEnabledInputSources and absent from the runtime enabled list. That half-torn shape
  is what a Settings row removal leaves behind, and it is consistent with the 08-03 edit
  having rewritten the list rather than disabling one source cleanly.
- [ime-dupe-watchdog] The runtime duplicate count is read with python3 + ctypes against
  Carbon's TIS API rather than a Swift helper, because only TIS sees the per-login runtime
  list (`defaults read` is blind to it), pyobjc ships no Carbon bindings, and compiling a
  Swift helper would put the Xcode toolchain on a background job's critical path. Measured
  0.1s per run with system python3 alone.
- [ime-dupe-watchdog] The new watchdog check DETECTS the duplicate and deliberately does not
  repair it: removing a duplicate row is exactly what rewrote the whole persisted array on
  2026-08-03 and left Bomi out of the enabled list for three days, and the one safe reset
  (a logout) is a human's decision rather than a background job's.
- [ime-dupe-watchdog] The launch agent moved from `StartInterval 14400` to six
  `StartCalendarInterval` entries at HH:30 every 4h, because the interval timer silently
  stopped firing after 2026-08-06 15:37 for ~13h with no reboot, empty stderr and last exit
  code 0 -- so the drop self-heal was dormant with no signal. A calendar entry is re-armed
  per occurrence, and fixed clock times make a missed run visible in maintenance.log.
  The plist is now version-controlled at Scripts/com.bomi.logsnapshot.plist; it previously
  existed only in ~/Library/LaunchAgents, where this fix could not survive a reinstall.
- [ime-dupe-watchdog] A ModeSwitcher.select hardening (take the first ref that actually
  selects instead of `list.first`, which a duplicate registration can make stale) was
  written and then REVERTED: `select` has no callers at all -- the toggle goes through
  `selectViaIMK`, and the 07-22 spec revision already recorded the TIS path as "retained
  but unused". That also explains the zero "TIS refused" lines across 13MB live + 79MB
  durable logs: the line cannot be reached. Hardening dead code buys nothing, and the
  duplicate is already detected from the watchdog where TIS truth is read anyway.
2026-08-06 07:19 | [session end] reason=other
2026-08-06 07:20 | [session end] reason=other
- [ime-drop-selfheal] 2026-08-07 recurrence is the DUPLICATE class again, but narrower: only
  com.bomi.inputmethod.bomi.roman appears twice in the runtime enabled list, korean once.
  AppleEnabledInputSources / AppleInputSourceHistory / AppleSelectedInputSources each carry
  the mode exactly once, so nothing reached persistence -- the extra row lives only in the
  current login session's HIToolbox registry. The two rows are distinct TISInputSource
  objects (CFEqual false, different pointers) with identical properties and both icon URLs
  resolving to ~/Library/Input Methods/Bomi.app, so it is a real second registration rather
  than a rendering artifact.
- [ime-drop-selfheal] Two candidate causes were ruled out. (1) LaunchServices had a SECOND
  Bomi.app registered under the same bundle ID -- the gitignored 07-29 build output at
  ~/Project/bomi-input/Bomi.app. Unregistering it with `lsregister -u` plus a
  TextInputMenuAgent restart left the duplicate row in place, so the stale registration was
  not the source; it was left unregistered anyway, since a build artifact has no business in
  the input-source registry. (2) Bomi's own code cannot create a registration: the sources
  call only TISCopyCurrentKeyboardInputSource / TISCreateInputSourceList / TISSelectInputSource
  -- no TISRegisterInputSource or TISEnableInputSource anywhere -- and the installed
  Info.plist declares each mode once in both tsInputModeListKey and
  tsVisibleInputModeOrderedArrayKey.
- [ime-drop-selfheal] The duplicate is cosmetic so far: ModeSwitcher.select takes list.first
  from the now-2-element match list, and both 13MB live and 79MB durable debug logs contain
  zero "TIS refused" lines, so every toggle still lands through the fast TIS path rather than
  the unverifiable IMK fallback.
- [ime-drop-selfheal] The watchdog cannot see this incident class: bomi-log-snapshot.sh counts
  only the persisted list, so it logged `present (modes=2, expected 2)` while three Bomi rows
  were on screen. Separately its 4h launchd timer had stopped firing after 2026-08-06 15:37
  -- ~13h with no reboot (uptime 1d20h), empty stderr, last exit code 0 -- and
  `launchctl kickstart` brought it back immediately. So the self-heal for the DROP class was
  also dormant for that window, which is the part worth fixing first.
2026-08-07 05:04 | [session end] reason=other
2026-08-07 05:04 | [session end] reason=other
2026-08-07 05:05 | [session end] reason=other
2026-08-07 07:04 | [session end] reason=other
- [ime-dupe-watchdog] 2026-08-10 recurrence triaged: the duplicate is NOT growing. The runtime
  TIS enabled list has held exactly one extra `com.bomi.inputmethod.bomi.korean` row since
  2026-08-07 08:30 (it first appeared 04:40 that day as an extra `roman` row, then moved to
  korean), and every 4h watchdog run since has logged the same `korean=2 roman=1 rows=6`.
- [ime-dupe-watchdog] The documented safe reset no longer works: the duplicate SURVIVED the
  2026-08-10 15:11 reboot -- the 15:12 post-login watchdog run already read korean=2 -- so the
  skill's "a fresh HIToolbox session resets the runtime list" claim is now falsified and a
  logout should not be offered as the fix without re-testing it.
- [ime-dupe-watchdog] Every persisted store is clean, so there is nothing for the self-heal to
  repair: AppleEnabledInputSources, AppleSelectedInputSources and AppleInputSourceHistory each
  carry korean and roman exactly once, and the installed Info.plist declares each mode once in
  both tsInputModeListKey and tsVisibleInputModeOrderedArrayKey.
- [ime-dupe-watchdog] The two korean rows are indistinguishable by every TIS property probed
  (type, category, enabled, selected, languages, ASCII-capable, bundle id and
  kTISPropertyIconImageURL all identical, pointing at ~/Library/Input Methods/Bomi.app), so
  they are two registrations of the same bundle rather than a stale second copy on disk.
- [ime-dupe-watchdog] LaunchServices did hold a second registration of bundle id
  com.bomi.inputmethod.bomi -- the assemble-app.sh build output left in the repo at
  /Users/bglee/Project/bomi-input/Bomi.app (built 2026-07-29, gitignored) -- and it was
  unregistered with `lsregister -u`. That is not yet proven to be the cause: the duplicate did
  not clear immediately, the repo path does not appear anywhere in the rebuilt
  com.apple.IntlDataCache.le.kbdx (only Methods/Bomi.app does), and the bundle had already sat
  registered for nine days before the first duplicate. The real test is the next login.
- [ime-dupe-watchdog] Still cosmetic after 465h of logging: 0 WEDGES in every app, 0 "TIS
  refused" lines in the 97MB durable log, so every toggle still lands through the fast TIS path
  despite the extra row.
2026-08-10 17:20 | [session end] reason=other
2026-08-10 17:20 | [session end] reason=other
2026-08-10 17:22 | [session end] reason=other
- [toggle-fail-terminal] The 2026-08-11 11:45 password-field revert could not be reproduced by driving
  secure input directly: Carbon EnableSecureEventInput() moved the selection to ABC and
  DisableSecureEventInput() restored com.bomi.inputmethod.bomi.korean cleanly, even with the duplicate
  runtime rows present. So the duplicate alone is not sufficient to cause the revert; a second condition
  is still unidentified, and the 11:45 window has no IME log because the debug switch was off until 11:50.
- [toggle-fail-terminal] Removing the leftover com.apple.inputmethod.Korean.390Sebulshik row from the
  persisted AppleEnabledInputSources (backup at scratchpad/HIToolbox.backup.plist) did NOT change the
  runtime list: still rows=6 with korean=2 plus the parent bundle row, before and after killall
  TextInputMenuAgent. The runtime registry is per-login, so this test cannot conclude until the next
  login -- the removal is deliberately left in place so that login decides it.
2026-08-11 13:06 | [session end] reason=other
2026-08-11 13:07 | [session end] reason=other
2026-08-11 13:10 | [session end] reason=other
- [moachigi-chord] Chord window is 150ms and lives in the ENGINE, not the controller: the
  decision "same syllable or new one" needs the previous key's time, which only the composer
  has across calls. 90-133ms real rolls from the 514h log set the floor; untimed inputASCII
  kept as the never-chord path so every existing test and non-IMK caller is untouched.
- [moachigi-chord] Deliberate lone-jamo typing (e.g. lone vowel then a syllable) inside the
  window WILL now merge — accepted: that is the definition of chord typing, and the window
  keeps it rare. Knob left as a public var, promote to Preferences only if daily use demands.
- [mail-commit-probe] Apple Mail's recipient field asks for a commit ~150ms after a
  keystroke while its completion runs, with the syllable still half-built (logged
  preedit='혀', preedit='ㄹ'). Honouring commitComposition there split the syllable, so
  the next jamo started a new one and the field filled with loose jamo ('김ㅕㄴ'), which
  matches no contact and takes the suggestion list down. Fix: commitComposition no
  longer flushes. Apple 2-Set Korean survives the same request, so it does not commit
  on it either.
- [mail-commit-probe] Rejected first: implementing composedString so IMK reports the
  real preedit. Mail sent commitComposition just the same, so "IMK thinks we are not
  composing" was not the trigger. Reverted rather than kept as a harmless extra.
- [mail-commit-probe] Ignoring the request is safe because every real end of composition
  flushes elsewhere -- deactivateServer, setValue on language change, and the
  modifier/passthrough branches of handleKeyEvent. No unit test: the change is the
  ABSENCE of a call inside an IMKInputController callback, verified on-device instead.
<<<<<<< HEAD
- [rcmd-shortcut-leak] Log evidence (06:42:03, com.apple.campo): Right-Cmd FIRE, 'b' keyDown with
  .command 138ms later, key-up 7ms after that -> app got Cmd+B. Typing overlap, not a Bomi
  routing bug. Fix: ToggleGate remembers the toggle key as "held" from fire until its key-up,
  any other modifier key, or 500ms (key-up is often lost); handleKeyEvent strips that bit and,
  in roman mode, types event.characters itself since returning false would pass the original
  Cmd+key through. Kept in ToggleGate so it is unit-tested; controller diff is minimal.
2026-08-26 09:24 | [session end] reason=other
2026-09-01 06:41 | [session end] reason=resume
=======
- [secure-passthrough] sudo prompts in BCT received Hangul even after BCT started toggling Secure Event Input (bomi-terminal PR #592): macOS swaps to an ASCII keyboard *layout* during secure input and ABC is not in the enabled list (TIS: ABC enabled=0, only bomi.roman is ASCII-capable), so the source stayed on bomi.korean -- reproduced by calling EnableSecureEventInput() directly. Fix on the IME side: handleKeyEvent passes keys through while IsSecureEventInputEnabled(), no mode/source change, so BCT's per-pane source pin and per-app memory stay untouched. Chosen over re-enabling ABC because an OS source swap would be captured by BCT's pin on blur. IMK-layer change: builds + 20 unit tests pass; sudo prompt verified on-device by yoros.
2026-08-26 12:18 | [push] secure-passthrough @ 06e7714 -- fix(ime): type ASCII while Secure Event Input is on (sudo/ssh password prompts)
2026-08-26 12:18 | [PR] https://github.com/yoropico/bomi-input/pull/17
- [app-default-mode] Per-app default mode is FORCED on every activateServer (yoros chose this over first-entry-only): simplest, no in-process "already applied" set, and it is what pinning Terminal=English means. Switch reuses the toggle path (optimistic ModeState + IMK selectMode), never TIS directly, because TIS-driven switches leave IMK routing stale (see spec).
- [app-default-mode] Menu items keep target=nil: IMK dispatches the action to the controller with a {kIMKCommandMenuItemName, kIMKCommandClientName} dictionary sender, which is also how we learn WHICH app the user was in.
- [app-default-mode] activateServer apply is DEFERRED 150ms: macOS restores the app remembered source at +0ms and re-asserts it at +16ms after activateServer, so an immediate selectMode was overwritten every time (log 10:08:36). After the delay we resync from TIS and switch only if still wrong.

- [mail-field-probe] The two Mail bugs are one root cause, not two: commitComposition is the
  only point where Mail syncs its completion with our composer. Honouring it split the
  syllable (loose jamo, matched nobody); ignoring it leaves the last syllable marked, and
  Mail reported 2026-08-24 that it now selects an unrelated contact. Text on screen is
  correct in the new failure mode, which is why it reads as "slightly odd" rather than broken.
- [mail-field-probe] Evidence for the second mode, log 09:01:44-50 (typing 최승호): Mail asked
  for a commit twice with '승' and '호' still marked, both IGNORED, and the user immediately
  backspaced twice, retyped, pressed Right-Arrow to shake off the completion, then Return.
- [mail-field-probe] Cannot decide the fix from our own log: it records what we SEND, never
  what the client holds, so whether Mail matches on the marked text or only the committed
  prefix is unanswerable from here. Added probeClient() reading back client.length/string/
  selectedRange/markedRange after every setMarkedText, commit and flush, and at
  commitComposition itself. Gated on DebugLog.isEnabled because each call is synchronous IPC
  into the client and must not sit on the keystroke path of a shipped build.
- [mail-field-probe] The before-write probe answered it in one keystroke. Log 16:35:44.452,
  right before our setMarkedText '형': len=41 text='김상태_센터장(영업센터) - stkim1@rsautomation.co.kr'
  sel=1+40 marked=1+1. Mail had already committed its completion into the field with the
  remainder SELECTED from index 1 to the end, computed from '김' alone -- our marked '혀' was
  not in the query and Mail overwrote it. That is the reported bug, exactly: 김형 typed, 김상태 offered.
- [mail-field-probe] So the original reading was right and my retraction after fix #2 was wrong:
  Mail queries on the text it received as committed. Fix #2's forced commit DID produce the
  correct candidate (김형태 for 김형) -- that part worked and should be kept.
- [mail-field-probe] What killed fix #2 was the write that followed, not the commit. Passing an
  explicit replacementRange bypasses the client's own "replace marked range plus selection"
  rule, so the completion remainder survived as literal text (len stayed 41). Passing noRange
  consumes the whole thing: at 16:35:44.453 the same write took the field from 41 chars back to
  a clean '김형'. The range bookkeeping was the defect, not honouring the request.
- [mail-field-probe] Fix #3 = fix #2's forced commit kept, but the replacement range is no
  longer trusted from memory alone. takeReplacementRange unions the recorded range with the
  client's live markedRange and selectedRange at write time, so Mail's selected completion
  remainder is swallowed the way a plain keystroke would swallow it. noRange stays the path for
  every write outside a forced commit, because the client's own rule already does the right
  thing there -- that was the lesson of fix #2, which overrode it and orphaned the remainder.
- [mail-field-probe] The union is bounded to ranges that touch ours (other.location <=
  NSMaxRange(range) && NSMaxRange(other) >= range.location). Without it a selection sitting
  elsewhere in the document would be merged in and deleted; the completion remainder always
  abuts, so the bound costs nothing real.
- [mail-field-probe] Fix #3 partly works and is kept deployed: it is the first build where Mail
  ever resolves the right person. Log 17:09:45.621, after the forced commit of '린', the client
  held '김형 (Shawn Kim(김형린) - shawnkim@rsautomation.co.kr) ' -- the correct contact, matched
  on the full 김형린. The field also stays clean (writes take it back to '김형린'), so none of
  fix #2's welding of a stranger's address remains.
- [mail-field-probe] What is still wrong is the INTERMEDIATE candidate. At the '형' stage the
  forced commit leaves the field committed as '김형', yet Mail answers with
  '김상태_센터장(영업센터) - stkim1@rsautomation.co.kr' (17:09:43.792 before-probe), a match that
  contains no 형 at all. Once 린 is committed the same mechanism answers correctly, so Mail is
  not simply matching our committed text the way three fixes have assumed.
- [mail-field-probe] Separate defect found in the same log: a passthrough flush on Right-Arrow
  does not take. 17:09:23.475 wrote '형' over replacing=1+40 and the after-probe shows the field
  byte-identical at len=41 sel=1+40, while the same write from Space (17:09:36.200) and from a
  jamo key (17:09:43.792) both collapse it to '김형'. Not the reported bug; do not fold it into
  the same fix.
- [mail-field-probe] Three fixes have now failed on the same seam, which per systematic-debugging
  is the point to stop patching and question the design. The premise every attempt shares is that
  a marked syllable can coexist with Mail's async completion rewriting the same field -- two
  writers, no synchronisation. Before attempt #4, measure Apple 2-Set Korean typing 김형린 in the
  same field: if it also shows 김상태 mid-name, the intermediate candidate is Mail's own behaviour
  and the remaining work is nothing.
- [mail-field-probe] Apple 2-Set resolves 김형린 correctly in the same field (yoros, 2026-08-24),
  so the intermediate wrong candidate is OURS, not Mail's. That kills the "nothing left to do"
  branch and means our call sequence differs from Apple's somewhere we have never looked.
- [mail-field-probe] Every fix so far reasoned from our own side of the boundary, which is why
  three in a row missed. Added Scripts/imk-client-trace.swift: an NSTextView subclass that logs
  insertText/setMarkedText/unmarkText/rangeForUserCompletion with the field state after each.
  Typing the same text under each input source gives a direct diff of what the two IMEs send.
  rangeForUserCompletion is traced on purpose -- NSTextView refuses to complete while marked
  text exists, so when it turns into a real range is likely the whole answer.
- [mail-field-probe] The client trace answers it, and the answer is architectural: Apple 2-Set
  never calls setMarkedText at all. Its whole trace is insertText with an explicit
  replacementRange over the previous rendering of the same syllable -- 'ㄱ' at none, then '기'
  and '김' each replacing 4+1, a repeat '김' to finalise, then 'ㅎ' appended at none. marked is a
  zero-length range on every single line. Bomi's block above it is the opposite: setMarkedText
  for every syllable, marked=1+1 throughout.
- [mail-field-probe] That explains the whole bug without any of the three theories tried.
  NSTextView refuses to complete while marked text exists, so with Bomi the completion only ever
  sees the committed prefix '김' and answers 김상태; with Apple every character is already
  committed text, so the field completes on 김형 like an ordinary typist and finds 김형린.
- [mail-field-probe] Adopting Apple's protocol deletes the problem rather than patching it:
  with nothing ever marked, commitComposition has nothing to commit, forcedCommit and its range
  bookkeeping go away, and the original loose-jamo bug cannot occur either. Cost is that every
  client must honour replacementRange -- which Apple's own IME already requires of them, but
  BCT's terminal client answers length()=0 to our probes and is the one to verify first, since a
  client that ignores the range would append instead of replace and render 'ㄱ기김' garbage.
- [mail-field-probe] Correction to the revert message: BCT does not ignore replacementRange -- we
  never sent one. Log 17:27:55-57 shows every write as replacing=none, because write() derives the
  range origin from the client's caret and BCT answers len=0 sel=0+0 to every probe, so the guard
  (caret.location < text length) blanked `rendered` on each append. The protocol was never
  exercised there; the range bookkeeping simply had no coordinates to work from.
- [mail-field-probe] That also means committed-text composition is IMPOSSIBLE, not merely risky,
  in any client that does not report length/caret: absolute ranges cannot be computed at all. The
  protocol therefore has to be conditional, and the only open question is how the condition is
  decided -- a per-app opt-in, or a capability probe on client.length().
- [mail-field-probe] Capability probing is ambiguous exactly where it matters: an empty NSTextView
  and BCT both answer length()=0 before the first write, so the mode cannot be chosen up front and
  switching protocols mid-syllable is where corruption has lived every time so far.
- [mail-field-probe] Fix #3 turned out to break BCT too, which is why the last word got cut:
  log 17:30:29 forced-commits '트' and records forcedCommit=0+1, then 17:30:31.561 flushes with
  replacing=0+1. BCT reports len=0 sel=0+0, so that range is not the syllable we just wrote --
  it is absolute position 0, the START of the line. Any client that cannot report coordinates
  gets an explicit range that points at the wrong text.
- [mail-field-probe] So all three post-main changes regressed a real workflow: fix #2 welded a
  stranger's address into Mail recipients, fix #3 overwrites line-start text in coordinate-less
  clients, and the committed-text protocol appended every intermediate jamo there. Restored
  Sources/Bomi/BomiInputController.swift to 901a707, which is behaviourally identical to main
  (commitComposition ignored, every write at noRange) and keeps only the gated probes.
- [mail-field-probe] The rule this cost four attempts to learn: never send an explicit
  replacementRange to a client that does not report length/caret, because the range means
  something different to it. Any future fix must establish that capability before using ranges,
  and the shipped default must stay noRange.
- [mail-field-probe] Reproducible defect isolated in the SHIPPED behaviour (not a regression from
  this branch): an ignored commitComposition makes the next flush delete the syllable instead of
  committing it. Log 19:53, three cases one minute apart.
  19:53:29.692 commitComposition '호' IGNORED, then 19:53:31.617 flush -> field '최승호' becomes
  '최승' (len 3 -> 2). Again at 19:53:46.501 / 19:53:47.976, same loss.
  Control at 19:53:34.609: '호' marked, NO commitComposition arrives, flush at 19:53:36.130 keeps
  '최승호' (len 3). The only difference between kept and lost is whether commitComposition fired.
- [mail-field-probe] Reading: after we return from commitComposition having written nothing, the
  composition is treated as over and the marked text is dropped, so our later insertText at
  noRange has no marked range to replace and the syllable is discarded rather than committed.
  The client still reports marked=2+1 while we are inside the callback, so the drop happens after
  we return -- which is why nothing on our side could see it before.
- [mail-field-probe] This is what "the last word never completes and vanishes" means, and it dates
  from PR #13, not from anything on this branch. Candidate fix that stays inside the range
  constraint: end the composition explicitly in flush (setMarkedText "" then insertText at
  noRange) instead of relying on insertText to replace a marked range that may already be gone.
  Not implemented -- four attempts have been reverted, so this one gets agreed before it ships.
- [mail-field-probe] Implemented the agreed fix: flush now ends the composition explicitly
  (setMarkedText "" then insertText at noRange) instead of relying on insertText to replace a
  marked range the client may already have dropped. Scoped to flush alone -- commit was measured
  working through the same window (17:36:01.705 IGNORED then 17:36:03.394 commit kept '김형'), so
  it is left untouched; flush is the shared blur/passthrough/mode-change path, so one change
  covers every caller that loses text.
- [mail-field-probe] Deliberately coordinate-free. An explicit replacementRange is what made the
  last four attempts unshippable, since BCT reports len=0 sel=0+0 and writes such a range at
  position 0; clearing the preedit needs no coordinates at all and so cannot mean something
  different there.
- [mail-field-probe] Added a probe between the two calls ("after ending composition") because the
  intermediate state is the thing to check if this fails: the field should briefly lose the marked
  syllable and then get it back as committed text, and a client that keeps it would double it.
- [prefs-window] Settings window lives IN the IME process (no second app). That forced Info.plist LSBackgroundOnly -> LSUIElement: a background-only process can never bring a window forward. Squirrel/Rime ships LSUIElement the same way. Watch on-device for focus not returning to the previous app after closing the window.
- [prefs-window] Toggle key is a popup of lone modifier keys, not a key-capture field: the toggle only fires on flagsChanged, so the valid set is small and enumerable.
- [arrow-flush-loss] Root cause of arrow-key syllable loss: cdc595e's unconditional two-step flush (empty setMarkedText, then insertText) breaks Chromium clients -- Edge log 07:24 shows caret unmoved and syllable gone on arrow/space flush, while one-step mid-typing commits land. Fix branches on client.markedRange(): range present = one-step replace-commit (pre-cdc595e path), range gone = keep the two-step that fixed Mail's dropped-marked-text case.
>>>>>>> origin/main
- [rcmd-shortcut-leak] "Still happens rarely" diagnosed: the fix WORKED (one on-device
  strip logged 08-26 09:22, campo) but the installed bundle was replaced 08-28 07:48 by
  another stream's main-tree install (PRs #14-#18 era) which predates this branch -- the
  binary since then contains no "toggle key still held" string, and every post-08-28 leak
  in the durable log matches the unfixed pattern. Not a hole in the held-window logic.
  Remedy: merged origin/main into the branch (worklog union, controller auto-merged,
  51 tests pass), reinstalled. Real prevention is landing the PR so main carries the fix.
- [blur-commit-double] Root cause of the doubled last syllable: Mail's subject field and Calendar ask
  for a commit as they lose focus, we ignore it (the recipient field sends the same request
  mid-syllable), and AppKit then finalises the marked syllable itself before deactivateServer
  arrives 1-15ms later, so the blur flush appends a second copy ('건건', '미팅팅', '안내내').
  Six cases in the durable log, under BOTH flush variants -- cdc595e's two-step and 6a37bed's
  markedRange branch -- so neither the recurrence nor the fix is about the flush shape.
- [blur-commit-double] Fix reads the field back at deactivateServer, only when a commit request was
  ignored for this syllable, and skips the write when the client already holds it as committed
  text (caret at the end, nothing selected: BlurCommit.clientAlreadyHolds). Not a blind skip:
  BCT's terminal view discards marked text on unmarkText and reports len=0, so it (and Chromium,
  also len=0) must keep being written to or the syllable is lost. Keystroke-driven flushes are
  untouched -- the recipient field still holds the syllable as MARKED there (sel=1+1) and needs
  the insert.
2026-09-02 05:13 | [session end] reason=other
2026-09-02 05:41 | [session end] reason=resume
- [blur-commit-double] Edge ("자주 발생") is the same root cause with a second trigger: Chromium confirms
  the composition in Blink on a mouse click (finishComposingText) or blur (Blink confirms internally,
  render_widget_host_view_cocoa.mm) and then discards its marked text -- that discard is the
  commitComposition we ignore. Log: 95 Edge commit requests, 18 followed by a keystroke that
  re-committed the same syllable ('업업'), 71 by a blur flush. Edge reports len=0, so the text
  read-back can never judge it; after cancelComposition Chromium's markedRange() answers NSNotFound,
  while Mail's recipient field (the one client that keeps composing after a request) still reports
  1+1. So: keystroke/toggle after a request drops the composer when markedRange is NSNotFound; blur
  after a request skips the write unless the client's text proves the syllable gone.
- [blur-commit-double] On-device 06:21 (Edge): the blur skip worked, but the keystroke drop never fired --
  markedRange() still answered 2+1 after the click's commit request, so the next key re-committed
  'ㅣ'. IMK apparently answers markedRange from its own cache (the reported location never matched
  the field either: marked=2+1 while sel=114+1). Switched the keystroke/toggle check to
  selectedRange(), which is live: Chromium returns the renderer's selection = composition range
  while composing (length>=1 in every probe), caret (length 0) once Blink confirmed; Mail's
  recipient field keeps the syllable selected (1+1 / 1+40). Every read is now logged
  ("after commit request: sel=... finalized=...") so the next recurrence shows the values.
2026-09-02 06:42 | [push] blur-commit-double @ 6e850f5 -- fix(ime): stop doubling the last syllable after a client's commit request (Mail, Calendar, Edge)
2026-09-02 06:42 | [PR] https://github.com/yoropico/bomi-input/pull/20
2026-09-02 07:00 | [session end] reason=other
2026-09-03 04:15 | [triage] 04:10 'cannot type Korean / cannot switch': NOT an IME or enabled-list fault -- both enabled domains, runtime rows, Bomi process and IMK activations all healthy; ioreg kCGSSessionSecureInputPID=23566 (BCT) holds Secure Event Input machine-wide. No tty in ICANON+!ECHO state, guard resign path (BCT->Edge flip) and blurring the rs-mes dock's focused password field did not release it, so the leak is outside SecureInputGuard's balanced path (WKWebView/NSSecureTextField suspects) or a count>=2; only a BCT restart clears it. Fix belongs in bomi-terminal.
2026-09-03 04:17 | [triage] BCT restart released the secure-input hold (ioreg now shows no holder, new BCT pid 62159); yoros confirmed typing normal. Root-cause fix still pending in bomi-terminal.
2026-09-03 04:19 | [dispatch] yoros said 진행 -> one headless bomi-terminal worker 70D94A2A (desk secure-input-leak, PR only) to reproduce the Secure Event Input leak (WKWebView/NSSecureTextField/guard paths) and add an IORegistry-holder-pid drain on app deactivation; brief in scratchpad briefs/secure-input-leak.md.
2026-09-03 04:23 | [dispatch] worker 70D94A2A died at 5 turns on a Fable 429 usage limit (no desk/branch created, nothing to clean). Re-spawned as 96174D28 with --model opus and an absolute node path in the brief (the headless env's /bin/sh hooks had no node/op on PATH).
2026-09-03 04:50 | [result] worker 96174D28 completed: root cause = WebKit leaves EnableSecureEventInput unbalanced when a RETAINED WKWebView with a focused password field is detached from its window (BCT dock tab swap/fold/close/full-page capture; harness scenario G leaks, I (makeFirstResponder(nil) before detach) does not; NSSecureTextField paths clean). PR bomi-terminal#701 (resign-first-responder before every detach + IORegistry-holder-pid bounded drain while inactive), gate green, desk kept, NOT deployed.
2026-09-03 05:12 | [dispatch] yoros: 끝나면 결과 알려줘 (= go) -> headless bomi-terminal worker to merge PR #701, --done the desk, Release-build + redeploy /Applications/BCT.app per bct-redeploy-to-applications, restart BCT, verify ioreg holder.
2026-09-03 05:23 | [result] deploy worker 7A7A4DD2 completed: PR #701 merged as b8423dc0, desk secure-input-leak closed, Release arm64 build signed and swapped into /Applications/BCT.app (GitCommit b8423dc, SecureInputDrain symbols present, CFBundleVersion still 125), BCT relaunched pid 96982 at 05:19:17, tmux sessions survived, ioreg shows no secure-input holder. Left: DerivedData Release BCT.app copy not removed (rm -rf guard), bomi-terminal worklog/session-state uncommitted.
2026-09-03 05:57 | [close] 작업종료: no open task in bomi-input (triage ran on main, no desk); the bomi-terminal desk secure-input-leak was already closed by the deploy worker. Session ends with IME healthy, BCT b8423dc deployed, no secure-input holder.
2026-09-03 06:21 | [session end] reason=other
2026-09-07 11:38 | [session end] reason=other
