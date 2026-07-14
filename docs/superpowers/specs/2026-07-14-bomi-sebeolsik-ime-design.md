# Bomi — Sebeolsik-Final Korean IME for macOS 26 (Design Spec)

- **Date:** 2026-07-14
- **Status:** Approved design, pre-implementation
- **Target:** macOS 26 (26.5.2), Xcode 26, Swift 6.3, Apple Silicon
- **Bundle id:** `com.bomi.inputmethod.bomi`

## 1. Goal & Scope

Build a **daily-driver replacement** Korean input method for macOS, focused on the **Sebeolsik-final (세벌식 최종, libhangul id `3f`)** layout. It must feel at least as solid as Apple's built-in Korean IME for a Sebeolsik-final user, with robust composition and mis-state recovery in demanding apps.

### MVP features (in scope)
- Sebeolsik-final Hangul automaton (choseong/jungseong/jongseong, compound jamo).
- Robust composition + **mis-state recovery**: jamo-level backspace, no dropped composition in hard apps (Terminal/Electron/etc.).
- **In-IME han/eng toggle** (Gureum-style), default **Right Command**, with **per-app han/eng memory**.
- Status/preferences via the IMK input-source **menu** (`menu()` override) + `UserDefaults`.

### Non-goals (deferred, not in MVP)
- Hanja conversion (dictionary + candidate window).
- Symbol/special-character input layer beyond what the `3f` map already carries.
- Additional layouts (Dubeolsik, Sebeolsik-390) — architecture leaves room; not built now.
- Eojeol-level "keep composing" mode (see §5.4); MVP commits per-syllable.

## 2. Key Decisions (resolved during brainstorming)

| Decision | Choice | Why |
|---|---|---|
| Base API | **InputMethodKit (IMK)** | Only official Apple API for a macOS IME; not deprecated on macOS 26; no replacement. CGEventTap can't show preedit / breaks in secure fields → unusable for Hangul. |
| Engine | **Pure Swift automaton** | Zero deps, license-free, Swift 6/macOS 26 native, full control of NFC. libhangul used only as reference + test oracle. |
| Layout | **Sebeolsik-final (`3f`)** first | User's daily layout. Cho/jung/jong keys are physically separate → clean automaton, no 도깨비불. |
| Han/eng | **In-IME toggle**, default Right Command | Consistent feel, per-app memory; Gureum-style. |
| Commit policy | **Per-syllable immediate commit** | Matches Apple/Gureum feel; robust in hard apps (eojeol-keep would break long preedit). |
| Build | **SwiftPM + assembly script** | CLI/git-friendly, no Xcode GUI, keeps Engine a clean module. |
| Concurrency | `nonisolated ... @unchecked Sendable` + `mainSync` bridge | Latest verified idiom (Shiki Suen 2026); no external package. |

## 3. Research Basis (verified, with sources)

InputMethodKit facts confirmed against real, current open-source IMEs and the "macOS Input Method Development Guidelines for 2026" (Shiki Suen), vChewing/IMKSwift, goftam, toyimk. Full notes in `scratchpad/research-findings.md`. Highlights:

- **Info.plist required keys:** `InputMethodConnectionName = $(PRODUCT_BUNDLE_IDENTIFIER)_Connection` (must be exactly this or silent load failure), `InputMethodServerControllerClass = $(PRODUCT_MODULE_NAME).BomiInputController`, `LSBackgroundOnly=true`, `TISInputSourceID`, `TISIntendedLanguage`, `tsInputMethodIconFileKey`, `NSPrincipalClass`, and a `ComponentInputModeDict` (`tsInputModeListKey` + `tsVisibleInputModeOrderedArrayKey`).
- **Bundle id must contain `inputmethod`.**
- **Swift controller** needs `@objc(BomiInputController)`.
- **Swift 6 concurrency friction is real** (IMK headers lack `@MainActor`, not `Sendable`). Handle via `nonisolated` class + `@unchecked Sendable` + a `mainSync` helper; `nonisolated` is mandatory on `IMKStateSetting`/`IMKMouseHandling` methods.
- **Install:** `~/Library/Input Methods` (per-user, no sudo); `killall` to reload; log out/in only for first registration. Ad-hoc signing is sufficient for personal use.
- **macOS 26 gotchas:** `IMKClient_Legacy` console spam (benign); candidate-window teardown race across sibling sessions; NSWindow memory not reclaimed (Liquid Glass) → keep long-lived NSWindows minimal (reason we skip a persistent NSStatusItem in MVP).
- **Han/eng:** override `recognizedEvents()` to add `.flagsChanged`; Right Command keyCode `0x36` (left `0x37`).

