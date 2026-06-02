# Design: Simplify the menu-bar IME indicator icons (monochrome template)

Date: 2026-06-03
Status: Approved (Concept A)
Scope: macOS app target (`OSX`), asset catalog only — no Info.plist, no source code change.

## Goal

Make the menu-bar input-mode indicator icons simpler and more macOS-native by
converting them from colored, slightly skeuomorphic cloud+label icons into flat
**monochrome template** icons that auto-adapt to the light/dark menu bar.

"A bit simpler" (사용자 요청: "조금 더 심플하게") — keep the 구름 (cloud) brand,
drop color and visual weight, and reduce multi-character labels to single
characters that stay legible at 16 px.

## Current state (what exists today)

- 8 distinct icon files, each an imageset in `OSX/Assets.xcassets`, referenced
  **by filename** from `OSX/Info.plist` via `tsInputModeMenuIconFileKey` /
  `tsInputModeAlternateMenuIconFileKey` / `tsInputModePaletteIconFileKey`.
- The PNGs ship **only inside the compiled `Assets.car`** (no loose copies in
  `Contents/Resources`). The Text Input system resolves `han2.png` etc. through
  the asset catalog by name, so replacing the imageset PNGs is sufficient.
- Each imageset has `@1x` (16 px) + `@2x` (32 px), `universal` idiom, no
  appearance (light/dark) variants. The same colored PNG is used in both menu
  bar appearances today.
- Visual style today: colored cloud (Korean = blue, English = orange) with the
  label drawn **below** the cloud as small colored text (or none for `eng` /
  `han` (안마태)).

### Mode → icon mapping (from Info.plist, 16 modes → 8 icons)

| icon file   | input modes                                                                 | current label |
|-------------|------------------------------------------------------------------------------|---------------|
| `eng`       | system, colemak, dvorak                                                       | (none)        |
| `qwerty`    | qwerty (구름 로마자 QWERTY)                                                   | QW            |
| `han`       | hanahnmatae (안마태)                                                          | (none)        |
| `han2`      | han2, han2classic (두벌식)                                                    | 2             |
| `han3`      | han3-2011, han3-2012, han3classic, han3layout2, han3noshift (세벌식)          | 3             |
| `han390`    | han390 (세벌식 390)                                                           | 390           |
| `han3final` | han3final, han3finalnoshift (세벌식 최종)                                     | 3F            |
| `hanroman`  | hanroman (한글 로마자)                                                        | ROM           |

## Chosen design — Concept A: cloud silhouette + knockout label

A single, flat cloud silhouette fills the full tile. The mode label is **punched
out (knocked out / transparent)** of the cloud body, so the menu-bar background
shows through the glyph. Because the image is a template, the cloud renders near-
black on a light menu bar and near-white on a dark menu bar; the knockout shows
the bar color either way.

Rationale for Concept A over the "label below the cloud" variant (A2):
- The cloud uses the full 16 px height, so the knockout glyph is larger and more
  legible at real menu-bar size than a stacked cloud + sub-label.
- Forces the simplification the user asked for (single-char labels).
- Trade-off accepted: it changes the label placement from "below" to "inside".

### Cloud shape

Flattened, single-fill cloud: a rounded base bar plus three overlapping bumps
(left small, center large, right medium), unioned with non-zero winding. No
gradient, no outline, no inner shading. Same silhouette at @1x and @2x.

### Label scheme (single character, knockout)

| icon file   | new label | notes                                              |
|-------------|-----------|----------------------------------------------------|
| `eng`       | (none)    | plain cloud = English/roman default                |
| `han2`      | 2         |                                                    |
| `han3`      | 3         |                                                    |
| `han390`    | 9         | from "390"; the 9 distinguishes it from plain 3    |
| `han3final` | F         | from "3F" (final)                                  |
| `hanroman`  | R         | from "ROM" (roman)                                 |
| `qwerty`    | Q         | from "QW"                                          |
| `han`       | 안        | 안마태; resolves eng/han collision (see Risks)      |

