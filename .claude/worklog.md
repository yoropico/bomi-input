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
