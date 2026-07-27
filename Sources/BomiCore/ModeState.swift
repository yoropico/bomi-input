import Foundation

/// The one Han/Eng mode cache shared by every input controller in the process.
///
/// macOS (TIS) owns the truth — the active input source IS the mode — but IMK
/// creates one controller per text client, and `selectMode` is asynchronous, so
/// each controller needs a value it can read *now* for the keystroke that may
/// beat the switch. A per-instance cache cannot work: a toggle fired in one app
/// would leave every other app's controller typing in the stale language. This
/// is that single optimistic cache instead. It is repaired from TIS in
/// `activateServer`, hinted by `setValue`, and resynced by `ModeSwitcher` when
/// a requested switch never lands.
///
/// MainActor-isolated because BomiCore has no default isolation to inherit:
/// every access happens on the main thread (the `MainActor.assumeIsolated` runs
/// of IMK callbacks), and the annotation makes the compiler check that.
@MainActor
public enum ModeState {
    public static var current: InputMode = .korean
}
