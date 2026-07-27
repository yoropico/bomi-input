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
    /// How the switch was performed. Reported so a failure is attributable to a
    /// specific layer instead of guessed at.
    enum Outcome: String {
        /// TIS switched us using the cached source ref.
        case tisCached
        /// TIS switched us after re-looking the source up.
        case tisFresh
        /// TIS refused; handed to IMK's own slow path, whose result we cannot verify.
        case fallback
    }

    /// `TISInputSource` refs keyed by mode id. The input-source list almost never
    /// changes, so caching avoids a `TISCreateInputSourceList` scan per toggle.
    /// Only touched on the main thread (IMK input handling).
    private static var cache: [String: TISInputSource] = [:]

    private static func currentSourceID() -> String? {
        guard let src = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(src, kTISPropertyInputSourceID) else { return nil }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }

    /// The id of the source macOS has active right now, ours or not. The debug log
    /// needs this: "it switched to somebody else's source" and "it did not switch"
    /// are different failures, and `currentMode()` flattens both to nil.
    static func currentID() -> String { currentSourceID() ?? "(none)" }

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

    /// Switch by asking **IMK itself** (`selectInputMode:`) instead of replacing the
    /// input source behind IMK's back with `TISSelectInputSource`.
    ///
    /// Why: on-device, every TIS-driven toggle leaves IMK's event routing stale — the
    /// controller keeps receiving `keyDown` but never another `flagsChanged`, so the
    /// next Right-Cmd is lost and only refocusing the app repairs it. IMK cannot be
    /// expected to keep its routing coherent across a source switch it was never told
    /// about. `selectMode` is that same switch, announced.
    ///
    /// The "`selectMode` is a ~1 second slow path" claim that made us abandon it was
    /// never actually timed, so this measures it: the poll below reports how long the
    /// switch really took to land in TIS.
    static func selectViaIMK(_ mode: InputMode, selectMode: (String) -> Void) {
        let id = mode.rawValue
        let started = ProcessInfo.processInfo.systemUptime
        selectMode(id)
        pollUntilLanded(id: id, startedAt: started, attempt: 0)
    }

    /// Polls TIS off the input path so the real cost of `selectMode` is a measured
    /// number in the log, not a remembered one.
    private static func pollUntilLanded(id: String, startedAt: TimeInterval, attempt: Int) {
        let elapsedMs = Int((ProcessInfo.processInfo.systemUptime - startedAt) * 1000)
        if currentSourceID() == id {
            DebugLog.log("    ModeSwitcher: IMK selectMode landed in \(elapsedMs)ms")
            return
        }
        guard attempt < 100 else {   // 100 * 20ms = 2s ceiling
            DebugLog.log("    ModeSwitcher: IMK selectMode did NOT land within \(elapsedMs)ms")
            // The optimistic cache is now wrong, and nothing re-reads TIS until the
            // next focus change — until then every controller types in the stale
            // language. Heal it from TIS, which is the truth here: this path is
            // reached only because the switch never landed, so there is no
            // landed-then-retoggled race to lose. (The success path above must NOT
            // resync: there a fast re-toggle can legitimately disagree with TIS.)
            if let actual = currentMode() {
                ModeState.current = actual
                DebugLog.log("    ModeSwitcher: resynced ModeState.current=\(actual.rawValue) from TIS")
            }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(20)) {
            MainActor.assumeIsolated {
                pollUntilLanded(id: id, startedAt: startedAt, attempt: attempt + 1)
            }
        }
    }

    @discardableResult
    static func select(_ mode: InputMode, fallback: (String) -> Void) -> Outcome {
        let id = mode.rawValue

        if let cached = cache[id], selectAndVerify(cached, id: id) { return .tisCached }
        cache[id] = nil   // stale ref, or the select didn't take — re-look it up

        let filter = [kTISPropertyInputSourceID as String: id] as NSDictionary
        let list = (TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource]) ?? []
        if let source = list.first, selectAndVerify(source, id: id) {
            cache[id] = source
            return .tisFresh
        }

        // TIS refused — hand it to IMK's own slow path.
        DebugLog.log("    ModeSwitcher: TIS refused '\(id)' (matches=\(list.count)) -> IMK selectMode fallback")
        fallback(id)
        return .fallback
    }
}
