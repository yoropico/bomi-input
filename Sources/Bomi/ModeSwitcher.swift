import Carbon
import BomiCore

/// Switches the system input source between our two modes.
///
/// IMK's `selectMode(_:)` (ObjC `selectInputMode:`) is a ~1 second slow path.
/// `TISSelectInputSource` — the same mechanism as Ctrl-Opt-Space — switches
/// immediately AND makes macOS refresh the menu-bar icon, which is the whole
/// point of this feature. If the target source is disabled or missing (e.g. the
/// user removed the Roman entry from Input Sources), fall back to `selectMode`.
enum ModeSwitcher {
    /// `TISInputSource` refs keyed by mode id. The input-source list almost never
    /// changes, so caching avoids a `TISCreateInputSourceList` scan per toggle.
    /// Only touched on the main thread (IMK input handling).
    private static var cache: [String: TISInputSource] = [:]

    static func select(_ mode: InputMode, fallback: (String) -> Void) {
        let id = mode.rawValue

        if let cached = cache[id], TISSelectInputSource(cached) == noErr { return }
        cache[id] = nil   // stale ref (source disabled/removed) — re-look it up

        let filter = [kTISPropertyInputSourceID as String: id] as NSDictionary
        if let source = (TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource])?.first,
           TISSelectInputSource(source) == noErr {
            cache[id] = source
            return
        }

        fallback(id)
    }
}
