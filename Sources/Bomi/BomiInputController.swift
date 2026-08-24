import AppKit
import InputMethodKit
import Carbon
import BomiEngine
import BomiCore

/// IMK always invokes `handle(_:client:)` on the main thread, but the ObjC
/// `sender` parameter isn't `Sendable`. This box lets us carry it across the
/// (statically required, dynamically already-satisfied) hop into the
/// `MainActor.assumeIsolated` closure below.
private nonisolated struct UncheckedSendableBox<Value>: @unchecked Sendable {
    let value: Value
}

@objc(BomiInputController)
final class BomiInputController: IMKInputController {
    private var composer = HangulComposer()
    private var gate = ToggleGate()

    /// Where the syllable being composed currently sits in the client, as real
    /// text. `nil` when nothing of ours is on screen yet.
    ///
    /// This IME does not use marked text (see `write`), so there is no preedit for
    /// the client to track — this range is the only record of what we put there,
    /// and therefore of what the next keystroke has to overwrite.
    private var rendered: NSRange?

    /// Keys that end/interrupt composition and are handled by the app itself:
    /// Enter(0x24), Return(0x4C), Tab(0x30), Escape(0x35), arrows(0x7B-0x7E), space(0x31).
    private static let passthroughKeys: Set<UInt16> = [0x24, 0x4C, 0x30, 0x35, 0x7B, 0x7C, 0x7D, 0x7E, 0x31]

    nonisolated override init() {
        super.init()
        DebugLog.log("\(tag) init()")
    }

    nonisolated override init(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        super.init(server: server, delegate: delegate, client: inputClient)
        DebugLog.log("\(tag) init(server:delegate:client:)")
    }

    /// IMK documents `sender` as always conforming to IMKTextInput, but the cast
    /// can fail when the client arrives as an XPC proxy. The client is stored on
    /// the controller at creation (one controller per session, per
    /// IMKInputController.h), so fall back to it rather than dropping the text.
    private func client(_ sender: Any!) -> IMKTextInput? {
        if let client = sender as? IMKTextInput { return client }
        guard let stored = super.client() else { return nil }
        return stored
    }
    private let noRange = NSRange(location: NSNotFound, length: NSNotFound)

    /// Short per-instance tag for the debug log. IMK creates one controller per
    /// text client, so "the toggle stopped arriving" may really be "the events now
    /// go to a *different* instance" — indistinguishable without this.
    private nonisolated var tag: String {
        "c\(UInt(bitPattern: ObjectIdentifier(self).hashValue) % 1000)"
    }

    private static func describe(_ r: NSRange) -> String {
        r.location == NSNotFound ? "none" : "\(r.location)+\(r.length)"
    }

    /// Probe: read back what the CLIENT actually holds, rather than what we
    /// believe we sent it. This is how the Mail bug was pinned down — our own log
    /// records only what we send, so the divergence between the two sides stayed
    /// invisible until the client answered for itself.
    ///
    /// Every call is synchronous IPC into the client, so it is gated on the debug
    /// switch and costs a shipped session nothing.
    private func probeClient(_ client: IMKTextInput, _ label: String) {
        guard DebugLog.isEnabled else { return }
        let len = client.length()
        var actual = NSRange(location: NSNotFound, length: 0)
        let whole: String
        if len > 0 {
            whole = client.string(from: NSRange(location: 0, length: len), actualRange: &actual) ?? "(nil)"
        } else {
            whole = ""
        }
        DebugLog.log("      \(self.tag) CLIENT[\(label)] len=\(len) text='\(whole)' "
                     + "sel=\(Self.describe(client.selectedRange())) "
                     + "marked=\(Self.describe(client.markedRange())) "
                     + "got=\(Self.describe(actual))")
    }