Sebeolsik-final data taken verbatim from libhangul:
- Key map: `data/keyboards/hangul-keyboard-3f.xml.template` (`id="3f" type="jaso"`, 95 entries).
- Combination table: `data/keyboards/hangul-combination-default.xml` (36 entries).
Both reproduced in Appendix A/B and in `scratchpad/research-findings.md`.

## 4. Architecture (3 layers, isolated)

```
bomi-input/
├─ Sources/
│  ├─ Engine/            ← pure Swift, Foundation only, ZERO IMK. Unit-testable standalone.
│  │  ├─ Jamo.swift             cho/jung/jong definitions + Unicode index tables
│  │  ├─ Syllable.swift         (cho,jung,jong) ⇄ Unicode syllable (0xAC00), NFC + fallback
│  │  ├─ SebeolsikFinal.swift   3f key→jamo table (data, from libhangul)
│  │  ├─ Combination.swift      compound-jamo table (data, from libhangul)
│  │  └─ HangulComposer.swift   automaton state machine: input/backspace/commit
│  ├─ IMKLayer/         ← InputMethodKit glue (thin)
│  │  ├─ BomiInputController.swift   IMKInputController subclass
│  │  ├─ KeyTranslator.swift         NSEvent → US-QWERTY(+shift) char → 3f lookup; toggle detect
│  │  └─ LanguageMode.swift          han/eng state + per-app memory
│  └─ App/
│     ├─ main.swift             IMKServer bootstrap (@main), custom NSApplication
│     ├─ Preferences.swift      UserDefaults (toggle key, layout, per-app memory on/off)
│     └─ MenuBuilder.swift      builds the IMK input-source menu
├─ Resources/
│  ├─ Info.plist                IMK keys
│  └─ *.tiff/.png               menu-bar / mode icons
├─ Tests/EngineTests/           sequence → expected string (no IMK)
├─ Scripts/
│  ├─ assemble-app.sh           swift build output → Bomi.app bundle + Info.plist + sign
│  └─ install.sh                copy to ~/Library/Input Methods + killall
├─ Package.swift
└─ docs/superpowers/specs/…
```

**Data flow:**
`keyDown → KeyTranslator → (han mode) HangulComposer.input(jamo) → buffer update → BomiInputController.setMarkedText(preedit) → on commit condition → client.insertText`.
Backspace → `composer.backspace()` (jamo-level). Han/eng toggle → force-commit + mode switch.

**Module discipline:** each file ≤ ~300 lines / 12KB; propose a split first if exceeded. Engine has no IMK import → fully unit-testable.

## 5. Engine Design (Sebeolsik-final automaton)

### 5.1 Jamo classification (by Unicode range of the mapped value)
- Choseong: `U+1100–U+1112` (index = value − 0x1100, 0..18)
- Jungseong: `U+1161–U+1175` (index = value − 0x1161, 0..20)
- Jongseong: `U+11A8–U+11C2` (index = value − 0x11A7, 1..27; 0 = none)
- Anything else (symbols/digits from the `3f` map, e.g. `0x00B7`, `0x203B`, ASCII) = **non-jamo**: not composable.

