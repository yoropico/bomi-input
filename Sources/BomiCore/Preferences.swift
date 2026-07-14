import Foundation

// `@unchecked`: the only stored property is a `UserDefaults`, which is
// documented thread-safe; the compiler just can't see that.
public final class Preferences: @unchecked Sendable {
    public static let shared = Preferences()
    private let d: UserDefaults

    /// `defaults` is injectable so tests can run against an isolated suite
    /// instead of the process-wide standard store.
    public init(defaults: UserDefaults = .standard) {
        self.d = defaults
        d.register(defaults: ["toggleKeyCode": 0x36, "perAppMemory": true])
    }

    /// `UInt16(exactly:)` (not the trapping `UInt16(_:)`) so an out-of-range
    /// stored value can never crash the IME — falls back to Right Command.
    public var toggleKeyCode: UInt16 { UInt16(exactly: d.integer(forKey: "toggleKeyCode")) ?? 0x36 }
    public var perAppMemory: Bool { d.bool(forKey: "perAppMemory") }
}