    /// Put the composing syllable on screen as ordinary, committed text.
    ///
    /// **Why not `setMarkedText`.** Because Apple's own Korean input method does
    /// not, and that difference was the whole Mail bug. Traced side by side on
    /// 2026-08-24 with `Scripts/imk-client-trace.swift`, Apple 2-Set typing 김형린
    /// emits nothing but `insertText`, each call carrying an explicit
    /// `replacementRange` over the previous rendering of the same syllable — 'ㄱ'
    /// at none, then '기' and '김' each replacing `4+1` — and marks nothing, ever.
    ///
    /// That matters because `NSTextView` refuses to complete while marked text
    /// exists: `rangeForUserCompletion` returns none. With a marked syllable Mail's
    /// recipient field could only ever complete on the committed prefix, so typing
    /// 김형린 it matched '김' and offered 김상태. With every character already
    /// committed it completes on 김형 like an ordinary typist and finds 김형린.
    ///
    /// Writing an empty string deletes the rendering, which is how backspacing to
    /// nothing clears up after itself.
    private func write(_ text: String, _ client: IMKTextInput, _ why: String) {
        let replace = rendered ?? noRange
        probeClient(client, "before \(why)")
        DebugLog.log("    \(tag) -> insertText '\(text)' (\(why)) replacing=\(Self.describe(replace))")
        client.insertText(text, replacementRange: replace)

        if text.isEmpty {
            rendered = nil
        } else if let previous = rendered {
            // Replaced in place: same start, new length.
            rendered = NSRange(location: previous.location, length: text.utf16.count)
        } else {
            // Appended, or dropped onto whatever the client had selected. The
            // caret now sits just past what we wrote, which is the only way to
            // learn where it landed.
            let caret = client.selectedRange()
            rendered = caret.location == NSNotFound || caret.location < text.utf16.count
                ? nil
                : NSRange(location: caret.location - text.utf16.count, length: text.utf16.count)
        }
        probeClient(client, "after \(why)")
    }

    /// Show the syllable currently being composed.
    private func showPreedit(_ client: IMKTextInput) {
        let s = composer.preedit
        guard !s.isEmpty || rendered != nil else { return }
        write(s, client, "preedit")
    }

    /// A syllable is finished. Apple rewrites it once more over its own range
    /// before starting the next one, so do the same and then let the range go: the
    /// text stays, but it is no longer ours to overwrite.
    private func commit(_ text: String, _ client: IMKTextInput) {
        guard !text.isEmpty else { return }
        write(text, client, "commit")
        rendered = nil
    }

    /// End composition. Under this protocol the syllable is already real text in
    /// the client, so nothing is written — only our own state is dropped.
    private func flush(_ client: IMKTextInput) {
        let tail = composer.flush()
        if !tail.isEmpty {
            DebugLog.log("    \(tag) flush '\(tail)' already in client, releasing \(Self.describe(rendered ?? noRange))")
        }
        rendered = nil
    }

