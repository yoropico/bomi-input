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
