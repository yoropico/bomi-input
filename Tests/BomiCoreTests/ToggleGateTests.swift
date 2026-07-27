import Testing
@testable import BomiCore

// Right-Command Han/Eng toggle, modeled on Gureum's on-device-verified rules:
//   - fire on PRESS (0→1 transition), never on release: switching the input
//     source makes the following key-up get delivered elsewhere, so a
//     release-based toggle wedges.
//   - debounce duplicate presses (the source switch — and Chromium apps — emit
//     two press events a few ms apart; toggling on both flips 한→영→한).
//   - reset the flag tracker on BOTH fire and suppress, and on focus changes,
//     or a missed key-up leaves the command bit stuck and every later press is
//     cancelled out as "no transition".

private let rightCmd: UInt16 = 0x36
private let leftCmd: UInt16 = 0x37
private let cmdFlag: UInt = 0x10_0000   // device-independent .command
private let shiftFlag: UInt = 0x2_0000

@Test func firesOnPressNotRelease() {
    var g = ToggleGate()
    // press: command bit goes 0 -> 1
    #expect(g.flagsChanged(keyCode: rightCmd, flagsRaw: cmdFlag, toggleKeyCode: rightCmd, now: 0) == .fire)
    // release: command bit goes 1 -> 0 — must NOT fire again
    #expect(g.flagsChanged(keyCode: rightCmd, flagsRaw: 0, toggleKeyCode: rightCmd, now: 0.5) == .notPress)
}

@Test func duplicatePressWithinWindowIsSuppressed() {
    var g = ToggleGate()
    #expect(g.flagsChanged(keyCode: rightCmd, flagsRaw: cmdFlag, toggleKeyCode: rightCmd, now: 0) == .fire)
    // the source switch (or a Chromium app) emits a second press 5ms later
    #expect(g.flagsChanged(keyCode: rightCmd, flagsRaw: cmdFlag, toggleKeyCode: rightCmd, now: 0.005) == .suppressed)
}

@Test func deliberateSecondTapOutsideWindowFires() {
    var g = ToggleGate()
    #expect(g.flagsChanged(keyCode: rightCmd, flagsRaw: cmdFlag, toggleKeyCode: rightCmd, now: 0) == .fire)
    // a human re-tap is far slower than the 80ms window
    #expect(g.flagsChanged(keyCode: rightCmd, flagsRaw: cmdFlag, toggleKeyCode: rightCmd, now: 0.30) == .fire)
}

@Test func missedKeyUpDoesNotWedgeTheNextPress() {
    var g = ToggleGate()
    #expect(g.flagsChanged(keyCode: rightCmd, flagsRaw: cmdFlag, toggleKeyCode: rightCmd, now: 0) == .fire)
    // The key-up never arrives (the input-source switch ate it). The next physical
    // press must still be seen as a 0->1 transition — this is the wedge bug.
    #expect(g.flagsChanged(keyCode: rightCmd, flagsRaw: cmdFlag, toggleKeyCode: rightCmd, now: 1.0) == .fire)
}

@Test func otherModifierKeysAreNotPresses() {
    var g = ToggleGate()
    // Left shift changing state must never toggle.
    #expect(g.flagsChanged(keyCode: 0x38, flagsRaw: shiftFlag, toggleKeyCode: rightCmd, now: 0) == .notPress)
}

@Test func resetClearsAccumulatedFlags() {
    var g = ToggleGate()
    _ = g.flagsChanged(keyCode: rightCmd, flagsRaw: cmdFlag, toggleKeyCode: rightCmd, now: 0)
    g.reset()   // called on activate/deactivate
    // After a reset the very next press is still a clean 0->1 transition.
    #expect(g.flagsChanged(keyCode: rightCmd, flagsRaw: cmdFlag, toggleKeyCode: rightCmd, now: 1.0) == .fire)
}

// Regression: a left-side modifier configured as the toggle key must work too.
// `modifierFlag(forKeyCode:)` used to map only the right-side key codes, so
// Left Command/Shift/Option/Control returned nil and the toggle died silently.
@Test func leftCommandConfiguredAsToggleFires() {
    var g = ToggleGate()
    // press: command bit goes 0 -> 1
    #expect(g.flagsChanged(keyCode: leftCmd, flagsRaw: cmdFlag, toggleKeyCode: leftCmd, now: 0) == .fire)
    // release: command bit goes 1 -> 0 — must NOT fire again
    #expect(g.flagsChanged(keyCode: leftCmd, flagsRaw: 0, toggleKeyCode: leftCmd, now: 0.5) == .notPress)
    // a human re-tap outside the 80ms window fires again
    #expect(g.flagsChanged(keyCode: leftCmd, flagsRaw: cmdFlag, toggleKeyCode: leftCmd, now: 1.0) == .fire)
}

@Test func otherLeftModifiersFires() {
    // Each modifier gets its own gate: firing one sets the debounce timestamp.
    var shiftGate = ToggleGate()
    // Left Shift configured as the toggle key.
    #expect(shiftGate.flagsChanged(keyCode: 0x38, flagsRaw: shiftFlag, toggleKeyCode: 0x38, now: 0) == .fire)
    var optionGate = ToggleGate()
    // Left Option configured as the toggle key.
    #expect(optionGate.flagsChanged(keyCode: 0x3A, flagsRaw: 0x8_0000, toggleKeyCode: 0x3A, now: 0) == .fire)
    var controlGate = ToggleGate()
    // Left Control configured as the toggle key.
    #expect(controlGate.flagsChanged(keyCode: 0x3B, flagsRaw: 0x4_0000, toggleKeyCode: 0x3B, now: 0) == .fire)
}
