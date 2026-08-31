import Foundation

// `@unchecked`: the only stored property is a `UserDefaults`, which is
// documented thread-safe; the compiler just can't see that.
public final class Preferences: @unchecked Sendable {
    public static let shared = Preferences()

    /// Right Command (kVK_RightCommand) — the key Korean users expect for 한/영.
    /// Override with: `defaults write com.bomi.inputmethod.bomi toggleKeyCode 61` (Right Option).
    public static let defaultToggleKeyCode: UInt16 = 0x36

    /// Apps that rewrite the physical modifier before the IME ever sees it.
    ///
    /// Royal TSX delivers **Right-Command as Right-Option**: on-device, 24 of 24
    /// `flagsChanged` events from it carried keyCode 61 and not once keyCode 54 —
    /// and that was with no RDP session connected, in the app's own settings field.
    /// Without this substitution the user's normal Right-Command does nothing there.
    private static let toggleKeySubstitutions: [String: UInt16] = [
        "com.lemonmojo.RoyalTSX.App": 0x3D,   // kVK_RightOption
    ]

    private let d: UserDefaults

    /// `defaults` is injectable so tests can run against an isolated suite
    /// instead of the process-wide standard store.
    public init(defaults: UserDefaults = .standard) {
        self.d = defaults
        d.register(defaults: ["toggleKeyCode": Int(Preferences.defaultToggleKeyCode)])
    }

    /// `UInt16(exactly:)` (not the trapping `UInt16(_:)`) so an out-of-range
    /// stored value can never crash the IME.
    public var toggleKeyCode: UInt16 {
        UInt16(exactly: d.integer(forKey: "toggleKeyCode")) ?? Preferences.defaultToggleKeyCode
    }

    public func setToggleKeyCode(_ keyCode: UInt16) {
        d.set(Int(keyCode), forKey: "toggleKeyCode")
    }

    /// Modifier keys a user can pick as the Han/Eng toggle, with their menu names.
    /// Only lone modifiers qualify: the toggle fires on `flagsChanged`, never `keyDown`.
    public static let toggleKeyChoices: [(name: String, keyCode: UInt16)] = [
        ("오른쪽 Command", 0x36), ("오른쪽 Option", 0x3D), ("오른쪽 Control", 0x3E),
        ("오른쪽 Shift", 0x3C), ("왼쪽 Command", 0x37), ("왼쪽 Option", 0x3A),
        ("왼쪽 Control", 0x3B), ("Caps Lock", 0x39),
    ]

    public static func toggleKeyName(_ keyCode: UInt16) -> String {
        toggleKeyChoices.first { $0.keyCode == keyCode }?.name ?? "keyCode \(keyCode)"
    }

    /// The keyCode that actually arrives from `bundleID` when the user presses the
    /// configured toggle key. Only substitutes when the user is on the default
    /// Right-Command — if they deliberately chose another key, respect it.
    public func toggleKeyCode(forApp bundleID: String?) -> UInt16 {
        let configured = toggleKeyCode
        guard configured == Preferences.defaultToggleKeyCode,
              let id = bundleID,
              let substitute = Preferences.toggleKeySubstitutions[id] else { return configured }
        return substitute
    }

    /// Per-app default input mode, keyed by bundle id and applied on EVERY
    /// activation of that app (not just the first): the user pins Terminal to
    /// English and it stays English no matter what was active before Cmd-Tab.
    /// Also settable from the shell:
    /// `defaults write com.bomi.inputmethod.bomi defaultModeByApp -dict-add com.apple.Terminal com.bomi.inputmethod.bomi.roman`
    private static let defaultModeKey = "defaultModeByApp"

    /// nil = no default for this app; an unparseable stored value also reads as nil
    /// rather than trapping.
    public func defaultMode(forApp bundleID: String?) -> InputMode? {
        guard let bundleID,
              let raw = d.dictionary(forKey: Preferences.defaultModeKey)?[bundleID] as? String
        else { return nil }
        return InputMode(rawValue: raw)
    }

    /// Every app with a default, unparseable entries skipped. Sorted for stable UI rows.
    public func allDefaultModes() -> [(bundleID: String, mode: InputMode)] {
        (d.dictionary(forKey: Preferences.defaultModeKey) ?? [:])
            .compactMap { id, raw in (raw as? String).flatMap(InputMode.init(rawValue:)).map { (id, $0) } }
            .sorted { $0.0 < $1.0 }
    }

    public func setDefaultMode(_ mode: InputMode?, forApp bundleID: String) {
        var map = d.dictionary(forKey: Preferences.defaultModeKey) ?? [:]
        map[bundleID] = mode?.rawValue
        d.set(map, forKey: Preferences.defaultModeKey)
    }
}
