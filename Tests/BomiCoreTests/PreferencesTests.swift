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
