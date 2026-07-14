# Bomi — Han/Eng switching via system input modes (design)

Date: 2026-07-14
Status: approved
Supersedes: §6.3 (in-IME han/eng toggle) and §6.5 (per-app memory) of
`2026-07-14-bomi-sebeolsik-ime-design.md`. Everything else in that spec
(Sebeolsik-final automaton, per-syllable commit, IMK bridging) stands.

## Problem

The shipped design toggles Han/Eng with an **internal boolean** inside a single
input mode. macOS therefore never learns the mode changed, so the menu-bar
indicator can never update — the user sees the same icon in Korean and English.
Swapping the icon file cannot fix this; the indicator is driven by which **input
source** is active, not by IME-internal state.

Confirmed against Gureum (`OSXCore/InputReceiver.swift`), which declares Korean
and Roman as **separate input modes** and switches the system input source on
toggle. Its own comment states this is what makes the menu-bar 한/A icon refresh.

A tempting shortcut — switching to the system ABC layout for English — is wrong:
it **deactivates our IME**, so Right-Command never reaches us again and the
toggle becomes one-way. Gureum avoids this with its own Roman mode; so do we.

## Design

### Input modes (Info.plist `ComponentInputModeDict`)

Two modes, both visible, both ours:

| Mode id | `TISIntendedLanguage` | Menu-bar icon | Behavior |
|---|---|---|---|
| `com.bomi.inputmethod.bomi.korean` | `ko` | `statusbomi_han` (ㅂ) | Sebeolsik-final composition |
| `com.bomi.inputmethod.bomi.roman`  | `en` | `statusbomi_eng` (B) | keys pass through, no composition |

Each mode sets `tsInputModeMenuIconFileKey`, `tsInputModeAlternateMenuIconFileKey`,
`tsInputModePaletteIconFileKey` (Gureum sets all three per mode), plus
`tsInputModeIsVisibleKey`. Both ids are listed in
`tsVisibleInputModeOrderedArrayKey`. Localize both mode ids in
`Resources/<lang>.lproj/InfoPlist.strings` (ko: 보미 / 로마자, en: Bomi / Roman).

### Toggle

Right-Command bare tap (detected by the existing pure `ToggleGate`) selects the
*other* mode:

1. `TISSelectInputSource` on the target mode's `TISInputSource` — the fast path
   (same mechanism as Ctrl-Opt-Space); the menu-bar icon refreshes immediately.
2. Fallback to `IMKTextInput.selectMode(id)` if the source is missing/disabled
   or selection fails. (Gureum notes `selectMode` alone is a ~1s slow path.)
3. Cache the `TISInputSource` ref per mode id; invalidate on selection failure.

Flush any in-progress syllable **before** switching.

### Language state ownership

The **active input mode is the single source of truth** — we no longer keep a
`korean` boolean or a per-app map.

- `activateServer` / `setValue(_:forTag:client:)` with
  `kTextServiceInputModePropertyTag` tell us the current mode id; store it and
  flush the composer on change.
- `handleKeyEvent` composes only when the active mode is `…korean`; in `…roman`
  it returns `false` (pass through).
- **Per-app memory is delegated to macOS** (System Settings ▸ Keyboard ▸ "switch
  input source per document/app"). We do not fight it.

### Removals

- `BomiCore/LanguageMode.swift` and its 3 tests — its whole purpose (global +
  per-app language state) is now owned by macOS.
- `Preferences.perAppMemory` and the "앱별 한/영 기억" menu item.

### Kept

`HangulComposer` and the whole `BomiEngine` (unchanged), `KeyTranslator`,
`ToggleGate`, `Preferences.toggleKeyCode`, the IMK concurrency bridging.

### Icons

Source: this user's Gureum fork (`~/Project/gureum/OSX`).

| Purpose | File | Sizes |
|---|---|---|
| Korean mode | `statusbomi_han.png` + `statusbomi_han@2x.png` | 16 / 32 |
| Roman mode | `statusbomi_eng.png` + `statusbomi_eng@2x.png` | 16 / 32 |
| Input-method / app icon | `bomi-input.png` (ㅂ logo) | 1024 |

Copy into `Resources/`. `assemble-app.sh` currently copies `Info.plist`,
`bomi.tiff`, and `*.lproj` individually — extend it to copy the icon PNGs too.
Replaces the current 16×16 `bomi.tiff` (`tsInputMethodIconFileKey` →
`bomi-input.png`).

**Dark variants are out of scope.** Gureum ships `_dark` PNGs but its own
`Info.plist` points `Menu`/`AlternateMenu`/`Palette` at the *same* light file per
mode — the dark files are selected in code via asset catalogs, which we don't
use. We ship the light PNGs only; macOS renders menu-bar icons appropriately. If
the icon reads poorly in dark mode, revisit then (do not pre-solve).

## Testing

- `ToggleGate` (pure, existing tests stand): bare tap vs chord.
- New pure unit: mode-id resolution — given active mode id, the toggle target is
  the other one; unknown id defaults to korean.
- `TISSelectInputSource` itself is a system call — not unit-testable; covered by
  manual verification.
- Manual (the point of the change): menu bar shows **ㅂ** in Korean and **B** in
  English, flips on Right-Command tap, both directions, and survives app switch.

## Risks

- **Registration**: adding a mode changes the input-source set; macOS caches it.
  A logout/login is required for the new Roman mode to appear (already learned:
  bundle id/mode changes need a TIS cache refresh).
- **Both modes visible**: the user will see two entries (보미, 로마자) in the
  input-source list. That is how Gureum behaves and is intended — the Roman entry
  is what the toggle switches to.
- `TISSelectInputSource` fails if the target mode is not enabled in System
  Settings. Fallback to `selectMode` covers it; if both fail we stay put (no
  silent breakage of composition).
