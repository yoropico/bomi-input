import Foundation

/// What to do with a keyDown whose toggle-key modifier bit was just stripped
/// (the key overlapped the Han/Eng toggle; see `ToggleGate.heldModifier`).
public enum HeldKeyAction: Equatable, Sendable {
    /// Korean mode, a composable key: run the normal composer path. Its
    /// `setMarkedText` is what already makes the key count as consumed.
    case compose
    /// Mark the text now and commit it on the next runloop turn.
    case markThenCommit(String)
    /// Nothing sensible to type (arrows, backspace, return, escape): consume it.
    case swallow
}

/// A stripped key must never be handed back to the app: `return false` passes
/// the ORIGINAL Cmd+key through, and the app runs it as a shortcut. So the
/// controller either types the key itself or swallows it.
///
/// Typing it has a Chromium-specific trap. In Chromium hosts (Edge, Electron
/// apps such as 1Password) a key equivalent does reach the IME first, but the
/// browser afterwards still forwards the REAL Cmd+key keydown to the page --
/// and, unhandled there, to its own accelerators -- unless the IME left marked
/// text or inserted more than one character during that event
/// (render_widget_host_view_cocoa.mm, `keyEvent:wasKeyEquivalent:`:
/// `if (_hasMarkedText || oldHasMarkedText || _textToBeInserted.length() > 1)`
/// sends a VK_PROCESSKEY stand-in, the `else` sends the real event). A plain
/// one-character `insertText` therefore typed the letter AND fired Cmd+A /
/// Cmd+R / Cmd+W (on-device 2026-09-07: every roman-mode strip in Edge). Marking
/// the character first and committing it a runloop turn later is what makes
/// Chromium take the consumed branch; every other client already handles that
/// mark-then-commit sequence, because Korean typing is nothing else.
public enum HeldKeyPolicy {
    /// - Parameters:
    ///   - korean: the mode the keyDown arrived in (already the toggle's target).
    ///   - composable: the key maps to a jamo (not a passthrough key or backspace).
    ///   - chars: the event's `characters`.
    public static func action(korean: Bool, composable: Bool, chars: String) -> HeldKeyAction {
        if korean && composable { return .compose }
        guard chars.unicodeScalars.count == 1, let s = chars.unicodeScalars.first,
              (0x20...0x7E).contains(s.value) else { return .swallow }
        return .markThenCommit(chars)
    }
}
