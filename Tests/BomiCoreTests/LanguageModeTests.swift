import Testing
import Foundation
@testable import BomiCore

// Language state must be UserDefaults-backed (spec §6.5): persisted across
// restarts AND shared across the per-client controller instances IMK creates.
// A separate LanguageMode over the same store stands in for a sibling session.

private func freshSuite(_ name: String) -> UserDefaults {
    let d = UserDefaults(suiteName: name)!
    d.removePersistentDomain(forName: name)
    return d
}

@Test func stateIsSharedAndPersistedAcrossInstances() {
    let d = freshSuite("bomi.test.persist")
    let prefs = Preferences(defaults: d)
    let a = LanguageMode(defaults: d, prefs: prefs)
    #expect(a.isKorean(forApp: nil) == false)   // default: English
    a.toggle(forApp: nil)
    #expect(a.isKorean(forApp: nil) == true)
    // A distinct instance over the same store must see it (shared + persisted).
    let b = LanguageMode(defaults: d, prefs: prefs)
    #expect(b.isKorean(forApp: nil) == true)
}

@Test func perAppMemoryRemembersEachApp() {
    let d = freshSuite("bomi.test.perapp")
    let prefs = Preferences(defaults: d)   // perAppMemory defaults true
    let lang = LanguageMode(defaults: d, prefs: prefs)
    lang.toggle(forApp: "com.apple.TextEdit")   // English -> Korean
    lang.toggle(forApp: "com.apple.Terminal")   // Korean(global) -> English
    #expect(lang.isKorean(forApp: "com.apple.TextEdit") == true)
    #expect(lang.isKorean(forApp: "com.apple.Terminal") == false)
    // and it survives into a fresh instance
    let lang2 = LanguageMode(defaults: d, prefs: prefs)
    #expect(lang2.isKorean(forApp: "com.apple.TextEdit") == true)
    #expect(lang2.isKorean(forApp: "com.apple.Terminal") == false)
}

@Test func perAppMemoryDisabledUsesGlobalOnly() {
    let d = freshSuite("bomi.test.noperapp")
    d.set(false, forKey: "perAppMemory")
    let prefs = Preferences(defaults: d)
    let lang = LanguageMode(defaults: d, prefs: prefs)
    lang.toggle(forApp: "com.apple.TextEdit")   // global -> Korean
    #expect(lang.isKorean(forApp: "com.apple.Terminal") == true)  // global, ignores per-app
    #expect(lang.isKorean(forApp: "whatever") == true)
}
