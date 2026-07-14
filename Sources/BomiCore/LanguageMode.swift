import Foundation

/// Han/Eng state, backed by `UserDefaults` (spec §6.5). Because the store is
/// process-wide and disk-persisted, the state is automatically shared across the
/// per-client `BomiInputController` instances IMK creates AND survives restarts —
/// no singleton needed, each controller may hold its own `LanguageMode`.
public final class LanguageMode {
    private let d: UserDefaults
    private let prefs: Preferences
    private static let globalKey = "globalKorean"
    private static let perAppKey = "perAppModes"

    /// `defaults`/`prefs` are injectable so tests run against an isolated suite.
    public init(defaults: UserDefaults = .standard, prefs: Preferences = .shared) {
        self.d = defaults
        self.prefs = prefs
    }

    private var global: Bool {
        get { d.bool(forKey: Self.globalKey) }
        set { d.set(newValue, forKey: Self.globalKey) }
    }

    private var perApp: [String: Bool] {
        get { (d.dictionary(forKey: Self.perAppKey) as? [String: Bool]) ?? [:] }
        set { d.set(newValue, forKey: Self.perAppKey) }
    }

    public func isKorean(forApp bundleID: String?) -> Bool {
        if prefs.perAppMemory, let id = bundleID, let v = perApp[id] { return v }
        return global
    }

    public func toggle(forApp bundleID: String?) {
        let now = !isKorean(forApp: bundleID)
        global = now
        if prefs.perAppMemory, let id = bundleID {
            var m = perApp
            m[id] = now
            perApp = m
        }
    }
}
