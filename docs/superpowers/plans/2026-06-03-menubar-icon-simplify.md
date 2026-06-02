# Menu-bar IME Icon Simplification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the 8 colored cloud+label menu-bar indicator icons with flat monochrome **template** icons (cloud silhouette + single-character knockout label) that auto-adapt to light/dark menu bars.

**Architecture:** A committed AppKit/Swift generator script deterministically renders all 16 PNGs (8 imagesets × @1x 16px / @2x 32px) as black+alpha templates — opaque black cloud with the label knocked out to transparent. Each imageset's `Contents.json` is marked `template-rendering-intent: template` so AppKit tints the shape per appearance. No Info.plist or source-code change (filenames unchanged → no re-registration).

**Tech Stack:** Swift 6 + AppKit (NSBezierPath, NSBitmapImageRep, CoreText text knockout via `.destinationOut`), Xcode asset catalogs, `sips` for verification.

**TDD note:** This is deterministic asset generation, not logic — there is no unit under test. The verification gates that replace tests are: (a) the generator's printed alpha stats, (b) `sips` dimension/alpha checks, (c) a rendered contact sheet inspected visually, (d) a successful signed build, and (e) on-device light/dark rendering. Each task ends with a concrete verify step before commit.

---

## File Structure

- **Create** `OSX/Icons/generate-menubar-icons.swift` — the committed, reproducible generator. Sole responsibility: render the 16 template PNGs into the imageset directories and print per-file alpha stats.
- **Modify (overwrite)** the 16 PNGs under `OSX/Assets.xcassets/{eng,han,han2,han3,han390,han3final,hanroman,qwerty}.imageset/` — produced by the generator.
- **Modify** the 8 `Contents.json` in those imagesets — add `template-rendering-intent`.
- **Create (ephemeral, not committed)** `/tmp/gureum-icon-verify/verify.swift` — contact-sheet renderer that loads the committed PNGs and simulates light/dark template tinting for visual review.
- **Unchanged:** `OSX/Info.plist`, all source, `AppIcon.appiconset`, `OSXTestApp`, `OSX/Icons/*.png`.

Label scheme (from spec): `eng`→(none), `han`→안, `han2`→2, `han3`→3, `han390`→9, `han3final`→F, `hanroman`→R, `qwerty`→Q.

---

## Task 1: Add the icon generator and regenerate the 16 PNGs

**Files:**
- Create: `OSX/Icons/generate-menubar-icons.swift`
- Modify (overwritten by run): `OSX/Assets.xcassets/{eng,han,han2,han3,han390,han3final,hanroman,qwerty}.imageset/<name>.png` and `<name>@2x.png`

- [ ] **Step 1: Write the generator script**

Create `OSX/Icons/generate-menubar-icons.swift` with exactly:

