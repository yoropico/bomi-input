import Foundation

/// Pure state machine for the Right-Command Han/Eng toggle. It fires only on a
/// *bare* down→up tap of the toggle key; any chord (another modifier held, or a
/// non-modifier key pressed in between) disarms it. Kept IMK-free so the rule is
/// unit-testable — the controller feeds it decoded flag/key facts.
public struct ToggleGate {
    public private(set) var armed = false
    public init() {}

    /// Process a `flagsChanged` event. Returns `true` iff the toggle should fire now.
    /// - Parameters:
    ///   - isToggleKey: the key whose modifier changed is the configured toggle key.
    ///   - toggleKeyDown: that modifier's bit is now present (down) vs absent (up).
    ///   - otherModifiersPresent: any of Shift/Control/Option is currently held.
    public mutating func flagsChanged(isToggleKey: Bool, toggleKeyDown: Bool, otherModifiersPresent: Bool) -> Bool {
        // A change on any *other* modifier means the toggle key is part of a chord.
        guard isToggleKey else { armed = false; return false }
        if toggleKeyDown {
            // #4: arm only for a clean press — another modifier already held is a chord.
            armed = !otherModifiersPresent
            return false
        }
        // Release: fire iff still armed, then always disarm.
        let fire = armed
        armed = false
        return fire
    }

    /// A non-modifier keyDown arrived — the toggle key (if held) is part of a
    /// chord (e.g. the "C" of Right-Command+C), so it must not fire on release.
    public mutating func chordInterrupt() { armed = false }
}
