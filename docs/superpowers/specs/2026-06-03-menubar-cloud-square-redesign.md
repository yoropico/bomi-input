# Design: Fix squished menu-bar cloud — custom near-square bezier cloud

Date: 2026-06-03
Status: Approved, pre-implementation. Supersedes the "Sizing" decision in
`2026-06-03-ime-icon-simplify-design.md`. Scope: macOS app target (`OSX`),
asset catalog + generator only — no Info.plist, no source-code change.

## Problem (confirmed root cause)

On device the menu-bar cloud renders **horizontally squished** (찌그러짐).

Evidence chain:

1. The menu-bar icon is supplied via `OSX/Info.plist`
   `tsInputModeMenuIconFileKey => "han.png"` etc. — the Carbon Text Input
   Services **input-mode menu icon slot, which is a fixed square** (16×16 pt
   standard).
2. The currently installed `Assets.car` carries **24×16 / 48×32 (≈1.5:1 wide)**
   renditions — i.e. the uncommitted "wide tile" generator variant was built and
   installed.
3. The committed baseline (`cfcb945`) was square **16×16 / 32×32**.
4. The 24×16 PNG content itself is undistorted (natural cloud aspect).

So the distortion happens at **display time**: macOS scales the wide image into
the square slot **without preserving aspect ratio**, compressing the cloud
width to ~67%. The wide-tile generator's premise ("the menu bar scales icons by
height, so a wide tile fills full height undistorted") is **false** for this
slot — the slot is square and forces a square fit.

## Geometric constraint

A natural `cloud.fill` silhouette is ≈1.5:1 (wider than tall). In a **square**
slot you can only have two of {no distortion, no side-clip, fills height}:

- square tile + aspect-fit (cfcb945): no distortion, no clip, but cloud only
  ~67% of menu-bar height (looks small).
- wide tile (current bug): squished.
- square tile + height-fill of a wide cloud: side-clipped into a block
  (rejected on device earlier).

Filling the square's height **without distortion or clipping requires a glyph
whose aspect ≈ 1:1**. A literal wide cloud cannot do it; a custom chunkier cloud
can.

## Design (approved)

1. **Revert the tile to square** (16×16 @1x, 32×32 @2x) so it matches the square
   slot — eliminates the non-uniform scaling that causes the squish.
2. **Replace the stock SF Symbols** (`cloud.fill` / `cloud`) with a **single
   custom `NSBezierPath` cloud** whose tight bounds aspect is ≈ **1.05:1**
   (near-square, slightly wide), drawn to fill ~88% of the square tile.
   - **Korean (ko) modes → `path.fill()`** (solid cloud).
   - **English/roman (en) modes → `path.stroke(lineWidth:)`** (outline cloud).
   - One path, one source of truth; filled vs outline is the only difference —
     preserves the existing Korean-vs-English semantic.

### Cloud path shape

A chunky cumulus silhouette: near-flat bottom, three smooth rounded bumps on top
(left small, center tall, right medium), joined as one closed bezier. Tuned so
the bounding box is ≈1.05:1 and it still reads as a cloud at 16 px. Stylization
is explicit and accepted: this is a deliberately chunky, near-square cloud, not a
photo-accurate one — that is the only way to satisfy {square slot, large,
undistorted} together.

### Rendering (keep existing generator structure)

- Draw the path into a high-res canvas (256 px), then downscale to 16/32 px for
  crisp edges (same downscale approach as today).
- Outline stroke width ≈ 7–8% of canvas size so it survives at 16 px without
  muddying.
- Normalize to opaque black + alpha (template mask); `Contents.json`
  `template-rendering-intent: template` unchanged.
- Emit all 8 imagesets × @1x/@2x. Korean imagesets share the filled artwork;
  English imagesets share the outline artwork (as today).

## Scope of change

- `OSX/Icons/generate-menubar-icons.swift` — swap symbol source for the custom
  path; restore square tile.
- The 8 menu-bar imagesets (`eng, han, han2, han3, han390, han3final, hanroman,
  qwerty`), both scales (regenerated PNGs).
- **Unchanged:** `OSX/Info.plist`, all source, `Contents.json` template intent,
  `AppIcon.appiconset`, tests.

## Verification

1. Render candidates; **review actual 16/32 px PNGs** with the user; tune bump
   shape + stroke weight until accepted (no browser mockups — judge the real
   artifact).
2. Signed Release build (session gotcha #11 overrides; keep
   `OSX/Version.xcconfig` out of the diff). BUILD SUCCEEDED expected.
3. Install to `/Library/Input Methods/` (osascript admin, gotcha #1); restart
   Gureum.
4. On device, light **and** dark menu bar.

## Success criteria

- No distortion: the cloud is not horizontally compressed.
- The cloud fills the large majority of the menu-bar height (visibly bigger than
  the cfcb945 ~67% letterbox).
- Korean (filled) vs English (outline) distinguishable at a glance; outline not
  muddy at 16 px.
- Correct template tinting in both light and dark menu bars.
- No Info.plist or code change; icons regenerable from the committed script.

## Risks / open items

- **R1: outline legibility at 16 px** — a near-square outline cloud with thin
  strokes can muddy; mitigated by the proportional stroke weight, confirmed at
  the candidate-review step.
- **R2: stylized shape acceptance** — chunky cloud may read less "cloud-like";
  tuned at candidate review, bumps adjustable.
- **R3: template tinting** — verify white-on-dark on device (same check as the
  prior icon work).