```swift
import AppKit

// Cloud silhouette (rounded base bar + three overlapping bumps), normalized to `rect`.
func cloudPath(in rect: NSRect) -> NSBezierPath {
    func p(_ nx: CGFloat, _ ny: CGFloat) -> NSPoint {
        NSPoint(x: rect.minX + nx * rect.width, y: rect.minY + ny * rect.height) }
    func r(_ n: CGFloat) -> CGFloat { n * rect.width }
    let path = NSBezierPath()
    path.append(NSBezierPath(roundedRect: NSRect(x: p(0.12, 0.30).x, y: p(0, 0.30).y,
        width: r(0.76), height: r(0.24)), xRadius: r(0.12), yRadius: r(0.12)))
    func circle(_ cx: CGFloat, _ cy: CGFloat, _ rad: CGFloat) {
        let c = p(cx, cy)
        path.append(NSBezierPath(ovalIn: NSRect(x: c.x - r(rad), y: c.y - r(rad),
            width: r(rad) * 2, height: r(rad) * 2))) }
    circle(0.33, 0.48, 0.15); circle(0.53, 0.56, 0.21); circle(0.71, 0.49, 0.16)
    path.windingRule = .nonZero
    return path
}

// Render one icon at `size`px as black+alpha template: opaque black cloud, label knocked out to alpha 0.
func renderIcon(size: Int, label: String?) -> NSBitmapImageRep {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    ctx.shouldAntialias = true
    NSColor.black.setFill()
    cloudPath(in: NSRect(x: 0, y: 0, width: s, height: s).insetBy(dx: s * 0.04, dy: s * 0.04)).fill()
    if let label = label, !label.isEmpty {
        ctx.compositingOperation = .destinationOut   // erase label region -> alpha 0
        let fs = s * (label.count >= 2 ? 0.34 : 0.50)
        let font = NSFont.systemFont(ofSize: fs, weight: .heavy)
        let str = NSAttributedString(string: label,
            attributes: [.font: font, .foregroundColor: NSColor.black])
        let sz = str.size()
        str.draw(at: NSPoint(x: s / 2 - sz.width / 2, y: s / 2 - sz.height / 2 - s * 0.03))
        ctx.compositingOperation = .sourceOver
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func alphaStats(_ rep: NSBitmapImageRep) -> (opaque: Int, transparent: Int) {
    var opaque = 0, transparent = 0
    for y in 0..<rep.pixelsHigh {
        for x in 0..<rep.pixelsWide {
            let a = rep.colorAt(x: x, y: y)?.alphaComponent ?? 0
            if a > 0.5 { opaque += 1 } else { transparent += 1 }
        }
    }
    return (opaque, transparent)
}

// arg 1 (optional): path to Assets.xcassets (default assumes run from repo root)
let assetsDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "OSX/Assets.xcassets"

let icons: [(String, String?)] = [
    ("eng", nil), ("han", "안"), ("han2", "2"), ("han3", "3"),
    ("han390", "9"), ("han3final", "F"), ("hanroman", "R"), ("qwerty", "Q"),
]

for (name, label) in icons {
    for (suffix, size) in [("", 16), ("@2x", 32)] {
        let rep = renderIcon(size: size, label: label)
        guard let data = rep.representation(using: .png, properties: [:]) else { fatalError("png fail") }
        let path = "\(assetsDir)/\(name).imageset/\(name)\(suffix).png"
        try! data.write(to: URL(fileURLWithPath: path))
        let st = alphaStats(rep)
        print("wrote \(path)  opaque=\(st.opaque) transparent=\(st.transparent)")
    }
}
print("done: \(icons.count) imagesets x 2 scales = \(icons.count * 2) png")
```

- [ ] **Step 2: Run the generator from the repo root**

Run: `cd /Users/bglee/Project/gureum && swift OSX/Icons/generate-menubar-icons.swift`
Expected: 16 lines like `wrote OSX/Assets.xcassets/han2.imageset/han2@2x.png  opaque=NNN transparent=NNN`, then `done: 8 imagesets x 2 scales = 16 png`. For every line `opaque > 0` and `transparent > 0` (cloud present + background/knockout present). `eng` lines have only background transparency (still `transparent > 0`).

- [ ] **Step 3: Verify dimensions and alpha of the regenerated PNGs**

Run:
```bash
cd /Users/bglee/Project/gureum
for n in eng han han2 han3 han390 han3final hanroman qwerty; do
  for s in "" "@2x"; do
    f="OSX/Assets.xcassets/$n.imageset/$n$s.png"
    sips -g pixelWidth -g pixelHeight -g hasAlpha "$f" | tr '\n' ' '; echo "  $f"
  done
done
```
Expected: every `""` file reports `pixelWidth: 16 pixelHeight: 16 hasAlpha: yes`; every `@2x` reports `pixelWidth: 32 pixelHeight: 32 hasAlpha: yes`.

- [ ] **Step 4: Commit the generator and regenerated icons**