Color is gone, so the **label presence carries the Korean/English distinction**:
a bare cloud is unambiguously English; every Korean/special mode carries a label.
This is why `han` (안마태), previously a bare blue cloud, must gain a label.

## Dark-mode mechanism (primary risk)

Plan: render each PNG as **black + alpha** (cloud = opaque black, label = fully
transparent knockout), and mark each imageset as a template image in its
`Contents.json`:

```json
"properties" : { "template-rendering-intent" : "template" }
```

When loaded via the asset catalog by name, this yields an `NSImage` with
`isTemplate == true`, which AppKit tints to match the destination appearance.

**Uncertainty:** it is not verified that the macOS input-source menu agent
(`TextInputMenuAgent`, a system process that draws the menu-bar IME icon from our
bundle) honors template tinting for IME icons. This MUST be verified on device in
both light and dark menu bars.

**Fallback if template tinting is not honored** (e.g. dark menu bar shows a solid
black, near-invisible cloud): provide explicit appearance variants in the asset
catalog — an "Any" (black) image and a "Dark" (white) image per imageset — so the
system picks the correct one by the menu bar's effective appearance. Keep the
same knockout label.

## Scope of change

Change only these 8 imagesets, both scales (16 PNGs total):
`eng, han, han2, han3, han390, han3final, hanroman, qwerty`.

Out of scope / unchanged:
- `OSX/Info.plist` (filenames unchanged → no plist edit, no re-registration).
- Application source code.
- `AppIcon.appiconset`, `OSXTestApp` assets, `Preferences/Example.png`,
  `OSX/Icons/*` (colemak/dvorak/command/libhangul there are not the menu-bar
  indicators).

## Generation (reproducibility)

Icons are generated programmatically with a small AppKit/Swift script (drafted
during brainstorming) so future tweaks are reproducible and diffable:

- Script committed under `OSX/Icons/generate-menubar-icons.swift`.
- Emits all 16 PNGs (8 modes × @1x/@2x) as black+alpha templates with knockout
  labels, written directly into the imageset directories.
- `swift OSX/Icons/generate-menubar-icons.swift` regenerates everything.

## Verification

1. Build a signed Release (per session gotcha #11: `DEVELOPMENT_TEAM=G7J2LY4LP9
   CODE_SIGN_STYLE=Automatic CODE_SIGN_IDENTITY="Apple Development"
   -allowProvisioningUpdates`, with `CURRENT_PROJECT_VERSION`/`MARKETING_VERSION`
   overrides), keeping `OSX/Version.xcconfig` out of the diff.
2. Install to `/Library/Input Methods/` (osascript admin, per gotcha #1).
3. On device, in BOTH light and dark menu bar:
   - cloud + label render correctly tinted (not invisible) — the template risk.
   - toggling Han/Eng and switching among 두벌식 / 세벌식 / 세벌식 최종 / 390 /
     로마자 / QWERTY shows the matching label.
   - legibility acceptable at real size (esp. 안마태 "안" at 16 px — see Risks).
4. Existing tests still pass (only the known unsigned
   `GureumObjCTests.testIPMDServerClientWrapper` may fail, pre-existing).

## Risks / open items

- **R1 (primary): template tinting in the system IME menu is unverified.** If
  dark mode renders the cloud invisible, apply the appearance-variant fallback.
- **R2: 안마태 "안" knockout at 16 px is dense** (a Hangul syllable is complex at
  ~8 px). Accepted because 안마태 is a niche layout and retina (@2x) renders it
  fine; revisit with a simpler mark on device if unacceptable.
- **R3: single-char compression loses some specificity** (390→9, final→F,
  roman→R). Acceptable: the menu lists full names; the icon only needs a quick
  family hint, and this is the simplification requested.

## Success criteria

- All 8 menu-bar indicator icons are flat monochrome templates that look correct
  in both light and dark menu bars on device.
- Han/Eng and the Korean layout variants remain distinguishable at a glance.
- No Info.plist or code change; icons regenerable from a committed script.
