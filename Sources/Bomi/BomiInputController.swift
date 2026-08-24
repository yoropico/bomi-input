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

    /// Text already pushed into the client by a forced commit whose syllable we
    /// are still composing, in the client's own coordinates.
    ///
    /// This is what lets a commit request be honoured without ending the
    /// composition: the text is in the client (so the client's completion sees
    /// the full string) while the composer keeps the syllable open, and the next
    /// composition update replaces this range instead of appending after it.
    /// Non-nil only between a forced commit and the next update; every other app
    /// never sets it and keeps exactly today's behaviour.
    private var forcedCommit: NSRange?

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

    /// The range the next write to the client must replace, consumed once.
    /// `noRange` means "wherever the client's own marked range / caret is",
    /// which is the normal path for every app that never forces a commit.
    private func takeReplacementRange() -> NSRange {
        defer { forcedCommit = nil }
        return forcedCommit ?? noRange
    }

    /// Probe: read back what the CLIENT actually holds, rather than what we
    /// believe we sent it. This is how the Mail bug was pinned down — our own log
    /// records only what we send, so the divergence between the two sides was
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

    private func showPreedit(_ client: IMKTextInput) {
        let s = composer.preedit
        let replace = takeReplacementRange()
        DebugLog.log("    \(tag) -> setMarkedText '\(s)' replacing=\(Self.describe(replace))")
        client.setMarkedText(s, selectionRange: NSRange(location: s.utf16.count, length: 0),
                             replacementRange: replace)
        probeClient(client, "after setMarkedText")
    }

    private func commit(_ text: String, _ client: IMKTextInput) {
        guard !text.isEmpty else { return }
        let replace = takeReplacementRange()
        DebugLog.log("    \(tag) -> insertText '\(text)' (commit) replacing=\(Self.describe(replace))")
        client.insertText(text, replacementRange: replace)
        probeClient(client, "after commit")
    }

    /// Flush any in-progress syllable to the client. Used on blur/commit/mode change.
    private func flush(_ client: IMKTextInput) {
        let tail = composer.flush()
        let replace = takeReplacementRange()
        if !tail.isEmpty {
            DebugLog.log("    \(tag) -> insertText '\(tail)' (flush) replacing=\(Self.describe(replace))")
            client.insertText(tail, replacementRange: replace)
            probeClient(client, "after flush")
        }
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
        let boxed = UncheckedSendableBox(value: sender)
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
                    if let client = self.client(boxed.value) {
                        self.flush(client)
                    } else {
                        _ = self.composer.flush()
                        self.forcedCommit = nil
                    }
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
            // A range captured against the previous focus means nothing here.
            self.forcedCommit = nil
            let app = (self.client(boxed.value)?.bundleIdentifier()) ?? "(nil)"
            DebugLog.log("\(self.tag) activateServer app=\(app) tis=\(ModeSwitcher.currentID()) mode=\(ModeState.current.rawValue)")
        }
    }

    /// A client can ask for a forced commit at any moment, including mid-syllable.
    /// Apple Mail's recipient field does exactly that while its completion runs:
    /// measured on-device, ~30-150ms after a keystroke it asks for a commit with
    /// the syllable still half-built.
    ///
    /// **Why it must be honoured.** The client-side probe of 2026-08-24 settles
    /// what the request is for. Typing 김형: the field really does read '김형',
    /// with '형' still marked (`len=2 text='김형' marked=1+1`), so Mail can see the
    /// whole string. What Mail acts on is narrower — the last text it received as
    /// *committed*, which was '김' alone. It asks here to have the rest committed,
    /// and refusing froze its completion on '김', which is why the suggestion read
    /// 김상태 while the field read 김형.
    ///
    /// **Why it cannot simply commit.** Committing used to end the composition
    /// too, so the next jamo started a new syllable and the field filled with
    /// loose jamo ('김ㅕㄴ') — matching no contact at all. That was the same bug
    /// from the other side: the client's text and our composer had to agree, and
    /// only one of them could be right at a time.
    ///
    /// So: push the syllable out, remember where it landed (the marked range is
    /// still valid here even though `selectedRange` reads as none mid-completion),
    /// and leave the composer composing. The next update replaces that range
    /// rather than appending after it, so the same syllable can keep growing.
    nonisolated override func commitComposition(_ sender: Any!) {
        let boxed = UncheckedSendableBox(value: sender)
        MainActor.assumeIsolated {
            guard let client = self.client(boxed.value) else { return }
            let app = client.bundleIdentifier() ?? "(nil)"
            let s = self.composer.preedit
            guard !s.isEmpty else {
                DebugLog.log("\(self.tag) commitComposition app=\(app) preedit='' nothing to commit")
                return
            }
            let mark = client.markedRange()
            client.insertText(s, replacementRange: self.forcedCommit ?? self.noRange)
            self.forcedCommit = mark.location == NSNotFound
                ? nil
                : NSRange(location: mark.location, length: s.utf16.count)
            DebugLog.log("\(self.tag) commitComposition app=\(app) preedit='\(s)' "
                         + "committed, still composing at \(Self.describe(self.forcedCommit ?? self.noRange))")
            self.probeClient(client, "after forced commit")
        }
    }

    nonisolated override func deactivateServer(_ sender: Any!) {
        let boxed = UncheckedSendableBox(value: sender)
        MainActor.assumeIsolated {
            self.gate.reset()
            if let client = self.client(boxed.value) {
                self.flush(client)
            } else {
                let tail = self.composer.flush()
                self.forcedCommit = nil
                if !tail.isEmpty {
                    DebugLog.log("\(self.tag) deactivateServer LOST '\(tail)': no IMKTextInput client")
                }
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
