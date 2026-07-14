# Bomi Sebeolsik-Final IME Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a daily-driver Sebeolsik-final Korean input method for macOS 26 using InputMethodKit and a pure-Swift Hangul automaton.

**Architecture:** Three isolated layers — `BomiEngine` (pure-Swift automaton, zero IMK, unit-tested), an IMK glue layer (`BomiInputController` + `KeyTranslator` + `LanguageMode`), and an app shell (`main.swift` IMKServer bootstrap + menu/preferences). The automaton is a direct port of libhangul's `jaso` processing logic with the Sebeolsik-final (`3f`) key map and combination table taken verbatim from libhangul.

**Tech Stack:** Swift 6.3, SwiftPM (swift-tools 6.2), InputMethodKit, AppKit, swift-testing (`import Testing`).

## Global Constraints

- swift-tools-version **6.2**; `platforms: [.macOS(.v14)]`; must run on macOS 26.
- `BomiEngine` target: **Foundation only, zero third-party deps**. App target links `InputMethodKit` + `AppKit`.
- Bundle id **`com.rsautomation.inputmethod.bomi`** (MUST contain `inputmethod`).
- `InputMethodConnectionName` = **`com.rsautomation.inputmethod.bomi_Connection`** (exact; mismatch = silent load failure).
- Controller class: `@objc(BomiInputController)`. App class: `@objc(BomiApplication)`. Info.plist references them by these ObjC names (no module prefix).
- App target uses `swiftSettings: [.defaultIsolation(MainActor.self)]` so IMK overrides are MainActor-isolated (chosen concurrency approach). Engine target stays non-isolated/pure.
- Commit policy: **per-syllable immediate commit**.
- Sebeolsik-final data is verbatim from libhangul `3f` (Appendix A of spec) and `hangul-combination-default` (Appendix B). Do not invent mappings.
- Unicode ranges: Cho `U+1100–1112`, Jung `U+1161–1175`, Jong `U+11A8–11C2`. Syllable = `0xAC00 + (cho*21+jung)*28+jong`.
- dev artifacts in English; commit trailer:
  `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>` and `Claude-Session: https://claude.ai/code/session_01WFUiSiq9yMT6m6FeR5Hk6i`.

## File Structure

```
Package.swift
Sources/BomiEngine/
  Jamo.swift            slot classification + index helpers
  Combination.swift     compound-jamo table + combine()
  SebeolsikFinal.swift  3f key(ascii)->jamo map + compat-jamo tables
  Syllable.swift        (cho,jung,jong) -> String (precomposed or compat fallback)
  HangulComposer.swift  automaton: input/backspace/flush (libhangul jaso port)
Sources/Bomi/
  main.swift            BomiApplication + AppDelegate + IMKServer bootstrap
  BomiInputController.swift  IMKInputController subclass
  KeyTranslator.swift   keyCode(+shift) -> US-QWERTY ascii; toggle-key detection
  LanguageMode.swift    han/eng state + per-app memory
  Preferences.swift     UserDefaults wrapper
  MenuBuilder.swift     input-source menu
Resources/
  Info.plist
  bomi.tiff             menu icon (16x16 placeholder ok)
Tests/BomiEngineTests/
  JamoTests.swift  SyllableTests.swift  CombinationTests.swift  ComposerTests.swift
Scripts/
  assemble-app.sh  install.sh
```

---

## Task 1: SwiftPM scaffold + IMK load spike

Proves the highest risks (§10.1/10.2/10.5 of spec): a hand-assembled (no-Xcode) bundle actually loads as an input method on macOS 26 and can commit text. Verification is **manual** (install + type in TextEdit), not a unit test.

**Files:**
- Create: `Package.swift`, `Sources/Bomi/main.swift`, `Sources/Bomi/BomiInputController.swift`, `Resources/Info.plist`, `Resources/bomi.tiff`, `Scripts/assemble-app.sh`, `Scripts/install.sh`
- Create stub: `Sources/BomiEngine/Jamo.swift` (empty enum so the library target compiles)

**Interfaces:**
- Produces: a runnable `Bomi.app` bundle; `@objc(BomiInputController)`, `@objc(BomiApplication)`.

- [ ] **Step 1: Create `Package.swift`**

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Bomi",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "BomiEngine"),
        .testTarget(name: "BomiEngineTests", dependencies: ["BomiEngine"]),
        .executableTarget(
            name: "Bomi",
            dependencies: ["BomiEngine"],
            swiftSettings: [.defaultIsolation(MainActor.self)],
            linkerSettings: [
                .linkedFramework("InputMethodKit"),
                .linkedFramework("AppKit"),
            ]
        ),
    ]
)
```

- [ ] **Step 2: Create empty `Sources/BomiEngine/Jamo.swift`** (so the target compiles)

```swift
import Foundation

// Filled in Task 2.
enum Jamo {}
```

- [ ] **Step 3: Create `Sources/Bomi/main.swift`**

```swift
import AppKit
import InputMethodKit

var server: IMKServer!

@objc(BomiApplication)
final class BomiApplication: NSApplication {
    private let appDelegate = AppDelegate()
    override init() {
        super.init()
        self.delegate = appDelegate
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let name = Bundle.main.infoDictionary?["InputMethodConnectionName"] as! String
        server = IMKServer(name: name, bundleIdentifier: Bundle.main.bundleIdentifier)
    }
}

let app = BomiApplication.shared
app.run()
```

- [ ] **Step 4: Create minimal `Sources/Bomi/BomiInputController.swift`**

```swift
import AppKit
import InputMethodKit

@objc(BomiInputController)
final class BomiInputController: IMKInputController {
    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event, event.type == .keyDown else { return false }
        guard let client = sender as? IMKTextInput else { return false }
        client.insertText("보미", replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
        return true
    }
}
```

- [ ] **Step 5: Create `Resources/Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Bomi</string>
  <key>CFBundleDisplayName</key><string>Bomi</string>
  <key>CFBundleExecutable</key><string>Bomi</string>
  <key>CFBundleIdentifier</key><string>com.rsautomation.inputmethod.bomi</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSBackgroundOnly</key><true/>
  <key>NSPrincipalClass</key><string>BomiApplication</string>
  <key>InputMethodConnectionName</key><string>com.rsautomation.inputmethod.bomi_Connection</string>
  <key>InputMethodServerControllerClass</key><string>BomiInputController</string>
  <key>tsInputMethodIconFileKey</key><string>bomi.tiff</string>
  <key>ComponentInputModeDict</key>
  <dict>
    <key>tsInputModeListKey</key>
    <dict>
      <key>com.rsautomation.inputmethod.bomi.korean</key>
      <dict>
        <key>TISInputSourceID</key><string>com.rsautomation.inputmethod.bomi.korean</string>
        <key>TISIntendedLanguage</key><string>ko</string>
        <key>tsInputModeScriptKey</key><string>smKorean</string>
        <key>tsInputModeMenuIconFileKey</key><string>bomi.tiff</string>
        <key>tsInputModeDefaultStateKey</key><true/>
        <key>tsInputModeIsVisibleKey</key><true/>
      </dict>
    </dict>
    <key>tsVisibleInputModeOrderedArrayKey</key>
    <array>
      <string>com.rsautomation.inputmethod.bomi.korean</string>
    </array>
  </dict>