    /// Han/Eng toggle. Fires on the PRESS of Right-Command — not the release,
    /// because switching the input source makes the key-up land elsewhere.
    /// Returns whether the event was consumed.
    private func handleToggleFlags(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags,
                                   client: IMKTextInput) -> Bool {
        let bundleID = client.bundleIdentifier() ?? "(nil)"
        let toggleKey = Preferences.shared.toggleKeyCode(forApp: client.bundleIdentifier())
        let outcome = gate.flagsChanged(keyCode: keyCode,
                                        flagsRaw: modifierFlags.rawValue,
                                        toggleKeyCode: toggleKey,
                                        now: ProcessInfo.processInfo.systemUptime)
        DebugLog.log("\(tag) flagsChanged app=\(bundleID) keyCode=\(keyCode) "
                     + "flags=0x\(String(modifierFlags.rawValue, radix: 16)) "
                     + "expectKey=\(toggleKey) outcome=\(outcome) mode=\(ModeState.current.rawValue) "
                     + "preedit='\(composer.preedit)' tis=\(ModeSwitcher.currentID())")

        switch outcome {
        case .notPress:
            return false
        case .suppressed:
            // A duplicate press (the source switch / a Chromium app emits two).
            // Consume it — toggling again would flip straight back.
            //
            // (Returning false here instead was tried and made things strictly worse:
            // every FIRE then lost its key-up, where before only ~1 in 12 did.)
            return true
        case .fire:
            flush(client)
            let target = ModeState.current.other
            // Optimistic. `selectMode` is asynchronous, and the next keystroke can beat
            // the switch; it must already be treated as the new language. The real state
            // is re-read from TIS in `activateServer` and reported by `setValue`.
            // The cache is process-wide, so a toggle fired in this client is already
            // visible to every other app's controller.
            ModeState.current = target

            // Ask IMK to switch, rather than swapping the input source behind its back.
            //
            // `TISSelectInputSource` (used here before) changes the active source without
            // IMK's knowledge, and IMK's event routing is then left stale: this controller
            // keeps getting `keyDown` but never another `flagsChanged`, so the next
            // Right-Cmd is simply lost and only refocusing the app (activateServer) repairs
            // it. Measured on-device: EVERY TIS toggle lost its key-up; what made it look
            // intermittent was that switching apps kept silently repairing it.
            //
            // Still deferred out of this callback: mutating the input state while IMK is
            // mid-dispatch of the event it just handed us is not something to rely on.
            let boxedClient = UncheckedSendableBox(value: client)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    DebugLog.log("  \(self.tag) FIRE target=\(target.rawValue) via=imk-selectMode")
                    ModeSwitcher.selectViaIMK(target) { id in boxedClient.value.selectMode(id) }
                }
            }
            return true
        }
    }

    private func handleKeyEvent(keyCode: UInt16, flags: NSEvent.ModifierFlags,
                                timestamp: TimeInterval, client: IMKTextInput) -> Bool {
        // Modifiers other than Shift: commit and pass through (e.g. Cmd+C).
        if flags.contains(.command) || flags.contains(.control) || flags.contains(.option) {
            flush(client)
            return false
        }

        // Roman mode: we stay active (so Right-Command still reaches us) but type nothing.
        if ModeState.current != .korean {
            flush(client)
            return false
        }

        let shift = flags.contains(.shift)

        // Backspace (0x33)
        if keyCode == 0x33 {
            if composer.backspace() { showPreedit(client); return true }
            return false
        }
        if Self.passthroughKeys.contains(keyCode) {
            flush(client)
            return false   // let the app handle the key itself
        }

        guard let ascii = KeyTranslator.ascii(keyCode: keyCode, shift: shift) else {
            flush(client); return false
        }

        // Timed input enables 모아치기: near-simultaneous keys assemble into one
        // syllable regardless of arrival order (see HangulComposer.chordWindow).
        let committed = composer.inputASCII(ascii, at: timestamp)
        commit(committed, client)
        showPreedit(client)
        return true
    }

    nonisolated override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event else { return false }
        let boxed = UncheckedSendableBox(value: sender)

        if event.type == .flagsChanged {
            let keyCode = event.keyCode
            let modifierFlags = event.modifierFlags
            return MainActor.assumeIsolated {
                guard let client = boxed.value as? IMKTextInput else {
                    DebugLog.log("\(self.tag) flagsChanged keyCode=\(keyCode) DROPPED: sender is not IMKTextInput")
                    return false
                }
                return self.handleToggleFlags(keyCode: keyCode, modifierFlags: modifierFlags, client: client)
            }
        }

        guard event.type == .keyDown else { return false }
        let keyCode = event.keyCode
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let chars = event.characters ?? ""
        let timestamp = event.timestamp
        // Press→IME arrival latency. NSEvent.timestamp and systemUptime share a
        // clock, so this exposes upstream (app event queue / WindowServer) delay
        // that per-key cadence alone cannot show. Field consumed by
        // Scripts/analyze-debug-log.py and the BCT-side probe's stage split.
        let arrivalMs = (ProcessInfo.processInfo.systemUptime - timestamp) * 1000
        return MainActor.assumeIsolated {
            guard let client = boxed.value as? IMKTextInput else { return false }
            DebugLog.log("\(self.tag) keyDown keyCode=\(keyCode) chars='\(chars)' "
                         + "flags=0x\(String(flags.rawValue, radix: 16)) mode=\(ModeState.current.rawValue) "
                         + "lat=\(String(format: "%.0f", arrivalMs))ms")
            return self.handleKeyEvent(keyCode: keyCode, flags: flags, timestamp: timestamp, client: client)
        }
    }

    /// IMK reports the active mode here — but only sometimes (korean→roman yes,
    /// roman→korean no). Treat it as a hint that agrees with TIS, never as the
    /// only source; the toggle path and `activateServer` read TIS directly.
    nonisolated override func setValue(_ value: Any!, forTag tag: Int, client sender: Any!) {
        let boxedValue = UncheckedSendableBox(value: value)
        if tag == kTextServiceInputModePropertyTag {
            MainActor.assumeIsolated {
                let newMode = InputMode.from(id: boxedValue.value as? String)
                DebugLog.log("\(self.tag) setValue mode=\(boxedValue.value as? String ?? "(nil)") "
                             + "parsed=\(newMode.rawValue) current=\(ModeState.current.rawValue)")
                if newMode != ModeState.current {
                    ModeState.current = newMode
                    // A mode change means the toggle key's key-up went elsewhere.
                    self.gate.reset()
                    // Never carry a half-composed syllable across a language change.
                    // Nothing is written: the syllable is already committed text.
                    _ = self.composer.flush()
                    self.rendered = nil
                }
            }
        }
        super.setValue(value, forTag: tag, client: sender)
    }

    /// IMK asks this **once per client** and caches the answer. If a controller
    /// ever goes live without this being asked, it receives keyDown but NOT
    /// flagsChanged — which is exactly the "Right-Cmd does nothing" wedge.
    nonisolated override func recognizedEvents(_ sender: Any!) -> Int {
        let app = (sender as? IMKTextInput)?.bundleIdentifier() ?? "(nil)"
        DebugLog.log("\(tag) recognizedEvents asked by app=\(app)")
        return Int(NSEvent.EventTypeMask.keyDown.rawValue | NSEvent.EventTypeMask.flagsChanged.rawValue)
    }

    nonisolated override func activateServer(_ sender: Any!) {
        let boxed = UncheckedSendableBox(value: sender)
        MainActor.assumeIsolated {
            // Clear accumulated modifier state: a key-up delivered to another
            // controller must not wedge the next press.
            self.gate.reset()
            // Trust TIS, not setValue.
            if let active = ModeSwitcher.currentMode() { ModeState.current = active }
            _ = self.composer.flush()
            // A range measured against the previous focus means nothing here.
            self.rendered = nil
            let app = (self.client(boxed.value)?.bundleIdentifier()) ?? "(nil)"
            DebugLog.log("\(self.tag) activateServer app=\(app) tis=\(ModeSwitcher.currentID()) mode=\(ModeState.current.rawValue)")
        }
    }

    /// Clients ask for a forced commit mid-composition — Apple Mail's recipient
    /// field does it while its completion runs. There is nothing left to do here:
    /// this IME never marks text, so every syllable the client can see is already
    /// committed and the request is satisfied before it arrives.
    ///
    /// Both bugs this callback used to cause die with it. Committing here ended
    /// the composition, so the next jamo opened a new syllable and the field filled
    /// with loose jamo ('김ㅕㄴ'); ignoring it left the last syllable marked, which
    /// is what kept Mail completing on the prefix alone. Neither state can exist now.
    nonisolated override func commitComposition(_ sender: Any!) {
        let boxed = UncheckedSendableBox(value: sender)
        MainActor.assumeIsolated {
            let app = (self.client(boxed.value)?.bundleIdentifier()) ?? "(nil)"
            DebugLog.log("\(self.tag) commitComposition app=\(app) preedit='\(self.composer.preedit)' "
                         + "already committed, rendered=\(Self.describe(self.rendered ?? self.noRange))")
        }
    }

    nonisolated override func deactivateServer(_ sender: Any!) {
        let boxed = UncheckedSendableBox(value: sender)
        MainActor.assumeIsolated {
            self.gate.reset()
            if let client = self.client(boxed.value) {
                self.flush(client)
            } else {
                _ = self.composer.flush()
                self.rendered = nil
            }
            DebugLog.log("\(self.tag) deactivateServer tis=\(ModeSwitcher.currentID()) mode=\(ModeState.current.rawValue)")
        }
    }

    nonisolated override func menu() -> NSMenu! {
        let boxed: UncheckedSendableBox<NSMenu> = MainActor.assumeIsolated {
            UncheckedSendableBox(value: MenuBuilder.build(mode: ModeState.current))
        }
        return boxed.value
    }
}
