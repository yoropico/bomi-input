# Bomi Han/Eng Mode Switching Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the macOS menu bar show Han/Eng (ㅂ ↔ B) by declaring Korean and Roman as two input modes and switching the system input source on Right-Command tap.

**Architecture:** The **active input mode becomes the single source of truth** for Han/Eng — macOS owns it. The IME declares two modes in `Info.plist`; a Right-Command bare tap calls `TISSelectInputSource` on the other mode (fast path, same as Ctrl-Opt-Space), falling back to `IMKTextInput.selectMode(id)`. Keeping our *own* Roman mode (rather than switching to system ABC) is what keeps the toggle bidirectional — ABC would deactivate our IME and Right-Command would never reach us again. The existing `LanguageMode` (UserDefaults per-app state) is deleted; per-app memory is delegated to macOS.

**Tech Stack:** Swift 6.2 (SwiftPM), InputMethodKit, Carbon (`TISSelectInputSource`), swift-testing.

**Spec:** `docs/superpowers/specs/2026-07-14-bomi-han-eng-mode-switching-design.md`

## Global Constraints

- swift-tools-version 6.2; `platforms: [.macOS(.v14)]`.
- Target `Bomi` (executable) has `swiftSettings: [.defaultIsolation(MainActor.self)]`. Every `IMKInputController` override that overrides a `nonisolated` ObjC declaration must be marked `nonisolated override` and hop via `MainActor.assumeIsolated { }`; non-Sendable ObjC values (`sender`, `NSMenu`) cross that boundary inside `UncheckedSendableBox`.
- Target `BomiCore` is a pure library: Foundation only, **no Carbon/AppKit/IMK**. Anything touching TIS lives in the `Bomi` target.
- Bundle id is exactly `com.bomi.inputmethod.bomi`. Mode ids are `com.bomi.inputmethod.bomi.korean` and `com.bomi.inputmethod.bomi.roman`. `InputMethodConnectionName` is `com.bomi.inputmethod.bomi_Connection`. **A bundle id must not end in `inputmethod`** or macOS silently refuses to register the IME.
- Regression gate: `swift test` must be green before every commit.
- Edits return the COMPLETE file, never a diff.
- Icon source: `~/Project/gureum/OSX` (the user's own Gureum fork).

---

### Task 1: Icons + two input modes in Info.plist

**Files:**
- Create: `Resources/statusbomi_han.png`, `Resources/statusbomi_han@2x.png`, `Resources/statusbomi_eng.png`, `Resources/statusbomi_eng@2x.png`, `Resources/bomi-input.png`
- Modify: `Resources/Info.plist` (whole file below)
- Modify: `Resources/en.lproj/InfoPlist.strings`, `Resources/ko.lproj/InfoPlist.strings` (whole files below)
- Modify: `Scripts/assemble-app.sh` (whole file below)
- Delete: `Resources/bomi.tiff`

**Interfaces:**
- Consumes: nothing.
- Produces: mode ids `com.bomi.inputmethod.bomi.korean` and `com.bomi.inputmethod.bomi.roman`, which Task 2 hard-codes in the `InputMode` enum. Icon filenames referenced by `Info.plist`.

- [ ] **Step 1: Copy the icons from the Gureum fork**

```bash
cd /Users/bglee/Project/worktrees/bomi-input-sebeolsik-mvp
G=/Users/bglee/Project/gureum/OSX
cp "$G/Assets.xcassets/statusbomi_han.imageset/statusbomi_han.png"    Resources/statusbomi_han.png
cp "$G/Assets.xcassets/statusbomi_han.imageset/statusbomi_han@2x.png" Resources/statusbomi_han@2x.png
cp "$G/Assets.xcassets/statusbomi_eng.imageset/statusbomi_eng.png"    Resources/statusbomi_eng.png
cp "$G/Assets.xcassets/statusbomi_eng.imageset/statusbomi_eng@2x.png" Resources/statusbomi_eng@2x.png
cp "$G/Icons/brand/bomi-input.png"                                    Resources/bomi-input.png
git rm -q Resources/bomi.tiff
```

Expected: 5 PNGs in `Resources/`, `bomi.tiff` gone.

- [ ] **Step 2: Rewrite `Resources/Info.plist` with both modes**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Bomi</string>
  <key>CFBundleDisplayName</key><string>Bomi</string>
  <key>CFBundleExecutable</key><string>Bomi</string>
  <key>CFBundleIdentifier</key><string>com.bomi.inputmethod.bomi</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSBackgroundOnly</key><true/>
  <key>NSPrincipalClass</key><string>BomiApplication</string>
  <key>InputMethodConnectionName</key><string>com.bomi.inputmethod.bomi_Connection</string>
  <key>InputMethodServerControllerClass</key><string>BomiInputController</string>
  <key>tsInputMethodIconFileKey</key><string>bomi-input.png</string>
  <key>ComponentInputModeDict</key>
  <dict>
    <key>tsInputModeListKey</key>
    <dict>
      <key>com.bomi.inputmethod.bomi.korean</key>
      <dict>
        <key>TISInputSourceID</key><string>com.bomi.inputmethod.bomi.korean</string>
        <key>TISIntendedLanguage</key><string>ko</string>
        <key>tsInputModeScriptKey</key><string>smKorean</string>
        <key>tsInputModeMenuIconFileKey</key><string>statusbomi_han.png</string>
        <key>tsInputModeAlternateMenuIconFileKey</key><string>statusbomi_han.png</string>
        <key>tsInputModePaletteIconFileKey</key><string>statusbomi_han.png</string>
        <key>tsInputModeDefaultStateKey</key><true/>
        <key>tsInputModeIsVisibleKey</key><true/>
      </dict>
      <key>com.bomi.inputmethod.bomi.roman</key>
      <dict>
        <key>TISInputSourceID</key><string>com.bomi.inputmethod.bomi.roman</string>
        <key>TISIntendedLanguage</key><string>en</string>
        <key>tsInputModeScriptKey</key><string>smRoman</string>
        <key>tsInputModeMenuIconFileKey</key><string>statusbomi_eng.png</string>
        <key>tsInputModeAlternateMenuIconFileKey</key><string>statusbomi_eng.png</string>
        <key>tsInputModePaletteIconFileKey</key><string>statusbomi_eng.png</string>
        <key>tsInputModeDefaultStateKey</key><true/>
        <key>tsInputModeIsVisibleKey</key><true/>
      </dict>
    </dict>
    <key>tsVisibleInputModeOrderedArrayKey</key>
    <array>
      <string>com.bomi.inputmethod.bomi.korean</string>
      <string>com.bomi.inputmethod.bomi.roman</string>
    </array>
  </dict>
</dict>
</plist>
```

- [ ] **Step 3: Rewrite both `InfoPlist.strings` (localize BOTH mode ids)**

`Resources/en.lproj/InfoPlist.strings`:

```
"CFBundleDisplayName" = "Bomi";
"CFBundleName" = "Bomi";
"com.bomi.inputmethod.bomi.korean" = "Bomi";
"com.bomi.inputmethod.bomi.roman" = "Bomi Roman";
```

`Resources/ko.lproj/InfoPlist.strings`:

```
"CFBundleDisplayName" = "보미";
"CFBundleName" = "보미";
"com.bomi.inputmethod.bomi.korean" = "보미";
"com.bomi.inputmethod.bomi.roman" = "보미 로마자";
```

- [ ] **Step 4: Rewrite `Scripts/assemble-app.sh` to copy the icons**

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
# Mode icons (menu bar ㅂ / B) + the input-method icon.
cp Resources/*.png "$APP/Contents/Resources/"
# Localized input-source display names — without these the input-source list
# shows the raw mode identifier.
for lproj in Resources/*.lproj; do
  cp -R "$lproj" "$APP/Contents/Resources/"
done
codesign --force --deep --sign - "$APP"
echo "Assembled $APP"
```

- [ ] **Step 5: Verify the plist and the assembled bundle**

Run:
```bash
plutil -lint Resources/Info.plist
./Scripts/assemble-app.sh
plutil -extract ComponentInputModeDict.tsInputModeListKey xml1 -o - Bomi.app/Contents/Info.plist | grep '<key>com\.'
ls Bomi.app/Contents/Resources/
```
Expected: plist `OK`; both `com.bomi.inputmethod.bomi.korean` and `com.bomi.inputmethod.bomi.roman` listed; Resources contains `statusbomi_han.png`, `statusbomi_han@2x.png`, `statusbomi_eng.png`, `statusbomi_eng@2x.png`, `bomi-input.png`, `en.lproj`, `ko.lproj`.

- [ ] **Step 6: Commit**

```bash
git add Resources Scripts
git commit -m "feat(bundle): declare korean+roman input modes with ㅂ/B menu-bar icons"
```

---

### Task 2: `InputMode` (pure, in BomiCore)

**Files:**
- Create: `Sources/BomiCore/InputMode.swift`
- Test: `Tests/BomiCoreTests/InputModeTests.swift`

**Interfaces:**
- Consumes: the two mode id strings from Task 1.
- Produces: `public enum InputMode: String, Sendable, CaseIterable` with cases `.korean` (raw `"com.bomi.inputmethod.bomi.korean"`) and `.roman` (raw `"com.bomi.inputmethod.bomi.roman"`); `public var other: InputMode`; `public static func from(id: String?) -> InputMode`. Tasks 3 and 4 use all three.

- [ ] **Step 1: Write the failing test**

`Tests/BomiCoreTests/InputModeTests.swift`:

```swift
import Testing
@testable import BomiCore

@Test func otherFlipsBetweenKoreanAndRoman() {
    #expect(InputMode.korean.other == .roman)
    #expect(InputMode.roman.other == .korean)
}

@Test func modeIdsMatchInfoPlist() {
    #expect(InputMode.korean.rawValue == "com.bomi.inputmethod.bomi.korean")
    #expect(InputMode.roman.rawValue  == "com.bomi.inputmethod.bomi.roman")
}

@Test func fromIdParsesKnownIdsAndDefaultsToKorean() {
    #expect(InputMode.from(id: "com.bomi.inputmethod.bomi.roman") == .roman)
    #expect(InputMode.from(id: "com.bomi.inputmethod.bomi.korean") == .korean)
    #expect(InputMode.from(id: nil) == .korean)              // no mode reported yet
    #expect(InputMode.from(id: "com.apple.keylayout.ABC") == .korean)  // unknown id
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter InputMode`
Expected: FAIL — compile error, `cannot find 'InputMode' in scope`.

- [ ] **Step 3: Write the minimal implementation**

`Sources/BomiCore/InputMode.swift`:

```swift
import Foundation

/// The two input sources this IME declares in Info.plist. The ACTIVE mode is the
/// single source of truth for Han/Eng — macOS owns it, so the controller keeps no
/// language boolean and no per-app map.
public enum InputMode: String, Sendable, CaseIterable {
    case korean = "com.bomi.inputmethod.bomi.korean"
    case roman = "com.bomi.inputmethod.bomi.roman"

    /// The mode a Right-Command tap switches to.
    public var other: InputMode { self == .korean ? .roman : .korean }

    /// Map an IMK mode identifier to a mode. An unknown or absent id means macOS
    /// has not told us yet — assume Korean, our default-state mode.
    public static func from(id: String?) -> InputMode {
        guard let id, let mode = InputMode(rawValue: id) else { return .korean }
        return mode
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter InputMode`
Expected: PASS, 3 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/BomiCore/InputMode.swift Tests/BomiCoreTests/InputModeTests.swift
git commit -m "feat(core): InputMode — active input source is the han/eng source of truth"
```

---

### Task 3: `ModeSwitcher` (TIS fast path, in the Bomi target)

**Files:**
- Create: `Sources/Bomi/ModeSwitcher.swift`

**Interfaces:**
- Consumes: `InputMode` (Task 2).
- Produces: `enum ModeSwitcher` with `static func select(_ mode: InputMode, fallback: (String) -> Void)`. Task 4 calls it as `ModeSwitcher.select(target) { id in client.selectMode(id) }`.

**Why no unit test:** `TISSelectInputSource` mutates the machine's active input source — there is nothing to assert against in-process without hijacking the user's keyboard. Correctness is covered by the manual verification in Task 6. Do not fake it with a mock; that would test the mock.

- [ ] **Step 1: Write the implementation**

`Sources/Bomi/ModeSwitcher.swift`:

```swift
import Carbon
import BomiCore

/// Switches the system input source between our two modes.
///
/// IMK's `selectMode(_:)` (ObjC `selectInputMode:`) is a ~1 second slow path.
/// `TISSelectInputSource` — the same mechanism as Ctrl-Opt-Space — switches
/// immediately AND makes macOS refresh the menu-bar icon, which is the whole
/// point of this feature. If the target source is disabled or missing (e.g. the
/// user removed the Roman entry from Input Sources), fall back to `selectMode`.
enum ModeSwitcher {
    /// `TISInputSource` refs keyed by mode id. The input-source list almost never
    /// changes, so caching avoids a `TISCreateInputSourceList` scan per toggle.
    /// Only touched on the main thread (IMK input handling).
    private static var cache: [String: TISInputSource] = [:]

    static func select(_ mode: InputMode, fallback: (String) -> Void) {
        let id = mode.rawValue

        if let cached = cache[id], TISSelectInputSource(cached) == noErr { return }
        cache[id] = nil   // stale ref (source disabled/removed) — re-look it up

        let filter = [kTISPropertyInputSourceID as String: id] as NSDictionary
        if let source = (TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource])?.first,
           TISSelectInputSource(source) == noErr {
            cache[id] = source
            return
        }

        fallback(id)
    }
}
```

- [ ] **Step 2: Verify it builds**

Run: `swift build 2>&1 | tail -3`
Expected: `Build complete!` (no concurrency errors — `cache` is a `static var` on a `MainActor`-isolated target).

- [ ] **Step 3: Commit**

```bash
git add Sources/Bomi/ModeSwitcher.swift
git commit -m "feat(imk): ModeSwitcher — TISSelectInputSource fast path with selectMode fallback"
```

---

### Task 4: Controller — track the active mode, compose only in Korean, toggle by switching input source

**Files:**
- Modify: `Sources/Bomi/BomiInputController.swift` (whole file below)

**Interfaces:**
- Consumes: `InputMode` (Task 2), `ModeSwitcher.select` (Task 3), `ToggleGate`, `KeyTranslator`, `Preferences.toggleKeyCode` (existing), `HangulComposer` (existing).
- Produces: a controller that no longer references `LanguageMode` (Task 5 deletes it).

**Key changes from the current file:**
- `private let language = LanguageMode()` and `private var korean = false` are replaced by `private var mode: InputMode = .korean`.
- New `nonisolated override func setValue(_:forTag:client:)` — IMK reports the active mode through `kTextServiceInputModePropertyTag`; that is where `mode` is updated and the composer flushed.
- `activateServer` no longer restores language from `LanguageMode` (macOS decides which mode activates).
- On toggle: flush, then `ModeSwitcher.select(mode.other) { id in client.selectMode(id) }`. `mode` is NOT set optimistically — IMK reports the new mode via `setValue`.
- `handleKeyEvent` composes only when `mode == .korean`.
- `togglePerAppMemory` is gone (Task 5 removes the menu item).

- [ ] **Step 1: Write the complete file**

`Sources/Bomi/BomiInputController.swift`:

```swift
import AppKit
import InputMethodKit
import Carbon
import BomiEngine
import BomiCore