```bash
cd /Users/bglee/Project/gureum
git add OSX/Icons/generate-menubar-icons.swift OSX/Assets.xcassets/eng.imageset OSX/Assets.xcassets/han.imageset OSX/Assets.xcassets/han2.imageset OSX/Assets.xcassets/han3.imageset OSX/Assets.xcassets/han390.imageset OSX/Assets.xcassets/han3final.imageset OSX/Assets.xcassets/hanroman.imageset OSX/Assets.xcassets/qwerty.imageset
git commit -m "Generate monochrome template menu-bar icons

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Visually verify the generated icons in light & dark

**Files:**
- Create (ephemeral, NOT committed): `/tmp/gureum-icon-verify/verify.swift`

- [ ] **Step 1: Write the contact-sheet verifier**

This loads the ACTUAL committed PNGs and simulates template tinting (black on a light bar, white on a dark bar via `.sourceAtop`). Create `/tmp/gureum-icon-verify/verify.swift`:

```swift
import AppKit

let assets = "/Users/bglee/Project/gureum/OSX/Assets.xcassets"
let modes = ["eng", "han2", "han3", "han390", "han3final", "hanroman", "qwerty", "han"]

func loadRep(_ path: String) -> NSBitmapImageRep {
    let d = try! Data(contentsOf: URL(fileURLWithPath: path))
    return NSBitmapImageRep(data: d)!
}

// Draw a black+alpha template `rep` at `rect`, tinted to `tint` (preserves alpha holes).
func drawTinted(_ rep: NSBitmapImageRep, in rect: NSRect, tint: NSColor) {
    let img = NSImage(size: NSSize(width: rep.pixelsWide, height: rep.pixelsHigh))
    img.addRepresentation(rep)
    img.draw(in: rect)
    let ctx = NSGraphicsContext.current!
    ctx.saveGraphicsState()
    ctx.compositingOperation = .sourceAtop
    tint.setFill()
    rect.fill()
    ctx.restoreGraphicsState()
}

func text(_ s: String, _ pt: NSPoint, _ sz: CGFloat, _ c: NSColor) {
    NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: sz, weight: .semibold),
        .foregroundColor: c]).draw(at: pt) }

let W: CGFloat = 760, H: CGFloat = 320
let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
NSColor.white.setFill(); NSRect(x: 0, y: 0, width: W, height: H).fill()