### 5.2 Composer state
Buffer `(cho: Int?, jung: Int?, jong: Int?)` plus a small **history stack** of applied steps for backspace. One syllable in progress at a time (per-syllable commit).

### 5.3 Input rule
For an incoming jamo with a known slot (cho/jung/jong):
1. If that slot is empty → fill it.
2. If occupied → try the **combination table** (§Appendix B) to merge (e.g. `ㄱ+ㄱ→ㄲ`, `ㅗ+ㅏ→ㅘ`, `ㄹ+ㄱ→ㄺ`). Success → replace slot with compound. Failure → **commit current syllable, start new one** with this jamo.
3. Slot-order violation (e.g. new choseong arrives while jong already set, or jung arrives after jong) → **commit current syllable, start new** with this jamo.

For a non-jamo (symbol/digit) → **commit current syllable**, then insert the symbol directly (no composition).

Sebeolsik-final specifics baked in:
- Compound jongseong (ㄲㄳㄵ…ㅄ) reachable via **both** dedicated keys and combination.
- Double choseong (ㄲㄸㅃㅆㅉ) and compound vowels (ㅘㅙㅚㅝㅞㅟㅢ) have **no dedicated key** → combination only.
- No 도깨비불: jong never migrates to next syllable's cho (separate keys).

### 5.4 Commit (per-syllable, NFC)
- Compose `(cho,jung,jong)` → `0xAC00 + (choIdx*21 + jungIdx)*28 + jongIdx` when cho+jung present.
- Incomplete states (lone consonant, lone/leading vowel, cho without jung, etc.) → **fallback to Hangul Compatibility Jamo (U+3130 block)** for display/commit.
- Commit triggers: next syllable starts, non-jamo input, han/eng toggle, focus loss (`deactivateServer`/`commitComposition`), or a passthrough special key (Space/Enter/arrows/Esc).
- (Deferred) eojeol-level keep-composing mode is explicitly out of MVP.

