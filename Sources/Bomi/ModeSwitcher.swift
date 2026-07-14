import Foundation
import Carbon
import BomiCore

/// Switches the system input source between our two modes, and reports which one
/// is actually active.
///
/// IMK's `selectMode(_:)` (ObjC `selectInputMode:`) is a ~1 second slow path.
/// `TISSelectInputSource` — the same mechanism as Ctrl-Opt-Space — switches
/// immediately AND makes macOS refresh the menu-bar icon, which is the whole
/// point of this feature. We verify the switch really took (rather than trusting
/// the return code) and fall back to `selectMode` if it didn't.
enum ModeSwitcher {
    /// `TISInputSource` refs keyed by mode id. The input-source list almost never
    /// changes, so caching avoids a `TISCreateInputSourceList` scan per toggle.
    /// Only touched on the main thread (IMK input handling).
    private static var cache: [String: TISInputSource] = [:]

    private static func currentSourceID() -> String? {
        guard let src = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(src, kTISPropertyInputSourceID) else { return nil }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }

    /// The mode macOS actually has active right now, or nil if the active source
    /// isn't one of ours.
    ///
    /// **This is the source of truth, not IMK's `setValue(_:forTag:client:)`.**
    /// On-device: switching korean→roman does deliver `setValue`, but roman→korean
    /// delivers nothing. A controller that only learns the mode from `setValue`
    /// therefore sticks on the stale value forever, after which every toggle merely
    /// re-selects the already-active source — the "한/영 전환이 안 됨" bug.
    static func currentMode() -> InputMode? {
        guard let id = currentSourceID() else { return nil }
        return InputMode(rawValue: id)
    }

    /// Select and verify: true only if the current source really became `id`.
    private static func selectAndVerify(_ source: TISInputSource, id: String) -> Bool {
        TISSelectInputSource(source) == noErr && currentSourceID() == id
    }

    static func select(_ mode: InputMode, fallback: (String) -> Void) {
        let id = mode.rawValue

        if let cached = cache[id], selectAndVerify(cached, id: id) { return }
        cache[id] = nil   // stale ref, or the select didn't take — re-look it up

        let filter = [kTISPropertyInputSourceID as String: id] as NSDictionary
        let list = (TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource]) ?? []
        if let source = list.first, selectAndVerify(source, id: id) {
            cache[id] = source
            return
        }

        // TIS refused — hand it to IMK's own slow path.
        fallback(id)
    }
}