struct Panel { let name: String; let bar: NSColor; let tint: NSColor; let yTop: CGFloat }
let panels = [
    Panel(name: "LIGHT menu bar (template tint = black)", bar: NSColor(white: 0.95, alpha: 1), tint: NSColor(white: 0.12, alpha: 1), yTop: H - 20),
    Panel(name: "DARK menu bar (template tint = white)",  bar: NSColor(white: 0.16, alpha: 1), tint: NSColor(white: 0.97, alpha: 1), yTop: H / 2 - 6),
]
for panel in panels {
    let ph: CGFloat = 130, py = panel.yTop - ph
    panel.bar.setFill(); NSRect(x: 12, y: py, width: W - 24, height: ph).fill()
    text(panel.name, NSPoint(x: 22, y: panel.yTop - 18), 11, panel.tint)
    var x: CGFloat = 26
    let colW = (W - 52) / CGFloat(modes.count)
    let rowY = panel.yTop - 40
    for m in modes {
        let r1 = loadRep("\(assets)/\(m).imageset/\(m)@2x.png")   // 32px
        let r2 = loadRep("\(assets)/\(m).imageset/\(m).png")      // 16px
        drawTinted(r1, in: NSRect(x: x, y: rowY - 48, width: 48, height: 48), tint: panel.tint)
        drawTinted(r1, in: NSRect(x: x + 52, y: rowY - 48, width: 32, height: 32), tint: panel.tint)
        drawTinted(r2, in: NSRect(x: x + 52, y: rowY - 48 - 19, width: 16, height: 16), tint: panel.tint)
        text(m, NSPoint(x: x, y: rowY - 66), 8.5, panel.tint)
        x += colW
    }
}
NSGraphicsContext.restoreGraphicsState()
try! out.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/tmp/gureum-icon-verify/contact.png"))
print("wrote /tmp/gureum-icon-verify/contact.png")
```

- [ ] **Step 2: Run the verifier and inspect**

Run: `cd /tmp/gureum-icon-verify && swift verify.swift`
Expected: `wrote /tmp/gureum-icon-verify/contact.png`. Then open/Read `/tmp/gureum-icon-verify/contact.png` and confirm:
- On BOTH panels the cloud silhouette is visible (black on light, white on dark) — not blank, not a solid block.
- Knockout labels (2/3/9/F/R/Q/안) are readable at 48px and @2x(32px); tight-but-present at @1x(16px).
- `eng` is a plain cloud (no hole); every other mode shows its hole.

If any label is wrong or illegible, adjust `renderIcon` in the generator (font size factor, y-nudge, or label string), re-run Task 1 Step 2, and re-run this step. Do NOT commit the verifier.

---

## Task 3: Mark the 8 imagesets as template images

**Files:**
- Modify: `OSX/Assets.xcassets/{eng,han,han2,han3,han390,han3final,hanroman,qwerty}.imageset/Contents.json`

- [ ] **Step 1: Add `template-rendering-intent` to every imageset**

Each current `Contents.json` ends with an `"info"` block and no `"properties"`. Add a `properties` block. The target shape for each file (example shown for `han2`, identical `properties` for all 8):

```json
{
  "images" : [
    { "idiom" : "universal", "filename" : "han2.png", "scale" : "1x" },
    { "idiom" : "universal", "filename" : "han2@2x.png", "scale" : "2x" },
    { "idiom" : "universal", "scale" : "3x" }
  ],
  "info" : { "version" : 1, "author" : "xcode" },
  "properties" : { "template-rendering-intent" : "template" }
}
```

Apply with this script (idempotent — uses Python to insert the key, preserving each file's existing `images`):

```bash
cd /Users/bglee/Project/gureum
python3 - <<'PY'
import json, os
base = "OSX/Assets.xcassets"
for n in ["eng","han","han2","han3","han390","han3final","hanroman","qwerty"]:
    p = f"{base}/{n}.imageset/Contents.json"
    with open(p) as f: d = json.load(f)
    d["properties"] = {"template-rendering-intent": "template"}
    with open(p, "w") as f:
        json.dump(d, f, indent=2); f.write("\n")
    print("updated", p)
PY
```

- [ ] **Step 2: Verify every Contents.json is valid JSON with the template intent**

Run:
```bash
cd /Users/bglee/Project/gureum
python3 - <<'PY'
import json
base = "OSX/Assets.xcassets"
for n in ["eng","han","han2","han3","han390","han3final","hanroman","qwerty"]:
    d = json.load(open(f"{base}/{n}.imageset/Contents.json"))
    assert d["properties"]["template-rendering-intent"] == "template", n
    print(n, "OK")
print("all 8 OK")
PY
```
Expected: 8 `OK` lines then `all 8 OK`, no traceback.

- [ ] **Step 3: Commit**

```bash
cd /Users/bglee/Project/gureum
git add OSX/Assets.xcassets/eng.imageset/Contents.json OSX/Assets.xcassets/han.imageset/Contents.json OSX/Assets.xcassets/han2.imageset/Contents.json OSX/Assets.xcassets/han3.imageset/Contents.json OSX/Assets.xcassets/han390.imageset/Contents.json OSX/Assets.xcassets/han3final.imageset/Contents.json OSX/Assets.xcassets/hanroman.imageset/Contents.json OSX/Assets.xcassets/qwerty.imageset/Contents.json
git commit -m "Mark menu-bar icon imagesets as template images

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Build (signed Release) and run tests

**Files:** none modified (verification only).

- [ ] **Step 1: Fetch tags (needed by the version xcconfig generator)**

Run: `cd /Users/bglee/Project/gureum && git fetch --tags`
Expected: completes without error.

- [ ] **Step 2: Build a signed Release**