### 5.5 Backspace / mis-state recovery
- If composing: pop the last applied step from the history stack.
  - Compound jamo → revert to its base (`ㄺ→ㄹ`).
  - Simple jamo → clear that slot.
  - Consume the key (don't forward), refresh marked text.
- If not composing: forward backspace to the app.

## 6. IMK Integration (thin layer)

### 6.1 BomiInputController: IMKInputController
- `@objc(BomiInputController)`; `nonisolated final class ... @unchecked Sendable`; `mainSync` helper hops to main thread where UI/client touch is needed. Do not hold strong refs to client objects across sessions (address-keyed lookup) to avoid ARC/MainActor congestion.
- Overrides:
  - `handle(_ event: NSEvent, client:) -> Bool` — single key entry point.
  - `recognizedEvents()` → `.keyDown ∪ .flagsChanged`.
  - `commitComposition(_:)`, `deactivateServer(_:)` — force-commit in-progress syllable.
  - `activateServer(_:)` — restore per-app han/eng state.
  - `menu()` — build the input-source menu (§7).

### 6.2 Text to client (IMKTextInput)
- Composing → `client.setMarkedText(_:selectionRange:replacementRange:)` (underlined preedit).
- Commit → `client.insertText(_:replacementRange:)`.

### 6.3 Key handling (return true=consume, false=passthrough)
```
keyDown → KeyTranslator(keyCode + shift → US-QWERTY char → 3f lookup)
  ├ eng mode                         → return false
  ├ han mode & jamo                  → composer.input → setMarkedText → true
  ├ han mode & symbol/digit          → commit → insert symbol → true
  ├ Backspace (composing)            → composer.backspace → setMarkedText → true
  ├ Space/Enter/arrows/Esc(composing)→ commit first → forward key (false)
  └ Right Command (flagsChanged)     → commit → toggle han/eng → true
```
- **KeyTranslator** maps `keyCode` to the US-QWERTY character honoring Shift but **ignoring CapsLock and the system layout**, so physical key position is authoritative (required for `type=jaso`).
- **Toggle detection**: a bare Right-Command tap (down→up with no other key in between) toggles; a Command used in a chord does not.

### 6.4 Hard-app mitigations (verify against gureum source during impl)
- Always commit in `deactivateServer`/`commitComposition` so mouse-click / tab-switch never drops composition.
- Detect apps where marked text misbehaves → `insertText` fallback path.

### 6.5 LanguageMode
- Han/eng flag + per-app memory (`bundleId → last mode`, `UserDefaults`, toggleable). Restore in `activateServer`.

## 7. UI & Preferences
- No persistent `NSStatusItem` in MVP (avoids macOS 26 NSWindow leak; uses IMK's own input-source icon).
- `menu()` returns: current mode indicator, **[Preferences] [Layout] [Han/Eng toggle key]**.
- `Preferences` (`UserDefaults`): toggle key (default Right Command), layout (default `3f`), per-app memory on/off.
- Minimal SwiftUI preferences window; most control lives in the menu.

## 8. Build / Install / Packaging
- `Package.swift`: `Engine` library target (pure), `IMKLayer` + `App` executable target linking IMK.
- `Scripts/assemble-app.sh`: `swift build -c release` → assemble `Bomi.app` (`Contents/MacOS/Bomi`, `Contents/Info.plist`, `Contents/Resources/…`) → `codesign` (ad-hoc `-`).
- `Scripts/install.sh`: copy `Bomi.app` → `~/Library/Input Methods/`, `killall Bomi` to reload. First-time: add in System Settings > Keyboard > Input Sources (log out/in if needed).
- Bundle id `com.bomi.inputmethod.bomi`.

## 9. Testing Strategy
- **EngineTests (XCTest, no IMK):** input-sequence → expected-string across all cho/jung/jong, every combination-table entry, dedicated-key vs combination compound jong equivalence, backspace recovery, commit boundaries, fallback for incomplete syllables. Sample: `kf`→`가`, `kfs`→`간` (s=ㄴ jong), `krw`→`갤` (r=ㅐ, w=ㄹ jong), `kkf`→`까` (ㄱ+ㄱ combine to ㄲ, +ㅏ). Verify each against libhangul.
- **libhangul oracle (optional):** run identical sequences through libhangul, diff results, as a build-time correctness check.
- **Manual integration:** TextEdit, Safari, Terminal, VS Code, a password field.

## 10. Risks & Open Questions (resolve first in implementation plan)
1. **Swift 6 IMK concurrency**: get the `nonisolated`/`@unchecked Sendable`/`mainSync` skeleton compiling and callback-correct before any automaton work. Highest risk.
2. **SwiftPM → IMK .app assembly**: verify a hand-assembled bundle (no Xcode) actually loads as an input method on macOS 26 (Info.plist keys + `inputmethod` bundle id + connection name). Do a "hello world commit" IME spike first.
3. **Right-Command bare-tap detection** reliability via `flagsChanged` under IMK.
4. **Hard-app preedit** behavior (Terminal/Electron): validate mitigations against gureum.
5. **Ad-hoc signing** actually loads on macOS 26 without Gatekeeper block for a personal input method.

## 11. Milestones (build order)
1. **IME spike**: minimal IMK app (SwiftPM-assembled bundle) that loads, shows in Input Sources, and commits a fixed string — proves §10.1, §10.2, §10.5.
2. **Engine core**: Jamo/Syllable/SebeolsikFinal/Combination + HangulComposer with unit tests (input/commit/backspace), TDD.
3. **Wire Engine into controller**: setMarkedText/insertText, per-syllable commit, backspace.
4. **Han/eng toggle** + per-app memory.
5. **Hard-app hardening** + menu/preferences.
6. **Polish**: icons, install script, docs.

---

## Appendix A — Sebeolsik-final (`3f`) key→value map (libhangul, verbatim)

`key` = shift-applied ASCII (0x21–0x7e); `value` = Unicode jamo (conjoining) or symbol. Source: `hangul-keyboard-3f.xml.template`.

```
21→11a9(ㄲ종) 22→00b7(·) 23→11bd(ㅈ종) 24→11b5(ㄿ종) 25→11b4(ㄾ종) 26→201c(“) 27→1110(ㅌ초)
28→0027(') 29→007e(~) 2a→201d(”) 2b→002b(+) 2c→002c(,) 2d→0029()) 2e→002e(.) 2f→1169(ㅗ중)
30→110f(ㅋ초) 31→11c2(ㅎ종) 32→11bb(ㅆ종) 33→11b8(ㅂ종) 34→116d(ㅛ중) 35→1172(ㅠ중) 36→1163(ㅑ중)
37→1168(ㅖ중) 38→1174(ㅢ중) 39→116e(ㅜ중) 3a→0034(4) 3b→1107(ㅂ초) 3c→002c(,) 3d→003e(>) 3e→002e(.)
3f→0021(!) 40→11b0(ㄺ종) 41→11ae(ㄷ종) 42→003f(?) 43→11bf(ㅋ종) 44→11b2(ㄼ종) 45→11ac(ㄵ종) 46→11b1(ㄻ종)
47→1164(ㅒ중) 48→0030(0) 49→0037(7) 4a→0031(1) 4b→0032(2) 4c→0033(3) 4d→0022(") 4e→002d(-)
4f→0038(8) 50→0039(9) 51→11c1(ㅍ종) 52→11b6(ㅀ종) 53→11ad(ㄶ종) 54→11b3(ㄽ종) 55→0036(6) 56→11aa(ㄳ종)
57→11c0(ㅌ종) 58→11b9(ㅄ종) 59→0035(5) 5a→11be(ㅊ종) 5b→0028(() 5c→003a(:) 5d→003c(<) 5e→003d(=)
5f→003b(;) 60→002a(*) 61→11bc(ㅇ종) 62→116e(ㅜ중) 63→1166(ㅔ중) 64→1175(ㅣ중) 65→1167(ㅕ중) 66→1161(ㅏ중)
67→1173(ㅡ중) 68→1102(ㄴ초) 69→1106(ㅁ초) 6a→110b(ㅇ초) 6b→1100(ㄱ초) 6c→110c(ㅈ초) 6d→1112(ㅎ초)
6e→1109(ㅅ초) 6f→110e(ㅊ초) 70→1111(ㅍ초) 71→11ba(ㅅ종) 72→1162(ㅐ중) 73→11ab(ㄴ종) 74→1165(ㅓ중)
75→1103(ㄷ초) 76→1169(ㅗ중) 77→11af(ㄹ종) 78→11a8(ㄱ종) 79→1105(ㄹ초) 7a→11b7(ㅁ종) 7b→0025(%)
7c→005c(\) 7d→002f(/) 7e→203b(※)
```

## Appendix B — Combination table (compound jamo, libhangul, verbatim)

Source: `hangul-combination-default.xml`. `first + second → result` (Unicode).

```
1100+1100→1101  1100+1109→11aa  1102+110c→11ac  1102+1112→11ad  1103+1103→1104
1105+1100→11b0  1105+1106→11b1  1105+1107→11b2  1105+1109→11b3  1105+1110→11b4
1105+1111→11b5  1105+1112→11b6  1107+1107→1108  1107+1109→11b9  1109+1109→110a
110c+110c→110d
1169+1161→116a  1169+1162→116b  1169+1175→116c  116e+1165→116f  116e+1166→1170
116e+1175→1171  1173+1175→1174
11a8+11a8→11a9  11a8+11ba→11aa  11ab+11bd→11ac  11ab+11c2→11ad  11af+11a8→11b0
11af+11b7→11b1  11af+11b8→11b2  11af+11ba→11b3  11af+11c0→11b4  11af+11c1→11b5
11af+11c2→11b6  11b8+11ba→11b9  11ba+11ba→11bb
```
