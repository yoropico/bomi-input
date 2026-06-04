# DKST (DINKIssTyle-IME-macOS) — source-level analysis vs bomi-input

Date: 2026-06-04. Source: https://github.com/DINKIssTyle/DINKIssTyle-IME-macOS (cloned shallow to
/tmp/dkst-research at research time; re-clone to revisit). Purpose: decide which DKST features are
worth porting into bomi-input.

## 0. Bottom line + LICENSE
- **DKST is MIT-licensed** (Copyright (c) 2025 DINKIssTyle). bomi-input descends from Gureum (BSD).
  => We MAY legally port code AND data (hanja.txt) into bomi-input, provided we keep the MIT copyright
  notice for any substantial borrowed portion. This is the key enabler.
- Highest-value, lowest-risk wins: (1) dictionary text-expansion, (2) Shift+jamo custom output.
  Highest-value, highest-risk: (3) inline direct-input (no underline). "모아치기" is likely already
  available in bomi via libhangul auto-reorder — verify before building.

## 1. Architecture
- Pure **Objective-C**, ~5,753 LOC. Heart is `Sources/InputController.m` (2,265 LOC).
- Files: InputController.m, DKSTHangul.m (460, **its OWN Hangul automaton — NOT libhangul**),
  DKSTHanjaDictionary.m (342), DKSTCompositionState.m (151), DKSTConstants.{h,m} (keyboard layouts),
  DKSTSettingsViewControllers.m (1158, settings UI), DKSTShortcutRecorder.m (539).
- bomi-input by contrast = Swift + **libhangul** automaton + standard IMKit marked-text composition.
- DKST's "CPU 1/2, fewer 병목, fewer 자소분리/로마자 on 영→한" claims trace to its hand-rolled
  automaton + the inline engine below. libhangul is itself fast; bomi can match the quality without
  swapping engines. Do NOT port DKSTHangul.m wholesale — bomi's libhangul is more battle-tested.

## 2. Distinctive features — implementation + bomi gap + port effort

### (A) Inline direct-input vs marked-text auto-switching — THE headline, HIGH effort
- Source: InputController.m tracks `_directInputComposedText/Length/Range`. Instead of always using
  `setMarkedText:` (underline composition), it `insertText:replacementRange:` committed text directly
  and re-replaces that range as composition evolves, giving "no underline" inline typing.
- Per-app engine policy: `bundleIdentifierUsesWebKitTextStack:`,
  `bundleIdentifierUsesChromiumMarkedTextPolicy:`, plus a user list
  `bundleIdentifierMatchesMarkedTextConfiguration:` (force marked text for listed Bundle IDs).
  `directInputRangeIsCurrent:` validates via `attributedSubstringFromRange:` that the inserted text
  is still present before replacing (handles stale ranges / app quirks).
- bomi today: ALWAYS marked-text (InputReceiver.updateComposition -> controller.updateComposition ->
  setMarkedText). No inline mode.
- Port: HIGH. Touches the InputController/InputReceiver commit/compose hot path + a per-app policy
  table + a settings list. Biggest UX upgrade but the riskiest (app-compat edge cases are why DKST
  needs 2,265 LOC and a user override list).

### (B) Shift + single jamo -> custom string/emoji — MEDIUM effort, independent
- Source: InputController.m `handleCustomShift:` maps Shift+<jamo key> to a user-defined output
  (e.g. Shift+ㅇ = "안녕하세요"). Configured in DKSTSettingsViewControllers (단자음/단모음 tab).
- bomi today: none.
- Port: MEDIUM. A key-event branch + a settings pane + stored mapping. Self-contained; no hot-path risk.

### (C) Dictionary text-expansion (trigger -> candidates) — MEDIUM effort, BEST ROI
- Source: DKSTHanjaDictionary.m loads `Resources/hanja.txt`, format `trigger:val1,val2,val3`
  (colon trigger, comma-separated candidates). Examples: `울:😢,😭,🥲,...`,
  `옛한글:ᄒᆞᆫ글 (아래아한글),...`, `ㅎ:→,←,↑,↓,...`. Parsed into an NSDictionary; also queries the
  **Apple system hanja dictionary** (`appleHanjaForHangul:`) and merges candidates.
- Trigger flow: type trigger, before commit press **Option+Enter** -> candidate window -> arrows +
  Enter/Space to pick (`handleHanjaConversion:`, `handleCandidateNavigation:`). Word triggers work by
  selecting (drag) then Option+Enter.
- Repurposed beyond hanja: emoji, Win-IME special-char tables (ㄱ/ㄴ/ㄷ... -> symbol sets), 옛한글.
- bomi today: has the candidate-window infrastructure (IMKCandidates) but no dictionary-expansion logic.
- Port: MEDIUM and the BEST ROI — reuses bomi's existing candidate window; the data file is MIT so it
  can be shipped as-is. Mostly: a dict loader + trigger detection + wire to IMKCandidates + a settings
  toggle/editor. The DICT editor UI (DKSTSettingsViewControllers) can be a later nicety.

### (D) Per-jamo backspace option — LOW/duplicate
- Source: DKSTHangul.m `backspace` (deletes by jamo even mid-composition; "글자 단위로 삭제" toggle).
- bomi: libhangul backspace already deletes by jamo while composing. Largely redundant; only the
  "delete whole syllable at once" toggle would be new.

### (E) 모아치기 (order-independent jamo: ㅏ+ㄱ=가) — likely ALREADY in bomi
- Source: DKSTHangul.m `moaJjikiEnabled`.
- bomi: `Configuration.hangulAutoReorder` maps to libhangul HANGUL_OPTION_AUTO_REORDER, which provides
  order-correction. VERIFY whether this already satisfies 모아치기 before building anything.

### (F) Shortcut non-interference (FCP V/B/A work) — partially in bomi
- bomi already passes Command/Control combos through (InputReceiver.input2 returns processed:false on
  .command/.control). DKST extends the philosophy further; assess specific gaps case by case.

### (G) Multiple selectable menu-bar icons at install — LOW value
- DKST's install.sh lets the user pick one of 7 status icons (Taegeuk/아래아한/한/가/Classic/Ang...).
  bomi ships a single brand glyph (ㅂ/B). Cosmetic; skip unless desired.

## 3. Recommended order for bomi-input (value / risk)
1. **Dictionary text-expansion (C)** — reuses our candidate window, MIT data included, contained. Best ROI.
2. **Shift+jamo custom output (B)** — independent, medium, high delight.
3. **Inline direct-input (A)** — biggest UX win but a hot-path rewrite; do as its own brainstormed project.
4. Verify **모아치기 (E)** is already covered by hangulAutoReorder before doing anything there.

## 4. Next step
Pick target feature(s) -> brainstorming -> spec -> implement. For (A) plan a dedicated design pass
(app-compat policy table + settings). Attribute DKST (MIT) for any substantial borrowed code/data.