Run (single line; per session gotcha #11 — overrides only on the command line, do not edit pbxproj):
```bash
cd /Users/bglee/Project/gureum && xcodebuild -project Gureum.xcodeproj -scheme OSX -configuration Release -derivedDataPath build/DerivedData-signed CURRENT_PROJECT_VERSION=1.13 MARKETING_VERSION=1.13.2 DEVELOPMENT_TEAM=G7J2LY4LP9 CODE_SIGN_STYLE=Automatic CODE_SIGN_IDENTITY="Apple Development" -allowProvisioningUpdates build
```
Expected: ends with `** BUILD SUCCEEDED **`. (First signing may prompt for the login-keychain password — choose Always Allow.)

- [ ] **Step 3: Restore the generated version xcconfig if the build dirtied it**

Run: `cd /Users/bglee/Project/gureum && git checkout -- OSX/Version.xcconfig 2>/dev/null; git status --short`
Expected: working tree shows no unintended changes (only build/ which is git-ignored). `OSX/Version.xcconfig` must not be staged.

- [ ] **Step 4: Confirm the new icons are inside the built bundle's Assets.car**

Run:
```bash
cd /Users/bglee/Project/gureum
APP=$(find build/DerivedData-signed -name Gureum.app -maxdepth 6 -type d | head -1)
ls -la "$APP/Contents/Resources/Assets.car"
```
Expected: `Assets.car` exists with a recent timestamp (the asset catalog was recompiled with the new PNGs). No separate per-icon files are expected (icons live in the car).

---

## Task 5: On-device install and light/dark verification (USER-DRIVEN)

**Files:** none (manual verification; resolves spec risk R1/R2).

- [ ] **Step 1: Install the signed build to /Library/Input Methods**

Run (admin via osascript — per gotcha #1, sudo has no TTY here):
```bash
cd /Users/bglee/Project/gureum
APP=$(find build/DerivedData-signed -name Gureum.app -maxdepth 6 -type d | head -1)
osascript -e "do shell script \"rm -rf '/Library/Input Methods/Gureum.app' && cp -R '$PWD/$APP' '/Library/Input Methods/'\" with administrator privileges"
```
Expected: no error. Then log out/in (or `killall Gureum` and reselect) so the input method reloads. Per gotcha #5, the input source may need re-adding in System Settings, and Input Monitoring TCC persists because the Apple Development signature is stable (gotcha #11).

- [ ] **Step 2: Verify in the LIGHT menu bar**

With the menu bar in light appearance, switch among 영문 / 두벌식 / 세벌식 / 세벌식 최종 / 390 / 한글 로마자 / QWERTY (and 안마태 if enabled). Expected: a dark cloud with the correct knockout label (2/3/9/F/R/Q/안), `eng` a plain dark cloud. Confirm labels are legible at real size.

- [ ] **Step 3: Verify in the DARK menu bar**

Switch the system/menu-bar appearance to dark and repeat. Expected (the spec's primary risk R1): the cloud renders **light/white and clearly visible**, knockout shows the dark bar through the label.

- [ ] **Step 4: Decide pass/fail**

PASS → proceed to Task 6. If the DARK menu bar shows an invisible/near-black cloud (template tinting NOT honored by the IME menu agent), STOP and do Task 5b (fallback). If only 안마태 "안" is too dense at 16px (R2) but everything else is fine, note it and proceed (acceptable for a niche layout) or pick a simpler mark and re-run Task 1.

---

## Task 5b: CONDITIONAL fallback — explicit light/dark appearance variants

Only if Task 5 Step 4 found the dark menu bar renders the cloud invisible.

**Files:**
- Modify: `OSX/Icons/generate-menubar-icons.swift` (emit a white `~dark` variant)
- Modify: the 8 PNGs gain `<name>~dark.png` / `<name>@2x~dark.png` siblings
- Modify: the 8 `Contents.json` to declare `Any` + `Dark` luminosity appearances

- [ ] **Step 1: Emit white dark-variant PNGs**

In `renderIcon`, parameterize the fill color and add a second output pass. Change the fill line and the loop:

```swift
func renderIcon(size: Int, label: String?, fill: NSColor) -> NSBitmapImageRep {
    // ... identical, but replace `NSColor.black.setFill()` with `fill.setFill()`
    //     and keep the knockout block using `.destinationOut` (color-independent).
}
```
And in the output loop, write both:
```swift
for (suffix, size) in [("", 16), ("@2x", 32)] {
    for (variant, fill) in [("", NSColor.black), ("~dark", NSColor.white)] {
        let rep = renderIcon(size: size, label: label, fill: fill)
        let data = rep.representation(using: .png, properties: [:])!
        try! data.write(to: URL(fileURLWithPath: "\(assetsDir)/\(name).imageset/\(name)\(suffix)\(variant).png"))
    }
}
```
Run: `swift OSX/Icons/generate-menubar-icons.swift`. Expected: now 32 PNGs (adds `~dark` siblings).

- [ ] **Step 2: Declare appearances in each Contents.json**

Target shape per imageset (example `han2`): two image entries per scale, `Any` (no appearances) + `Dark`:
```json
{
  "images" : [
    { "idiom":"universal", "filename":"han2.png", "scale":"1x" },
    { "idiom":"universal", "filename":"han2~dark.png", "scale":"1x",
      "appearances":[{"appearance":"luminosity","value":"dark"}] },
    { "idiom":"universal", "filename":"han2@2x.png", "scale":"2x" },
    { "idiom":"universal", "filename":"han2@2x~dark.png", "scale":"2x",
      "appearances":[{"appearance":"luminosity","value":"dark"}] },
    { "idiom":"universal", "scale":"3x" }
  ],
  "info" : { "version":1, "author":"xcode" }
}
```
Apply with a Python script over the 8 imagesets (drop `template-rendering-intent`; appearances replace it). Then verify each parses with `json.load`.

- [ ] **Step 3: Rebuild (Task 4), reinstall (Task 5 Step 1), re-verify light & dark, then commit**

```bash
git add OSX/Icons/generate-menubar-icons.swift OSX/Assets.xcassets/*.imageset
git commit -m "Fallback: explicit light/dark menu-bar icon variants

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: Finalize

- [ ] **Step 1: Update worklog**

Append a dated line to `.claude/worklog.md` summarizing: monochrome template menu-bar icons (Concept A), 8 imagesets regenerated via committed `OSX/Icons/generate-menubar-icons.swift`, template-rendering-intent set, on-device light/dark result (and whether fallback Task 5b was needed).

- [ ] **Step 2: Offer branch completion**

Invoke superpowers:finishing-a-development-branch to choose merge / PR / cleanup for `feature/menubar-icon-simplify`.

---

## Self-Review

**Spec coverage:**
- Concept A cloud + knockout label → Task 1 (`renderIcon`). ✓
- Label scheme (none/안/2/3/9/F/R/Q) → Task 1 `icons` array. ✓
- 8 imagesets, @1x+@2x only, no Info.plist/code change → Task 1 scope + Task 4 Step 3 (Version.xcconfig untouched). ✓
- Template mechanism → Task 3. ✓
- Dark-mode primary risk R1 + appearance-variant fallback → Task 5 Step 3-4 + Task 5b. ✓
- 안마태 R2 legibility → Task 2 Step 2 + Task 5 Step 4. ✓
- Reproducible generator committed at `OSX/Icons/generate-menubar-icons.swift` → Task 1. ✓
- Verification (build signed Release, tests, on-device) → Task 4 + Task 5. ✓

**Placeholder scan:** No TBD/TODO; all code blocks complete; the only conditional is Task 5b, explicitly gated on a Task 5 outcome with full steps. ✓

**Type consistency:** `renderIcon(size:label:)` defined in Task 1 is re-signatured to `renderIcon(size:label:fill:)` only in the fallback Task 5b (called out explicitly). `cloudPath`, `alphaStats`, `drawTinted` names are used consistently. The `icons` label map matches the spec table and Task 2's `modes` list (same 8 names). ✓