/// IMK always invokes `handle(_:client:)` on the main thread, but the ObjC
/// `sender` parameter isn't `Sendable`. This box lets us carry it across the
/// (statically required, dynamically already-satisfied) hop into the
/// `MainActor.assumeIsolated` closure below.
private nonisolated struct UncheckedSendableBox<Value>: @unchecked Sendable {
    let value: Value
}

@objc(BomiInputController)
final class BomiInputController: IMKInputController {
    private var composer = HangulComposer()
    private var gate = ToggleGate()

    /// The active input source IS the Han/Eng state — macOS owns it. IMK reports
    /// it via `setValue(_:forTag:client:)` with `kTextServiceInputModePropertyTag`.
    private var mode: InputMode = .korean

    /// Keys that end/interrupt composition and are handled by the app itself:
    /// Enter(0x24), Return(0x4C), Tab(0x30), Escape(0x35), arrows(0x7B-0x7E), space(0x31).
    private static let passthroughKeys: Set<UInt16> = [0x24, 0x4C, 0x30, 0x35, 0x7B, 0x7C, 0x7D, 0x7E, 0x31]

    nonisolated override init() {
        super.init()
    }

    nonisolated override init(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        super.init(server: server, delegate: delegate, client: inputClient)
    }

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

    /// Flush any in-progress syllable to the client. Used on blur/commit/mode change.
    private func flush(_ client: IMKTextInput) {
        let tail = composer.flush()
        if !tail.isEmpty { client.insertText(tail, replacementRange: noRange) }
    }

