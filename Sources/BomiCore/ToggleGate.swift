import Foundation

/// Outcome of processing one `flagsChanged` event for the Han/Eng toggle key.
public enum ToggleOutcome: Equatable, Sendable {
    /// Not a press of the toggle key — the caller passes the event through.
    case notPress
    /// A duplicate press (would flip 한→영→한) — consumed, but do not toggle.
    case suppressed
    /// Toggle now.
    case fire
}

/// Accumulates `flagsChanged` state so a modifier transition (0→1) can be
/// detected, and can be **reset** at focus/mode boundaries.
///
/// Why reset matters: the toggle switches the input source on press, and that
/// switch makes the following key-up get delivered somewhere else — it never
/// reaches us. Without a reset the command bit stays stuck "down" in `lastFlags`,
/// so every later press cancels out as "no transition" and the toggle is silently
/// eaten (symptom: Right-Cmd does nothing until you refocus the field).
struct ModifierFlagsTracker {
    private(set) var lastFlags: UInt = 0

    /// Update with this event's flags; return the bits that changed since the last one.
    mutating func transition(to flags: UInt) -> UInt {
        let changed = lastFlags ^ flags
        lastFlags = flags
        return changed
    }

    mutating func reset() { lastFlags = 0 }
}

/// Han/Eng toggle detection, modeled on Gureum's on-device-verified rules.
///
/// - Fires on **press** (0→1 transition of the toggle key's modifier bit), never
///   on release: the input-source switch eats the key-up (see `ModifierFlagsTracker`).
/// - **Debounces duplicate presses**: the source switch — and Chromium-based apps —
///   emit two press events a few ms apart for one physical press. Toggling on both
///   flips 한→영→한, which looks exactly like "the toggle doesn't work".
/// - Resets the tracker on **both** the fire and the suppress path, and on focus
///   changes, so a missed key-up can never wedge the state.
///
/// Left/right modifiers cannot be told apart from `modifierFlags` (the
/// device-dependent bits never reach an IME — only the device-independent
/// `.command` bit, with no side information). The `flagsChanged` event's
/// `keyCode` does carry it (Right-Command arrives as 0x36), so we key off that.
public struct ToggleGate {
    private var tracker = ModifierFlagsTracker()
    private var lastFireAt: TimeInterval?

    /// Duplicate-press window. A human re-tap is far slower (≥150ms).
    public static let duplicateWindow: TimeInterval = 0.08

    public init() {}

    /// Device-independent modifier bit that the given (left- or right-side)
    /// modifier key sets.
    private static func modifierFlag(forKeyCode keyCode: UInt16) -> UInt? {
        switch keyCode {
        case 0x36, 0x37: return 0x10_0000   // kVK_RightCommand / kVK_Command -> .command
        case 0x3C, 0x38: return 0x2_0000    // kVK_RightShift / kVK_Shift     -> .shift
        case 0x3D, 0x3A: return 0x8_0000    // kVK_RightOption / kVK_Option   -> .option
        case 0x3E, 0x3B: return 0x4_0000    // kVK_RightControl / kVK_Control -> .control
        default: return nil
        }
    }

    /// Process one `flagsChanged`.
    /// - Parameters:
    ///   - keyCode: which modifier key changed (this is the only left/right signal).
    ///   - flagsRaw: the event's `modifierFlags.rawValue`.
    ///   - toggleKeyCode: the configured toggle key (default Right Command, 0x36).
    ///   - now: monotonic seconds; injected so the debounce is testable.
    public mutating func flagsChanged(keyCode: UInt16, flagsRaw: UInt, toggleKeyCode: UInt16,
                                      now: TimeInterval,
                                      window: TimeInterval = ToggleGate.duplicateWindow) -> ToggleOutcome {
        let changed = tracker.transition(to: flagsRaw)

        guard keyCode == toggleKeyCode, let flag = Self.modifierFlag(forKeyCode: toggleKeyCode) else {
            return .notPress
        }
        // Press == the key's bit went 0 -> 1 in this event.
        guard (changed & flag) != 0, (flagsRaw & flag) != 0 else { return .notPress }

        if let last = lastFireAt, now - last >= 0, now - last < window {
            tracker.reset()   // suppress path MUST reset too, or a missed key-up wedges
            return .suppressed
        }

        lastFireAt = now
        tracker.reset()
        return .fire
    }

    /// Clear accumulated modifier state. Call on activate/deactivate so a key-up
    /// that was delivered elsewhere cannot wedge the next press.
    public mutating func reset() { tracker.reset() }
}
