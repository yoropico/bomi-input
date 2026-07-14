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
}