    private func handleToggleFlags(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags, client: IMKTextInput) {
        let isToggleKey = keyCode == Preferences.shared.toggleKeyCode
        let toggleKeyDown = modifierFlags.contains(.command)
        let otherModifiers = !modifierFlags.intersection([.shift, .control, .option]).isEmpty
        guard gate.flagsChanged(isToggleKey: isToggleKey, toggleKeyDown: toggleKeyDown,
                                otherModifiersPresent: otherModifiers) else { return }

        // Commit what's in flight, then hand the switch to macOS. `mode` is not set
        // here — IMK reports the new mode back through setValue(_:forTag:client:).
        flush(client)
        ModeSwitcher.select(mode.other) { id in client.selectMode(id) }
    }

    private func handleKeyEvent(keyCode: UInt16, flags: NSEvent.ModifierFlags, client: IMKTextInput) -> Bool {
        // Any non-modifier keyDown means Right-Command (if held) is part of a chord,
        // not a bare tap — disarm so releasing it does NOT fire the Han/Eng toggle.
        gate.chordInterrupt()

        // Modifiers other than Shift: commit and pass through (e.g. Cmd+C).
        if flags.contains(.command) || flags.contains(.control) || flags.contains(.option) {
            flush(client)
            return false
        }

        // Roman mode: we stay active (so Right-Command still reaches us) but type nothing.
        if mode != .korean {
            flush(client)
            return false
        }

        let shift = flags.contains(.shift)

        // Backspace (0x33)
        if keyCode == 0x33 {
            if composer.backspace() { showPreedit(client); return true }
            return false
        }
        if Self.passthroughKeys.contains(keyCode) {
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

    nonisolated override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event else { return false }
        let boxed = UncheckedSendableBox(value: sender)

        // Han/Eng toggle: bare Right-Command tap (down with no chord).
        if event.type == .flagsChanged {
            let keyCode = event.keyCode
            let modifierFlags = event.modifierFlags
            MainActor.assumeIsolated {
                guard let client = boxed.value as? IMKTextInput else { return }
                self.handleToggleFlags(keyCode: keyCode, modifierFlags: modifierFlags, client: client)
            }
            return false
        }

        guard event.type == .keyDown else { return false }
        let keyCode = event.keyCode
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return MainActor.assumeIsolated {
            guard let client = boxed.value as? IMKTextInput else { return false }
            return self.handleKeyEvent(keyCode: keyCode, flags: flags, client: client)
        }
    }

    /// IMK tells us which of our modes is active here. This is the ONLY place
    /// `mode` changes.
    nonisolated override func setValue(_ value: Any!, forTag tag: Int, client sender: Any!) {
        let boxed = UncheckedSendableBox(value: sender)
        let boxedValue = UncheckedSendableBox(value: value)
        if tag == kTextServiceInputModePropertyTag {
            MainActor.assumeIsolated {
                let newMode = InputMode.from(id: boxedValue.value as? String)
                guard newMode != self.mode else { return }
                self.mode = newMode
                // Never carry a half-composed syllable across a language change.
                if let client = self.client(boxed.value) {
                    self.flush(client)
                } else {
                    _ = self.composer.flush()
                }
            }
        }
        super.setValue(value, forTag: tag, client: sender)
    }

    nonisolated override func recognizedEvents(_ sender: Any!) -> Int {
        Int(NSEvent.EventTypeMask.keyDown.rawValue | NSEvent.EventTypeMask.flagsChanged.rawValue)
    }

    nonisolated override func activateServer(_ sender: Any!) {
        MainActor.assumeIsolated {
            // macOS decides which mode activates; it reports it via setValue.
            // Just make sure no stale composition survives the activation.
            _ = self.composer.flush()
        }
    }

    nonisolated override func commitComposition(_ sender: Any!) {
        let boxed = UncheckedSendableBox(value: sender)
        MainActor.assumeIsolated {
            if let client = self.client(boxed.value) { self.flush(client) } else { _ = self.composer.flush() }
        }
    }

    nonisolated override func deactivateServer(_ sender: Any!) {
        let boxed = UncheckedSendableBox(value: sender)
        MainActor.assumeIsolated {
            if let client = self.client(boxed.value) { self.flush(client) } else { _ = self.composer.flush() }
        }
    }

    nonisolated override func menu() -> NSMenu! {
        let boxed: UncheckedSendableBox<NSMenu> = MainActor.assumeIsolated {
            UncheckedSendableBox(value: MenuBuilder.build(mode: self.mode))
        }
        return boxed.value
    }
}
```

- [ ] **Step 2: Build (it will fail — MenuBuilder still has the old signature)**

Run: `swift build 2>&1 | tail -5`
Expected: FAIL — `MenuBuilder.build(mode:)` doesn't exist yet. That is Task 5. Do not fix it here; commit nothing until Task 5 compiles.

Proceed directly to Task 5 — Tasks 4 and 5 land as one compiling commit.

---

### Task 5: Delete `LanguageMode` + per-app memory, simplify the menu

**Files:**
- Delete: `Sources/BomiCore/LanguageMode.swift`, `Tests/BomiCoreTests/LanguageModeTests.swift`
- Modify: `Sources/BomiCore/Preferences.swift` (whole file below)
- Modify: `Sources/Bomi/MenuBuilder.swift` (whole file below)
- Modify: `Tests/BomiCoreTests/PreferencesTests.swift` (whole file below)

**Interfaces:**
- Consumes: `InputMode` (Task 2).
- Produces: `MenuBuilder.build(mode: InputMode) -> NSMenu` (called by Task 4's `menu()`); `Preferences.shared.toggleKeyCode` only.

**Why:** per-app language memory is now macOS's job (System Settings ▸ Keyboard ▸ per-document input source). `LanguageMode` stored global+per-app state that nothing reads any more, and `Preferences.perAppMemory` toggled a feature that no longer exists.

- [ ] **Step 1: Delete LanguageMode and its tests**

```bash
git rm -q Sources/BomiCore/LanguageMode.swift Tests/BomiCoreTests/LanguageModeTests.swift
```

- [ ] **Step 2: Rewrite `Sources/BomiCore/Preferences.swift`**

```swift
import Foundation

// `@unchecked`: the only stored property is a `UserDefaults`, which is
// documented thread-safe; the compiler just can't see that.
public final class Preferences: @unchecked Sendable {
    public static let shared = Preferences()
    private let d: UserDefaults

