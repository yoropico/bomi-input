import Testing
import Foundation
@testable import BomiCore

// The non-modifier toggle (F18, produced by Karabiner from Right-Command). A
// plain key has no modifier to overlap the next keystroke with, which is the
// whole point; the gate only has to debounce and ignore autorepeat.

private let f18: UInt16 = 0x4F
private let rightCmd: UInt16 = 0x36

@Test func plainKeyTogglesOnKeyDown() {
    var g = ToggleGate()
    #expect(g.keyDown(keyCode: f18, toggleKeyCode: f18, isRepeat: false, now: 0) == .fire)
    #expect(g.keyDown(keyCode: f18, toggleKeyCode: f18, isRepeat: false, now: 0.5) == .fire)
}

@Test func plainKeyIgnoresAutorepeatAndDuplicates() {
    var g = ToggleGate()
    #expect(g.keyDown(keyCode: f18, toggleKeyCode: f18, isRepeat: false, now: 0) == .fire)
    #expect(g.keyDown(keyCode: f18, toggleKeyCode: f18, isRepeat: true, now: 0.4) == .suppressed)
    #expect(g.keyDown(keyCode: f18, toggleKeyCode: f18, isRepeat: false, now: 0.005) == .suppressed)
}

@Test func otherKeysAndModifierCodesAreNotPlainToggles() {
    var g = ToggleGate()
    #expect(g.keyDown(keyCode: 0x00, toggleKeyCode: f18, isRepeat: false, now: 0) == .notPress)
    // a modifier keyCode only ever toggles through flagsChanged
    #expect(g.keyDown(keyCode: rightCmd, toggleKeyCode: rightCmd, isRepeat: false, now: 0) == .notPress)
}

@Test func plainKeyFireLeavesNoHeldModifier() {
    var g = ToggleGate()
    _ = g.keyDown(keyCode: f18, toggleKeyCode: f18, isRepeat: false, now: 0)
    #expect(g.heldModifier(now: 0.05) == nil)
}

@Test func keyDownToggleKeyDefaultsToF18AndZeroDisables() {
    let d = UserDefaults(suiteName: "KeyDownToggleTests.\(UUID())")!
    let p = Preferences(defaults: d)
    #expect(p.keyDownToggleKeyCode == 0x4F)
    d.set(0, forKey: "keyDownToggleKeyCode")
    #expect(p.keyDownToggleKeyCode == nil)
    d.set(999_999, forKey: "keyDownToggleKeyCode")
    #expect(p.keyDownToggleKeyCode == nil)
}
