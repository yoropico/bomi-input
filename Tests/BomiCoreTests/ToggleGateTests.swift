import Testing
@testable import BomiCore

// Right-Command Han/Eng toggle: fires only on a *bare* down→up tap, never as
// part of a chord. Pure state machine so the rule is testable without IMK.

@Test func bareTapTogglesOnRelease() {
    var g = ToggleGate()
    #expect(g.flagsChanged(isToggleKey: true, toggleKeyDown: true, otherModifiersPresent: false) == false)
    #expect(g.armed == true)
    #expect(g.flagsChanged(isToggleKey: true, toggleKeyDown: false, otherModifiersPresent: false) == true)
    #expect(g.armed == false)
}

@Test func chordWithLetterDoesNotToggle() {
    var g = ToggleGate()
    _ = g.flagsChanged(isToggleKey: true, toggleKeyDown: true, otherModifiersPresent: false) // armed
    g.chordInterrupt()  // a non-modifier keyDown (e.g. the 'C' of Cmd+C)
    #expect(g.armed == false)
    #expect(g.flagsChanged(isToggleKey: true, toggleKeyDown: false, otherModifiersPresent: false) == false)
}

@Test func preHeldModifierDoesNotArm() {   // #4
    var g = ToggleGate()
    // Shift already held when Right-Command goes down -> chord, must not arm.
    #expect(g.flagsChanged(isToggleKey: true, toggleKeyDown: true, otherModifiersPresent: true) == false)
    #expect(g.armed == false)
    #expect(g.flagsChanged(isToggleKey: true, toggleKeyDown: false, otherModifiersPresent: true) == false)
}

@Test func otherModifierChangeDisarms() {
    var g = ToggleGate()
    _ = g.flagsChanged(isToggleKey: true, toggleKeyDown: true, otherModifiersPresent: false) // armed
    // A different modifier's flagsChanged arrives before the toggle key is released.
    #expect(g.flagsChanged(isToggleKey: false, toggleKeyDown: false, otherModifiersPresent: false) == false)
    #expect(g.armed == false)
    #expect(g.flagsChanged(isToggleKey: true, toggleKeyDown: false, otherModifiersPresent: false) == false)
}

@Test func loneReleaseDoesNotToggle() {
    var g = ToggleGate()
    #expect(g.flagsChanged(isToggleKey: true, toggleKeyDown: false, otherModifiersPresent: false) == false)
}