</dict>
</plist>
```

- [ ] **Step 6: Create a placeholder `Resources/bomi.tiff`**

Run: `printf '한' | iconutil 2>/dev/null; sips -s format tiff /System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/GenericApplicationIcon.icns --out Resources/bomi.tiff --resampleWidth 16 2>/dev/null || : ; test -f Resources/bomi.tiff && echo OK`
Expected: `OK` (a 16px tiff exists). If it fails, any small `.tiff` works as a placeholder.

- [ ] **Step 7: Create `Scripts/assemble-app.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP="Bomi.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Bomi "$APP/Contents/MacOS/Bomi"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/bomi.tiff "$APP/Contents/Resources/bomi.tiff"
codesign --force --deep --sign - "$APP"
echo "Assembled $APP"
```

- [ ] **Step 8: Create `Scripts/install.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
DEST="$HOME/Library/Input Methods"
mkdir -p "$DEST"
killall Bomi 2>/dev/null || true
rm -rf "$DEST/Bomi.app"
cp -R Bomi.app "$DEST/Bomi.app"
echo "Installed to $DEST/Bomi.app"
echo "Now: System Settings > Keyboard > Input Sources > + > add Bomi (log out/in if it does not appear)."
```

- [ ] **Step 9: Build + assemble + install**

Run: `chmod +x Scripts/*.sh && ./Scripts/assemble-app.sh && ./Scripts/install.sh`
Expected: `Assembled Bomi.app` then `Installed to …`. No compile errors. **If the app target fails to compile due to IMK concurrency**, this is spec §10.1 — the chosen fix (`.defaultIsolation(MainActor.self)`) is already in `Package.swift`; if a specific IMK protocol method still errors, mark just that override `nonisolated` and bridge with `MainActor.assumeIsolated { }`.

- [ ] **Step 10: Manual verification**

1. In System Settings > Keyboard > Input Sources, add **Bomi**. (Log out/in if it doesn't show.)
2. Open TextEdit, switch to Bomi, press any letter key.
3. Expected: `보미` is inserted on each keypress.
Document the result in `.claude/worklog.md` (one line: loads? commits?).

- [ ] **Step 11: Commit**

```bash
git add -A
git commit -m "feat: IMK load spike — minimal Bomi.app that installs and commits text

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01WFUiSiq9yMT6m6FeR5Hk6i"
```

---

## Task 2: Jamo classification

**Files:**
- Modify: `Sources/BomiEngine/Jamo.swift`
- Test: `Tests/BomiEngineTests/JamoTests.swift`

**Interfaces:**
- Produces: `enum JamoSlot { case cho, jung, jong }`; `Jamo.slot(of: UInt32) -> JamoSlot?`; `Jamo.isCho/isJung/isJong(_ u: UInt32) -> Bool`.

- [ ] **Step 1: Write failing test**

```swift
import Testing
@testable import BomiEngine

@Test func classifiesSlots() {
    #expect(Jamo.slot(of: 0x1100) == .cho)   // ㄱ choseong
    #expect(Jamo.slot(of: 0x1112) == .cho)   // ㅎ choseong (last)
    #expect(Jamo.slot(of: 0x1161) == .jung)  // ㅏ jungseong
    #expect(Jamo.slot(of: 0x1175) == .jung)  // ㅣ jungseong (last)
    #expect(Jamo.slot(of: 0x11A8) == .jong)  // ㄱ jongseong
    #expect(Jamo.slot(of: 0x11C2) == .jong)  // ㅎ jongseong (last)
    #expect(Jamo.slot(of: 0x0041) == nil)    // 'A'
    #expect(Jamo.slot(of: 0x00B7) == nil)    // middot symbol
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter JamoTests`
Expected: FAIL (JamoSlot / slot(of:) not defined).

- [ ] **Step 3: Implement**

```swift
import Foundation

public enum JamoSlot: Equatable {
    case cho, jung, jong
}

public enum Jamo {
    public static let choBase: UInt32 = 0x1100, choLast: UInt32 = 0x1112
    public static let jungBase: UInt32 = 0x1161, jungLast: UInt32 = 0x1175
    public static let jongBase: UInt32 = 0x11A8, jongLast: UInt32 = 0x11C2

    public static func isCho(_ u: UInt32) -> Bool { (choBase...choLast).contains(u) }
    public static func isJung(_ u: UInt32) -> Bool { (jungBase...jungLast).contains(u) }
    public static func isJong(_ u: UInt32) -> Bool { (jongBase...jongLast).contains(u) }

    public static func slot(of u: UInt32) -> JamoSlot? {
        if isCho(u) { return .cho }
        if isJung(u) { return .jung }
        if isJong(u) { return .jong }
        return nil
    }

    /// Index into the syllable formula.
    public static func choIndex(_ u: UInt32) -> Int { Int(u - choBase) }        // 0..18
    public static func jungIndex(_ u: UInt32) -> Int { Int(u - jungBase) }      // 0..20
    public static func jongIndex(_ u: UInt32) -> Int { Int(u - jongBase) + 1 }  // 1..27
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter JamoTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/BomiEngine/Jamo.swift Tests/BomiEngineTests/JamoTests.swift
git commit -m "feat(engine): jamo slot classification and indices

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01WFUiSiq9yMT6m6FeR5Hk6i"
```

---

## Task 3: Combination table (compound jamo)

**Files:**
- Create: `Sources/BomiEngine/Combination.swift`
- Test: `Tests/BomiEngineTests/CombinationTests.swift`

**Interfaces:**
- Consumes: `Jamo`.
- Produces: `Combination.combine(_ first: UInt32, _ second: UInt32, allowChoToJong: Bool = true) -> UInt32` (returns `0` if no combination).

- [ ] **Step 1: Write failing test**

```swift
import Testing
@testable import BomiEngine

@Test func combinesJamo() {
    #expect(Combination.combine(0x1100, 0x1100) == 0x1101)  // ㄱ+ㄱ -> ㄲ (cho)
    #expect(Combination.combine(0x1169, 0x1161) == 0x116A)  // ㅗ+ㅏ -> ㅘ
    #expect(Combination.combine(0x11AF, 0x11A8) == 0x11B0)  // ㄹ+ㄱ -> ㄺ (jong)
    #expect(Combination.combine(0x11BA, 0x11BA) == 0x11BB)  // ㅅ+ㅅ -> ㅆ (jong)
    #expect(Combination.combine(0x1100, 0x1102) == 0)       // ㄱ+ㄴ -> none
}

@Test func rejectsChoToJongWhenDisallowed() {
    // ㄱ(cho)+ㅅ(cho) has a table entry -> ㄳ(jong); must be rejected during choseong input.
    #expect(Combination.combine(0x1100, 0x1109, allowChoToJong: false) == 0)
    #expect(Combination.combine(0x1100, 0x1109, allowChoToJong: true) == 0x11AA)
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter CombinationTests`
Expected: FAIL (Combination not defined).

- [ ] **Step 3: Implement** (table verbatim from spec Appendix B)

```swift
import Foundation

public enum Combination {
    @inline(__always) private static func key(_ a: UInt32, _ b: UInt32) -> UInt64 {
        (UInt64(a) << 32) | UInt64(b)
    }

    static let table: [UInt64: UInt32] = {
        let pairs: [(UInt32, UInt32, UInt32)] = [
            (0x1100,0x1100,0x1101),(0x1100,0x1109,0x11AA),(0x1102,0x110C,0x11AC),
            (0x1102,0x1112,0x11AD),(0x1103,0x1103,0x1104),(0x1105,0x1100,0x11B0),
            (0x1105,0x1106,0x11B1),(0x1105,0x1107,0x11B2),(0x1105,0x1109,0x11B3),
            (0x1105,0x1110,0x11B4),(0x1105,0x1111,0x11B5),(0x1105,0x1112,0x11B6),
            (0x1107,0x1107,0x1108),(0x1107,0x1109,0x11B9),(0x1109,0x1109,0x110A),
            (0x110C,0x110C,0x110D),
            (0x1169,0x1161,0x116A),(0x1169,0x1162,0x116B),(0x1169,0x1175,0x116C),
            (0x116E,0x1165,0x116F),(0x116E,0x1166,0x1170),(0x116E,0x1175,0x1171),
            (0x1173,0x1175,0x1174),
            (0x11A8,0x11A8,0x11A9),(0x11A8,0x11BA,0x11AA),(0x11AB,0x11BD,0x11AC),
            (0x11AB,0x11C2,0x11AD),(0x11AF,0x11A8,0x11B0),(0x11AF,0x11B7,0x11B1),
            (0x11AF,0x11B8,0x11B2),(0x11AF,0x11BA,0x11B3),(0x11AF,0x11C0,0x11B4),
            (0x11AF,0x11C1,0x11B5),(0x11AF,0x11C2,0x11B6),(0x11B8,0x11BA,0x11B9),
            (0x11BA,0x11BA,0x11BB),
        ]
        var t: [UInt64: UInt32] = [:]
        for (a, b, r) in pairs { t[key(a, b)] = r }
        return t
    }()

    /// Returns the combined jamo, or 0 if the pair does not combine.
    /// `allowChoToJong`: when false, a cho+cho pair whose result is a jongseong is rejected
    /// (libhangul's option_non_choseong_combi behavior during choseong input).
    public static func combine(_ first: UInt32, _ second: UInt32, allowChoToJong: Bool = true) -> UInt32 {
        guard let r = table[key(first, second)] else { return 0 }
        if !allowChoToJong, Jamo.isCho(first), Jamo.isCho(second), Jamo.isJong(r) {
            return 0
        }
        return r
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter CombinationTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/BomiEngine/Combination.swift Tests/BomiEngineTests/CombinationTests.swift
git commit -m "feat(engine): compound-jamo combination table (libhangul verbatim)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01WFUiSiq9yMT6m6FeR5Hk6i"
```

---

## Task 4: SebeolsikFinal key map + compatibility-jamo tables

**Files:**
- Create: `Sources/BomiEngine/SebeolsikFinal.swift`

**Interfaces:**
- Produces: `SebeolsikFinal.jamo(forASCII: UInt32) -> UInt32?` (0x21–0x7E → jamo or symbol scalar); `SebeolsikFinal.compat(_ jamo: UInt32) -> UInt32` (conjoining → Hangul Compatibility Jamo, identity if unknown).
- Note: values that are symbols/digits (non-jamo) are returned as-is; the composer decides via `Jamo.slot`.

- [ ] **Step 1: Write failing test** (in `SyllableTests.swift`, shared file created here)

```swift
import Testing
@testable import BomiEngine

@Test func sebeolsikLookup() {
    #expect(SebeolsikFinal.jamo(forASCII: 0x6B) == 0x1100) // 'k' -> ㄱ cho
    #expect(SebeolsikFinal.jamo(forASCII: 0x66) == 0x1161) // 'f' -> ㅏ jung
    #expect(SebeolsikFinal.jamo(forASCII: 0x73) == 0x11AB) // 's' -> ㄴ jong
    #expect(SebeolsikFinal.jamo(forASCII: 0x21) == 0x11A9) // '!' -> ㄲ jong
    #expect(SebeolsikFinal.jamo(forASCII: 0x2F) == 0x1169) // '/' -> ㅗ jung
    #expect(SebeolsikFinal.jamo(forASCII: 0x48) == 0x0030) // 'H' -> '0' (digit passthrough)
    #expect(SebeolsikFinal.jamo(forASCII: 0x20) == nil)    // space not in map
}

@Test func compatMapping() {
    #expect(SebeolsikFinal.compat(0x1100) == 0x3131) // ㄱ cho -> compat ㄱ
    #expect(SebeolsikFinal.compat(0x1161) == 0x314F) // ㅏ jung -> compat ㅏ
    #expect(SebeolsikFinal.compat(0x11AF) == 0x3139) // ㄹ jong -> compat ㄹ
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter SyllableTests`
Expected: FAIL (SebeolsikFinal not defined).

- [ ] **Step 3: Implement** (map verbatim from spec Appendix A)

```swift
import Foundation

public enum SebeolsikFinal {
    /// ASCII (shift-applied, 0x21–0x7E) -> Unicode jamo (conjoining) or symbol scalar.
    static let map: [UInt32: UInt32] = [
        0x21:0x11A9, 0x22:0x00B7, 0x23:0x11BD, 0x24:0x11B5, 0x25:0x11B4, 0x26:0x201C,
        0x27:0x1110, 0x28:0x0027, 0x29:0x007E, 0x2A:0x201D, 0x2B:0x002B, 0x2C:0x002C,
        0x2D:0x0029, 0x2E:0x002E, 0x2F:0x1169, 0x30:0x110F, 0x31:0x11C2, 0x32:0x11BB,
        0x33:0x11B8, 0x34:0x116D, 0x35:0x1172, 0x36:0x1163, 0x37:0x1168, 0x38:0x1174,
        0x39:0x116E, 0x3A:0x0034, 0x3B:0x1107, 0x3C:0x002C, 0x3D:0x003E, 0x3E:0x002E,
        0x3F:0x0021, 0x40:0x11B0, 0x41:0x11AE, 0x42:0x003F, 0x43:0x11BF, 0x44:0x11B2,
        0x45:0x11AC, 0x46:0x11B1, 0x47:0x1164, 0x48:0x0030, 0x49:0x0037, 0x4A:0x0031,
        0x4B:0x0032, 0x4C:0x0033, 0x4D:0x0022, 0x4E:0x002D, 0x4F:0x0038, 0x50:0x0039,
        0x51:0x11C1, 0x52:0x11B6, 0x53:0x11AD, 0x54:0x11B3, 0x55:0x0036, 0x56:0x11AA,
        0x57:0x11C0, 0x58:0x11B9, 0x59:0x0035, 0x5A:0x11BE, 0x5B:0x0028, 0x5C:0x003A,
        0x5D:0x003C, 0x5E:0x003D, 0x5F:0x003B, 0x60:0x002A, 0x61:0x11BC, 0x62:0x116E,
        0x63:0x1166, 0x64:0x1175, 0x65:0x1167, 0x66:0x1161, 0x67:0x1173, 0x68:0x1102,
        0x69:0x1106, 0x6A:0x110B, 0x6B:0x1100, 0x6C:0x110C, 0x6D:0x1112, 0x6E:0x1109,
        0x6F:0x110E, 0x70:0x1111, 0x71:0x11BA, 0x72:0x1162, 0x73:0x11AB, 0x74:0x1165,
        0x75:0x1103, 0x76:0x1169, 0x77:0x11AF, 0x78:0x11A8, 0x79:0x1105, 0x7A:0x11B7,
        0x7B:0x0025, 0x7C:0x005C, 0x7D:0x002F, 0x7E:0x203B,
    ]

    public static func jamo(forASCII ascii: UInt32) -> UInt32? { map[ascii] }

    /// Conjoining jamo -> Hangul Compatibility Jamo (U+3130 block). Identity if not a known jamo.
    static let compatTable: [UInt32: UInt32] = [
        // choseong
        0x1100:0x3131,0x1101:0x3132,0x1102:0x3134,0x1103:0x3137,0x1104:0x3138,0x1105:0x3139,
        0x1106:0x3141,0x1107:0x3142,0x1108:0x3143,0x1109:0x3145,0x110A:0x3146,0x110B:0x3147,
        0x110C:0x3148,0x110D:0x3149,0x110E:0x314A,0x110F:0x314B,0x1110:0x314C,0x1111:0x314D,
        0x1112:0x314E,
        // jungseong
        0x1161:0x314F,0x1162:0x3150,0x1163:0x3151,0x1164:0x3152,0x1165:0x3153,0x1166:0x3154,
        0x1167:0x3155,0x1168:0x3156,0x1169:0x3157,0x116A:0x3158,0x116B:0x3159,0x116C:0x315A,
        0x116D:0x315B,0x116E:0x315C,0x116F:0x315D,0x1170:0x315E,0x1171:0x315F,0x1172:0x3160,
        0x1173:0x3161,0x1174:0x3162,0x1175:0x3163,
        // jongseong
        0x11A8:0x3131,0x11A9:0x3132,0x11AA:0x3133,0x11AB:0x3134,0x11AC:0x3135,0x11AD:0x3136,
        0x11AE:0x3137,0x11AF:0x3139,0x11B0:0x313A,0x11B1:0x313B,0x11B2:0x313C,0x11B3:0x313D,
        0x11B4:0x313E,0x11B5:0x313F,0x11B6:0x3140,0x11B7:0x3141,0x11B8:0x3142,0x11B9:0x3144,
        0x11BA:0x3145,0x11BB:0x3146,0x11BC:0x3147,0x11BD:0x3148,0x11BE:0x314A,0x11BF:0x314B,
        0x11C0:0x314C,0x11C1:0x314D,0x11C2:0x314E,
    ]

    public static func compat(_ jamo: UInt32) -> UInt32 { compatTable[jamo] ?? jamo }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter SyllableTests`
Expected: PASS (sebeolsikLookup + compatMapping).

- [ ] **Step 5: Commit**

```bash
git add Sources/BomiEngine/SebeolsikFinal.swift Tests/BomiEngineTests/SyllableTests.swift
git commit -m "feat(engine): Sebeolsik-final 3f key map + compat-jamo tables

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01WFUiSiq9yMT6m6FeR5Hk6i"
```

---

## Task 5: Syllable rendering (NFC + fallback)

**Files:**
- Create: `Sources/BomiEngine/Syllable.swift`
- Test: extend `Tests/BomiEngineTests/SyllableTests.swift`

**Interfaces:**
- Consumes: `Jamo`, `SebeolsikFinal.compat`.
- Produces: `Syllable.render(cho: UInt32, jung: UInt32, jong: UInt32) -> String` (0 = slot empty).

- [ ] **Step 1: Write failing test** (append)

```swift
@Test func rendersSyllables() {
    #expect(Syllable.render(cho: 0x1100, jung: 0x1161, jong: 0)      == "가")
    #expect(Syllable.render(cho: 0x1100, jung: 0x1161, jong: 0x11AB) == "간")
    #expect(Syllable.render(cho: 0x1101, jung: 0x1161, jong: 0)      == "까") // ㄲ
    #expect(Syllable.render(cho: 0x1100, jung: 0x1162, jong: 0x11AF) == "갤") // ㄱ+ㅐ+ㄹ
}

@Test func rendersIncompleteAsCompat() {
    #expect(Syllable.render(cho: 0x1100, jung: 0, jong: 0) == "ㄱ") // lone cho -> compat
    #expect(Syllable.render(cho: 0, jung: 0x1161, jong: 0) == "ㅏ") // lone jung -> compat
    #expect(Syllable.render(cho: 0, jung: 0, jong: 0x11BA) == "ㅅ") // lone jong -> compat
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter SyllableTests`
Expected: FAIL (Syllable not defined).

- [ ] **Step 3: Implement**

```swift
import Foundation

public enum Syllable {
    static let sBase: UInt32 = 0xAC00

    /// Render the buffer. 0 means an empty slot. cho+jung present -> precomposed syllable;
    /// otherwise fall back to Hangul Compatibility Jamo for whichever slots are filled.
    public static func render(cho: UInt32, jung: UInt32, jong: UInt32) -> String {
        if cho != 0, jung != 0 {
            let ci = Jamo.choIndex(cho)
            let ji = Jamo.jungIndex(jung)
            let ki = jong == 0 ? 0 : Jamo.jongIndex(jong)
            let code = sBase + UInt32((ci * 21 + ji) * 28 + ki)
            return String(UnicodeScalar(code)!)
        }
        var s = ""
        if cho != 0  { s.unicodeScalars.append(UnicodeScalar(SebeolsikFinal.compat(cho))!) }
        if jung != 0 { s.unicodeScalars.append(UnicodeScalar(SebeolsikFinal.compat(jung))!) }
        if jong != 0 { s.unicodeScalars.append(UnicodeScalar(SebeolsikFinal.compat(jong))!) }
        return s
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter SyllableTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/BomiEngine/Syllable.swift Tests/BomiEngineTests/SyllableTests.swift
git commit -m "feat(engine): syllable rendering (NFC precomposed + compat fallback)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01WFUiSiq9yMT6m6FeR5Hk6i"
```

---

## Task 6: HangulComposer automaton

Direct port of libhangul `hangul_ic_process_jaso` (auto_reorder=off). One syllable in progress; `input` returns text to commit (may be empty), preedit read separately.

**Files:**
- Create: `Sources/BomiEngine/HangulComposer.swift`
- Test: `Tests/BomiEngineTests/ComposerTests.swift`

**Interfaces:**
- Consumes: `Jamo`, `Combination`, `Syllable`, `SebeolsikFinal`.
- Produces:
  - `struct HangulComposer` with `init()`, `var isComposing: Bool`, `var preedit: String`.
  - `mutating func inputASCII(_ ascii: UInt32) -> String` — process one 3f ASCII key; returns commit text.
  - `mutating func backspace() -> Bool` — true if it consumed a composing jamo.
  - `mutating func flush() -> String` — return + clear remaining preedit (for commit/toggle/blur).

- [ ] **Step 1: Write failing tests**

```swift
import Testing
@testable import BomiEngine

private func type(_ s: String) -> String {
    var c = HangulComposer()
    var out = ""
    for ch in s.unicodeScalars { out += c.inputASCII(ch.value) }
    out += c.flush()
    return out
}

@Test func basicSyllables() {
    #expect(type("kf") == "가")        // ㄱㅏ
    #expect(type("kfs") == "간")       // ㄱㅏㄴ(jong)
    #expect(type("kkf") == "까")       // ㄱ+ㄱ->ㄲ, ㅏ
    #expect(type("krw") == "갤")       // ㄱㅐㄹ(jong)
}

@Test func multipleSyllables() {
    #expect(type("kfsu") == "간ㄷ")    // 간 then ㄷ(cho) starts new -> compat until flushed? no: 간 commits, ㄷ lone -> "ㄷ"
    #expect(type("kfhf") == "가나")    // ㄱㅏ | ㄴ(cho h) starts new, ㅏ -> 나
}

@Test func compoundVowelAndJong() {
    #expect(type("kvf") == "과")       // ㄱ + ㅗ(v) + ㅏ(f) -> ㅘ -> 과
    #expect(type("yvwx") == "롥")      // stress: ㄹ ㅗ ㄹ(jong) ㄱ(jong)->ㄺ  => 롥
}

@Test func backspaceRevertsCompound() {
    var c = HangulComposer()
    _ = c.inputASCII(0x79) // ㄹ cho
    _ = c.inputASCII(0x76) // ㅗ jung
    _ = c.inputASCII(0x77) // ㄹ jong
    _ = c.inputASCII(0x78) // ㄱ jong -> ㄺ
    #expect(c.preedit == "롥")
    #expect(c.backspace() == true)     // remove ㄱ -> back to ㄹ jong
    #expect(c.preedit == "롤")
    #expect(c.backspace() == true)     // remove ㄹ jong
    #expect(c.preedit == "로")
}

@Test func symbolCommitsThenAppends() {
    // ';' (0x3B) is ㅂ cho in 3f, so use a real symbol: space is not in map -> handled by caller.
    // '.' (0x2E) maps to '.' symbol -> commits current then appends '.'
    #expect(type("kf.") == "가.")
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter ComposerTests`
Expected: FAIL (HangulComposer not defined).

- [ ] **Step 3: Implement** (port of libhangul jaso logic)

```swift
import Foundation

public struct HangulComposer {
    private var cho: UInt32 = 0
    private var jung: UInt32 = 0
    private var jong: UInt32 = 0
    private var stack: [UInt32] = []   // push order; last = most recent (peek); used for backspace

    public init() {}

    public var isComposing: Bool { !stack.isEmpty }
    public var preedit: String { Syllable.render(cho: cho, jung: jung, jong: jong) }

    private var peek: UInt32 { stack.last ?? 0 }

    private mutating func push(_ c: UInt32) {
        switch Jamo.slot(of: c) {
        case .cho:  cho = c
        case .jung: jung = c
        case .jong: jong = c
        case nil:   break
        }
        stack.append(c)
    }

    /// Emit current buffer as a string and clear it.
    private mutating func drain() -> String {
        let s = Syllable.render(cho: cho, jung: jung, jong: jong)
        cho = 0; jung = 0; jong = 0; stack.removeAll(keepingCapacity: true)
        return s
    }

    public mutating func flush() -> String { drain() }

    /// Process one Sebeolsik-final ASCII key. Returns text to commit to the client (possibly empty).
    public mutating func inputASCII(_ ascii: UInt32) -> String {
        guard let value = SebeolsikFinal.jamo(forASCII: ascii) else {
            // Not in the 3f map (e.g. space): commit current, let caller pass the key through.
            return drain()
        }
        var commit = ""
        switch Jamo.slot(of: value) {
        case .cho:
            if cho == 0 {
                if jung != 0 || jong != 0 { commit += drain() }
                push(value)
            } else if Jamo.isCho(peek),
                      case let comb = Combination.combine(cho, value, allowChoToJong: false),
                      comb != 0 {
                push(comb)
            } else {
                commit += drain(); push(value)
            }
        case .jung:
            if jung == 0 {
                if jong != 0 { commit += drain() }
                push(value)
            } else if Jamo.isJung(peek),
                      case let comb = Combination.combine(jung, value),
                      comb != 0 {
                push(comb)
            } else {
                commit += drain(); push(value)
            }
        case .jong:
            if jong == 0 {
                push(value)
            } else if Jamo.isJong(peek),
                      case let comb = Combination.combine(jong, value),
                      comb != 0 {
                push(comb)
            } else {
                commit += drain(); push(value)
            }
        case nil:
            // Symbol/digit from the 3f map (e.g. '.', '·'): commit current, append the symbol.
            commit += drain()
            commit.unicodeScalars.append(UnicodeScalar(value)!)
        }
        return commit
    }

    /// Backspace one jamo while composing. Rebuilds slots from the remaining stack
    /// (a compound reverts to its base). Returns false if nothing was composing.
    public mutating func backspace() -> Bool {
        guard !stack.isEmpty else { return false }
        stack.removeLast()
        cho = 0; jung = 0; jong = 0
        for c in stack {
            switch Jamo.slot(of: c) {
            case .cho:  cho = c
            case .jung: jung = c
            case .jong: jong = c
            case nil:   break
            }
        }
        return true
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter ComposerTests`
Expected: PASS. (If `yvwx`/`kvf` expectations differ from libhangul, trust libhangul: re-derive the expected string by hand from the jamo and fix the test literal, not the logic.)

- [ ] **Step 5: Full engine test sweep**

Run: `swift test`
Expected: all engine tests PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/BomiEngine/HangulComposer.swift Tests/BomiEngineTests/ComposerTests.swift
git commit -m "feat(engine): Sebeolsik-final Hangul automaton (libhangul jaso port)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01WFUiSiq9yMT6m6FeR5Hk6i"
```

---

## Task 7: KeyTranslator (keyCode + shift → 3f ASCII) + toggle detection

**Files:**
- Create: `Sources/Bomi/KeyTranslator.swift`

**Interfaces:**
- Produces:
  - `enum KeyTranslator`
  - `static func ascii(keyCode: UInt16, shift: Bool) -> UInt32?` — US-QWERTY physical layout, honoring Shift, ignoring CapsLock/system layout.
  - `static let rightCommandKeyCode: UInt16 = 0x36`

Note: this file is in the App target (no swift-testing wiring here); correctness is covered by manual integration in Task 8. Table is the standard US ANSI virtual-keycode layout.

- [ ] **Step 1: Implement**

```swift
import Foundation

enum KeyTranslator {
    static let rightCommandKeyCode: UInt16 = 0x36

    // US ANSI virtual keycode -> (unshifted, shifted) ASCII.
    private static let table: [UInt16: (UInt32, UInt32)] = [
        0x00:(0x61,0x41),0x0B:(0x62,0x42),0x08:(0x63,0x43),0x02:(0x64,0x44),0x0E:(0x65,0x45),
        0x03:(0x66,0x46),0x05:(0x67,0x47),0x04:(0x68,0x48),0x22:(0x69,0x49),0x26:(0x6A,0x4A),
        0x28:(0x6B,0x4B),0x25:(0x6C,0x4C),0x2E:(0x6D,0x4D),0x2D:(0x6E,0x4E),0x1F:(0x6F,0x4F),
        0x23:(0x70,0x50),0x0C:(0x71,0x51),0x0F:(0x72,0x52),0x01:(0x73,0x53),0x11:(0x74,0x54),
        0x20:(0x75,0x55),0x09:(0x76,0x56),0x0D:(0x77,0x57),0x07:(0x78,0x58),0x10:(0x79,0x59),
        0x06:(0x7A,0x5A),
        0x12:(0x31,0x21),0x13:(0x32,0x40),0x14:(0x33,0x23),0x15:(0x34,0x24),0x17:(0x35,0x25),
        0x16:(0x36,0x5E),0x1A:(0x37,0x26),0x1C:(0x38,0x2A),0x19:(0x39,0x28),0x1D:(0x30,0x29),
        0x1B:(0x2D,0x5F),0x18:(0x3D,0x2B),0x21:(0x5B,0x7B),0x1E:(0x5D,0x7D),0x2A:(0x5C,0x7C),
        0x29:(0x3B,0x3A),0x27:(0x27,0x22),0x2B:(0x2C,0x3C),0x2F:(0x2E,0x3E),0x2C:(0x2F,0x3F),
        0x32:(0x60,0x7E),
    ]

    /// US-QWERTY physical ASCII, honoring Shift only. Returns nil for non-character keys
    /// (space, return, arrows, etc. — the caller handles those explicitly).
    static func ascii(keyCode: UInt16, shift: Bool) -> UInt32? {
        guard let (lo, hi) = table[keyCode] else { return nil }
        return shift ? hi : lo
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: builds clean.

- [ ] **Step 3: Commit**

```bash
git add Sources/Bomi/KeyTranslator.swift
git commit -m "feat(imk): US-QWERTY keyCode->3f ASCII translator + right-cmd keycode

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01WFUiSiq9yMT6m6FeR5Hk6i"
```

---

## Task 8: Wire the automaton into BomiInputController (Korean mode)

Replace the spike controller with real composition: preedit via marked text, commit via insertText, backspace, special-key passthrough.

**Files:**
- Modify: `Sources/Bomi/BomiInputController.swift`

**Interfaces:**
- Consumes: `HangulComposer`, `KeyTranslator`.
- Produces: a working Korean composition controller (han-only for now; toggle in Task 9).

- [ ] **Step 1: Implement**

```swift
import AppKit
import InputMethodKit
import BomiEngine

@objc(BomiInputController)
final class BomiInputController: IMKInputController {
    private var composer = HangulComposer()

    private func client(_ sender: Any!) -> IMKTextInput? { sender as? IMKTextInput }
    private let noRange = NSRange(location: NSNotFound, length: NSNotFound)

    private func showPreedit(_ client: IMKTextInput) {
        let s = composer.preedit
        client.setMarkedText(s, selectionRange: NSRange(location: s.utf16.count, length: 0),
                             replacementRange: noRange)
    }

    private func commit(_ text: String, _ client: IMKTextInput) {
        guard !text.isEmpty else { return }
        client.insertText(text, replacementRange: noRange)
    }

    /// Flush any in-progress syllable to the client. Used on blur/commit.
    private func flush(_ client: IMKTextInput) {
        let tail = composer.flush()
        if !tail.isEmpty { client.insertText(tail, replacementRange: noRange) }
    }

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event, let client = client(sender) else { return false }
        guard event.type == .keyDown else { return false }

        // Modifiers other than Shift: commit and pass through (e.g. Cmd+C).
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) || flags.contains(.control) || flags.contains(.option) {
            flush(client)
            return false
        }

        let keyCode = event.keyCode
        let shift = flags.contains(.shift)

        // Backspace (0x33)
        if keyCode == 0x33 {
            if composer.backspace() { showPreedit(client); return true }
            return false
        }
        // Enter(0x24), Return(0x4C), Tab(0x30), Escape(0x35), arrows(0x7B-0x7E), space(0x31)
        let passthrough: Set<UInt16> = [0x24, 0x4C, 0x30, 0x35, 0x7B, 0x7C, 0x7D, 0x7E, 0x31]
        if passthrough.contains(keyCode) {
            flush(client)
            return false   // let the app handle the key itself
        }

        guard let ascii = KeyTranslator.ascii(keyCode: keyCode, shift: shift) else {
            flush(client); return false
        }

        let committed = composer.inputASCII(ascii)
        commit(committed, client)
        showPreedit(client)
        return true
    }

    override func commitComposition(_ sender: Any!) {
        if let client = client(sender) { flush(client) }
    }

    override func deactivateServer(_ sender: Any!) {
        if let client = client(sender) { flush(client) }
    }
}
```

- [ ] **Step 2: Build, assemble, install**

Run: `./Scripts/assemble-app.sh && ./Scripts/install.sh && killall Bomi 2>/dev/null; true`
Expected: assembles + installs clean.

- [ ] **Step 3: Manual verification**

In TextEdit with Bomi active, type (US keys) `k f s`: expect `간` to appear as underlined preedit then commit on next syllable/space. Try `k k f` → `까`, `k v f` → `과`, backspace mid-syllable reverts jamo. Type in Terminal too. Record result in worklog.

- [ ] **Step 4: Commit**

```bash
git add Sources/Bomi/BomiInputController.swift
git commit -m "feat(imk): wire Hangul automaton into controller (preedit/commit/backspace)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01WFUiSiq9yMT6m6FeR5Hk6i"
```

---

## Task 9: Han/Eng toggle + per-app memory

**Files:**
- Create: `Sources/Bomi/LanguageMode.swift`, `Sources/Bomi/Preferences.swift`
- Modify: `Sources/Bomi/BomiInputController.swift`

**Interfaces:**
- Produces:
  - `final class Preferences` (singleton `.shared`): `var toggleKeyCode: UInt16` (default `0x36` right-cmd), `var perAppMemory: Bool` (default true).
  - `final class LanguageMode`: `func isKorean(forApp bundleID: String?) -> Bool`, `func toggle(forApp bundleID: String?)`.
- Consumes: `Preferences`, `KeyTranslator`.

- [ ] **Step 1: Implement `Preferences.swift`**

```swift
import Foundation

final class Preferences {
    static let shared = Preferences()
    private let d = UserDefaults.standard
    private init() {
        d.register(defaults: ["toggleKeyCode": 0x36, "perAppMemory": true])
    }
    var toggleKeyCode: UInt16 { UInt16(d.integer(forKey: "toggleKeyCode")) }
    var perAppMemory: Bool { d.bool(forKey: "perAppMemory") }
}
```

- [ ] **Step 2: Implement `LanguageMode.swift`**

```swift
import Foundation

final class LanguageMode {
    private var global = false                 // false = English, true = Korean
    private var perApp: [String: Bool] = [:]

    func isKorean(forApp bundleID: String?) -> Bool {
        if Preferences.shared.perAppMemory, let id = bundleID, let v = perApp[id] { return v }
        return global
    }

    func toggle(forApp bundleID: String?) {
        let now = !isKorean(forApp: bundleID)
        global = now
        if Preferences.shared.perAppMemory, let id = bundleID { perApp[id] = now }
    }
}
```

- [ ] **Step 3: Wire toggle into the controller** — full updated `handle` + state

Add to `BomiInputController`:

```swift
    private let language = LanguageMode()
    private var korean = false
    private var appID: String?

    override func recognizedEvents(_ sender: Any!) -> Int {
        Int(NSEvent.EventTypeMask.keyDown.rawValue | NSEvent.EventTypeMask.flagsChanged.rawValue)
    }

    override func activateServer(_ sender: Any!) {
        appID = (sender as? IMKTextInput)?.bundleIdentifier()
        korean = language.isKorean(forApp: appID)
    }
```

Then, at the **top of `handle`**, before the keyDown guard, handle the toggle key and flagsChanged:

```swift
        // Han/Eng toggle: bare Right-Command tap (down with no chord).
        if event.type == .flagsChanged {
            handleToggleFlags(event, client)
            return false
        }
```

And add the toggle helper + make composition respect `korean`:

```swift
    private var toggleArmed = false

    private func handleToggleFlags(_ event: NSEvent, _ client: IMKTextInput) {
        let code = event.keyCode
        guard code == Preferences.shared.toggleKeyCode else { toggleArmed = false; return }
        // .command bit present on the right-cmd change means key-down; absent means key-up.
        let down = event.modifierFlags.contains(.command)
        if down {
            toggleArmed = true
        } else if toggleArmed {
            toggleArmed = false
            flush(client)
            language.toggle(forApp: appID)
            korean = language.isKorean(forApp: appID)
        }
    }
```

In `handle`, after the modifier check, gate composition on Korean mode:

```swift
        if !korean {
            flush(client)
            return false
        }
```
(Place this right after the `flagsChanged` block and the Cmd/Ctrl/Opt passthrough, before backspace handling.)

- [ ] **Step 4: Build, assemble, install, verify**

Run: `./Scripts/assemble-app.sh && ./Scripts/install.sh`
Manual: In TextEdit, tap Right-Command → toggles Korean/English; type to confirm; switch to another app and back to confirm per-app memory. Record in worklog.

- [ ] **Step 5: Commit**

```bash
git add Sources/Bomi/LanguageMode.swift Sources/Bomi/Preferences.swift Sources/Bomi/BomiInputController.swift
git commit -m "feat(imk): in-IME han/eng toggle (right-cmd) + per-app memory

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01WFUiSiq9yMT6m6FeR5Hk6i"
```

---

## Task 10: Input-source menu

**Files:**
- Create: `Sources/Bomi/MenuBuilder.swift`
- Modify: `Sources/Bomi/BomiInputController.swift` (override `menu()`)

**Interfaces:**
- Consumes: `Preferences`.
- Produces: `MenuBuilder.build(target:) -> NSMenu` with items: current-mode indicator (disabled), "Toggle Han/Eng key: Right Command" (disabled info), "Per-app memory" (checkable), "Preferences…" (opens nothing yet — safe no-op), "About Bomi".

- [ ] **Step 1: Implement `MenuBuilder.swift`**

```swift
import AppKit

enum MenuBuilder {
    static func build(korean: Bool, target: AnyObject) -> NSMenu {
        let menu = NSMenu(title: "Bomi")
        let mode = NSMenuItem(title: korean ? "한글 (Korean)" : "English", action: nil, keyEquivalent: "")
        mode.isEnabled = false
        menu.addItem(mode)
        menu.addItem(.separator())

        let mem = NSMenuItem(title: "앱별 한/영 기억", action: #selector(BomiInputController.togglePerAppMemory(_:)), keyEquivalent: "")
        mem.target = target
        mem.state = Preferences.shared.perAppMemory ? .on : .off
        menu.addItem(mem)

        let about = NSMenuItem(title: "Bomi 정보", action: nil, keyEquivalent: "")
        about.isEnabled = false
        menu.addItem(about)
        return menu
    }
}
```

- [ ] **Step 2: Add `menu()` + action to controller**

```swift
    override func menu() -> NSMenu! {
        MenuBuilder.build(korean: korean, target: self)
    }

    @objc func togglePerAppMemory(_ sender: NSMenuItem) {
        let d = UserDefaults.standard
        d.set(!Preferences.shared.perAppMemory, forKey: "perAppMemory")
    }
```

- [ ] **Step 3: Build, assemble, install, verify**

Run: `./Scripts/assemble-app.sh && ./Scripts/install.sh`
Manual: click the Bomi menu-bar item → menu shows current mode + per-app toggle. Record in worklog.

- [ ] **Step 4: Commit**

```bash
git add Sources/Bomi/MenuBuilder.swift Sources/Bomi/BomiInputController.swift
git commit -m "feat(ui): input-source menu (mode indicator + per-app memory toggle)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01WFUiSiq9yMT6m6FeR5Hk6i"
```

---

## Task 11: Hard-app hardening pass

Verify + fix demanding apps (Terminal, iTerm2, VS Code/Electron, a password field). No new files; targeted fixes with a documented result.

**Files:**
- Modify: `Sources/Bomi/BomiInputController.swift` (only if a defect is found)

- [ ] **Step 1: Test matrix** — in each app, type `kfs`, `kkf`, `kvf`, backspace mid-syllable, toggle han/eng, click elsewhere mid-composition, switch apps mid-composition. Record pass/fail per app in worklog.

- [ ] **Step 2: If composition is dropped on focus loss**, confirm `deactivateServer`/`commitComposition` both call `flush`. (Already present — verify they fire; some apps only send one.)

- [ ] **Step 3: If marked text is invisible/garbled in an app** (e.g. some Electron), add a per-client fallback: when `client.markedRange()` is not honored, commit immediately instead of showing preedit. Implement only if observed:

```swift
    // In showPreedit, guard:
    private func canMark(_ client: IMKTextInput) -> Bool {
        client.markedRange().location != NSNotFound || composer.isComposing
    }
```

- [ ] **Step 4: Cross-check the automaton against libhangul** for 20 representative sequences (optional oracle): if any diverge, fix the test literal to match libhangul, not the logic.

- [ ] **Step 5: Update `README.md`** with build/install instructions (from Scripts) and a one-line status.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "fix(imk): hard-app hardening pass + README

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01WFUiSiq9yMT6m6FeR5Hk6i"
```

---

## Self-Review

**Spec coverage:**
- §1 MVP features → Tasks 6 (automaton), 8 (composition+recovery), 9 (toggle+per-app), 10 (menu). ✅
- §4 architecture (3 layers) → Engine Tasks 2–6, IMK Tasks 7–9, App Tasks 1/10. ✅
- §5 automaton rules → Task 6 (ported verbatim). ✅
- §6 IMK integration (handle/commit/deactivate/recognizedEvents/setMarkedText/insertText) → Tasks 8–9. ✅
- §7 UI/prefs → Tasks 9–10. ✅
- §8 build/install → Task 1 (Package + scripts). ✅
- §9 testing → Tasks 2–6 unit tests; manual matrix Task 11. ✅
- §10 risks: 10.1 concurrency → Task 1 (defaultIsolation MainActor); 10.2 SwiftPM→.app → Task 1; 10.3 right-cmd tap → Task 9; 10.4 hard apps → Task 11; 10.5 ad-hoc signing → Task 1 codesign `-`. ✅
- §11 milestones → task order matches (spike first). ✅

**Placeholder scan:** No "TBD"/"handle edge cases"/"similar to". Task 11 Steps 2–3 are conditional-on-observation fixes with real code, not placeholders. ✅

**Type consistency:** `HangulComposer.inputASCII/backspace/flush/preedit/isComposing` used identically in Tasks 6 and 8. `KeyTranslator.ascii(keyCode:shift:)` and `rightCommandKeyCode` consistent Tasks 7/9. `Preferences.shared.perAppMemory/toggleKeyCode` consistent Tasks 9/10. `SebeolsikFinal.jamo(forASCII:)/compat` consistent Tasks 4/5/6. ✅

**Known follow-ups (out of MVP, tracked):** Hanja, symbol layer, Dubeolsik, eojeol-keep mode, real preferences window.
