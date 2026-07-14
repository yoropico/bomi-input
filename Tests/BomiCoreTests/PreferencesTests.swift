import Testing
import Foundation
@testable import BomiCore

private func freshDefaults(_ name: String) -> UserDefaults {
    let d = UserDefaults(suiteName: name)!
    d.removePersistentDomain(forName: name)
    return d
}

@Test func defaultToggleKeyIsRightCommand() {
    let p = Preferences(defaults: freshDefaults("bomi.test.prefdefault"))
    #expect(p.toggleKeyCode == 0x36)   // kVK_RightCommand
}

@Test func toggleKeyCodeIsOverridable() {
    let d = freshDefaults("bomi.test.prefoverride")
    d.set(0x3D, forKey: "toggleKeyCode")   // Right Option
    let p = Preferences(defaults: d)
    #expect(p.toggleKeyCode == 0x3D)
}

@Test func toggleKeyCodeClampsOutOfRange() {   // must not trap on a bad stored value
    let d = freshDefaults("bomi.test.prefrange")
    d.set(999_999, forKey: "toggleKeyCode")   // > UInt16.max
    let p = Preferences(defaults: d)
    #expect(p.toggleKeyCode == 0x36)
}

// Royal TSX rewrites the physical key before the IME ever sees it: pressing
// Right-Command arrives as Right-Option (verified on-device — 24/24 events were
// keyCode 61, keyCode 54 never once, even with no RDP session connected).
// So in that app we must accept 61 as the toggle key, or the user's normal
// Right-Command does nothing there.

@Test func royalTSXSubstitutesRightOptionForRightCommand() {
    let p = Preferences(defaults: freshDefaults("bomi.test.prefapp"))
    #expect(p.toggleKeyCode(forApp: "com.lemonmojo.RoyalTSX.App") == 0x3D)
}

@Test func otherAppsUseTheConfiguredKey() {
    let p = Preferences(defaults: freshDefaults("bomi.test.prefapp2"))
    #expect(p.toggleKeyCode(forApp: "com.apple.TextEdit") == 0x36)
    #expect(p.toggleKeyCode(forApp: nil) == 0x36)
}

@Test func substitutionOnlyAppliesWhenToggleKeyIsRightCommand() {
    // If the user deliberately picked another toggle key, don't second-guess them.
    let d = freshDefaults("bomi.test.prefapp3")
    d.set(0x3C, forKey: "toggleKeyCode")   // Right Shift
    let p = Preferences(defaults: d)
    #expect(p.toggleKeyCode(forApp: "com.lemonmojo.RoyalTSX.App") == 0x3C)
}