    /// `defaults` is injectable so tests can run against an isolated suite
    /// instead of the process-wide standard store.
    public init(defaults: UserDefaults = .standard) {
        self.d = defaults
        d.register(defaults: ["toggleKeyCode": 0x36])
    }

    /// `UInt16(exactly:)` (not the trapping `UInt16(_:)`) so an out-of-range
    /// stored value can never crash the IME — falls back to Right Command.
    public var toggleKeyCode: UInt16 { UInt16(exactly: d.integer(forKey: "toggleKeyCode")) ?? 0x36 }
}
```

- [ ] **Step 3: Rewrite `Tests/BomiCoreTests/PreferencesTests.swift`**

```swift
import Testing
import Foundation
@testable import BomiCore

@Test func defaultsWhenUnset() {
    let d = UserDefaults(suiteName: "bomi.test.prefdefault")!
    d.removePersistentDomain(forName: "bomi.test.prefdefault")
    let p = Preferences(defaults: d)
    #expect(p.toggleKeyCode == 0x36)
}

@Test func toggleKeyCodeClampsOutOfRange() {   // must not trap on a bad stored value
    let d = UserDefaults(suiteName: "bomi.test.prefrange")!
    d.removePersistentDomain(forName: "bomi.test.prefrange")
    d.set(999_999, forKey: "toggleKeyCode")   // > UInt16.max
    let p = Preferences(defaults: d)
    #expect(p.toggleKeyCode == 0x36)   // falls back to Right Command instead of crashing
}
```

- [ ] **Step 4: Rewrite `Sources/Bomi/MenuBuilder.swift`**

```swift
import AppKit
import BomiCore

enum MenuBuilder {
    static func build(mode: InputMode) -> NSMenu {
        let menu = NSMenu(title: "Bomi")

        let current = NSMenuItem(title: mode == .korean ? "한글 (세벌식 최종)" : "로마자 (English)",
                                 action: nil, keyEquivalent: "")
        current.isEnabled = false
        menu.addItem(current)
        menu.addItem(.separator())

        let toggleInfo = NSMenuItem(title: "한/영 전환 키: 오른쪽 Command", action: nil, keyEquivalent: "")
        toggleInfo.isEnabled = false
        menu.addItem(toggleInfo)

        let about = NSMenuItem(title: "Bomi 정보", action: nil, keyEquivalent: "")
        about.isEnabled = false
        menu.addItem(about)
        return menu
    }
}
```

- [ ] **Step 5: Build and run the full gate**

Run: `swift build 2>&1 | tail -3 && swift test 2>&1 | tail -3`
Expected: `Build complete!` and all tests pass. Test count stays at **27**: 15 BomiEngine + 12 BomiCore (5 ToggleGate + 2 KeyTranslator + 2 Preferences + 3 InputMode). The 3 LanguageMode tests are deleted and the 3 InputMode tests replace them; `PreferencesTests` keeps 2 tests (the `perAppMemory` assertion is dropped from `defaultsWhenUnset`).

- [ ] **Step 6: Commit Tasks 4 + 5 together**

```bash
git add -A Sources Tests
git commit -m "feat(imk): han/eng by switching input source; delete LanguageMode (macOS owns per-app now)"
```

---

### Task 6: Assemble, install, and verify on-device

**Files:** none (verification only).

**Interfaces:** consumes everything above.

- [ ] **Step 1: Assemble and install**

Run:
```bash
./Scripts/assemble-app.sh && ./Scripts/install.sh
```
Expected: `Assembled Bomi.app`, `Installed to ~/Library/Input Methods/Bomi.app`.

- [ ] **Step 2: Confirm BOTH modes register (after logout/login)**

The user must **log out and log back in** — macOS caches the input-source set, and we added a mode.

Then run the TIS probe:
```bash
swift /private/tmp/claude-501/-Users-bglee-Project-bomi-input/d43e5b0a-00de-4486-b3b6-5ae9326d10c1/scratchpad/tis-probe.swift
```
Expected: entries for BOTH `com.bomi.inputmethod.bomi.korean` and `com.bomi.inputmethod.bomi.roman`, each `Enabled=true`, `SelectCapable=true`, with `LocalizedName` "보미" / "보미 로마자" (or the English names).

If the Roman mode is missing, the user must add it in System Settings ▸ Keyboard ▸ Input Sources ▸ `+` (both entries must be enabled for `TISSelectInputSource` to reach them).

- [ ] **Step 3: Manual verification (the point of this whole plan)**

In TextEdit with Bomi active:

1. Menu bar shows **ㅂ** in Korean mode.
2. Type `k f s` → `간` composes and commits.
3. Tap **Right Command** → menu bar flips to **B**, and typing produces plain English letters (no Hangul).
4. Tap **Right Command** again → back to **ㅂ**, Hangul composition works again. **Both directions must work** — this is what having our own Roman mode buys.
5. Mid-syllable toggle: type `k f` (incomplete), tap Right-Command → the partial syllable commits, no jamo is lost.
6. Right-Command **+ C** (copy) → must NOT flip the mode (chord, not a bare tap).
7. Cmd-Tab to another app and back → mode indicator still correct.

Record results in `.claude/worklog.md`.

- [ ] **Step 4: Commit any fixes, then report**

If steps 1–7 all pass, the feature is done. If a step fails, use superpowers:systematic-debugging — do not guess-patch.

---

## Notes for the implementer

- **Do not** add a `korean` boolean back to the controller "for convenience". The whole point is that macOS owns the mode; two sources of truth will drift.
- **Do not** switch to `com.apple.keylayout.ABC` for English. That deactivates our IME and the toggle becomes one-way.
- `kTextServiceInputModePropertyTag` comes from `Carbon` — the controller imports it.
- If `swift build` complains that `setValue(_:forTag:client:)` is implicitly MainActor-isolated, mark it `nonisolated override` (same pattern as every other IMK override in this file).
