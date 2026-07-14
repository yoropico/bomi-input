import Foundation

/// The two input sources this IME declares in Info.plist. The ACTIVE mode is the
/// single source of truth for Han/Eng — macOS owns it, so the controller keeps no
/// language boolean and no per-app map.
public enum InputMode: String, Sendable, CaseIterable {
    case korean = "com.bomi.inputmethod.bomi.korean"
    case roman = "com.bomi.inputmethod.bomi.roman"

    /// The mode a Right-Command tap switches to.
    public var other: InputMode { self == .korean ? .roman : .korean }

    /// Map an IMK mode identifier to a mode. An unknown or absent id means macOS
    /// has not told us yet — assume Korean, our default-state mode.
    public static func from(id: String?) -> InputMode {
        guard let id, let mode = InputMode(rawValue: id) else { return .korean }
        return mode
    }
}
