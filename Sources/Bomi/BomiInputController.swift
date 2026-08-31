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
    /// believe we sent it.
    ///
    /// Mail's recipient field picks its completion candidate from the field, and
    /// the open question behind both known Mail bugs (loose jamo before
    /// `commitComposition` was ignored, wrong contact after) is whether that match
    /// counts the marked text or only the committed prefix. Nothing on our side
    /// can answer that — only the client's own string/selection can.
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
        DebugLog.log("    \(tag) -> setMarkedText '\(s)'")
        client.setMarkedText(s, selectionRange: NSRange(location: s.utf16.count, length: 0),
                             replacementRange: noRange)
        probeClient(client, "after setMarkedText")
    }

    private func commit(_ text: String, _ client: IMKTextInput) {
        guard !text.isEmpty else { return }
        DebugLog.log("    \(tag) -> insertText '\(text)' (commit)")
        client.insertText(text, replacementRange: noRange)
        probeClient(client, "after commit")
    }

    /// Flush any in-progress syllable to the client. Used on blur/commit/mode change.
    ///
    /// Two client families need two opposite flushes, and `markedRange()` is what
    /// tells them apart:
    ///
    /// - Marked range still present (the normal case): commit by replacing it in
    ///   ONE `insertText` — the same path every mid-typing commit takes. Ending
    ///   the composition explicitly first (empty `setMarkedText`, then insert)
    ///   loses the syllable in Chromium clients: measured 2026-08-28 in Edge
    ///   Beta, an arrow/space-driven two-step flush left the caret unmoved and
    ///   the syllable gone (07:24:22/25/28/31), while every one-step mid-typing
    ///   commit in the same field landed fine.
    ///
    /// - Marked range already gone: the client dropped the marked text on its
    ///   own. Measured 2026-08-24 in Mail's recipient field after a
    ///   `commitComposition` we ignored: a passthrough-key flush took '최승호'
    ///   down to '최승' (19:53:29.692/31.617, again at 46.501/47.976) — with no
    ///   range left to replace, the bare `insertText` went nowhere. Ending the
    ///   composition explicitly first is what makes the insert land there, and
    ///   it needs no coordinates — which matters because an explicit
    ///   `replacementRange` means something else entirely to a client that does
    ///   not report its length or caret (BCT writes it at position 0).
    private func flush(_ client: IMKTextInput) {
        let tail = composer.flush()
        guard !tail.isEmpty else { return }
        if client.markedRange().location == NSNotFound {
            DebugLog.log("    \(tag) -> setMarkedText '' (end composition before flush)")
            client.setMarkedText("", selectionRange: NSRange(location: 0, length: 0),
                                 replacementRange: noRange)
            probeClient(client, "after ending composition")
        }
        DebugLog.log("    \(tag) -> insertText '\(tail)' (flush)")
        client.insertText(tail, replacementRange: noRange)
        probeClient(client, "after flush")
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

    private func handleKeyEvent(keyCode: UInt16, flags rawFlags: NSEvent.ModifierFlags, chars: String,
                                timestamp: TimeInterval, client: IMKTextInput) -> Bool {
        // The toggle key is still physically down after its fire: its modifier bit
        // on this keyDown is typing overlap, not a shortcut. Strip it so the app
        // never sees Cmd+<letter>. (See ToggleGate.heldModifier.)
        var flags = rawFlags
        let heldBit = gate.heldModifier(now: ProcessInfo.processInfo.systemUptime).map { NSEvent.ModifierFlags(rawValue: $0) }
        if let heldBit, flags.contains(heldBit) {
            flags.remove(heldBit)
            DebugLog.log("    \(tag) toggle key still held: stripped 0x\(String(heldBit.rawValue, radix: 16))")
        }

        // Modifiers other than Shift: commit and pass through (e.g. Cmd+C).
        if flags.contains(.command) || flags.contains(.control) || flags.contains(.option) {
            flush(client)
            return false
        }

        // Secure Event Input (sudo / ssh / passwd prompt): macOS only swaps to an
        // ASCII keyboard *layout* while it is on, and with ABC not enabled there is
        // none, so it stays on us and the prompt would receive Hangul. Type the
        // password as ASCII without touching the mode -- no source switch, so
        // BCT's per-pane input-source pin and per-app memory are never disturbed.
        if IsSecureEventInputEnabled() {
            flush(client)
            return false
        }

        // Roman mode: we stay active (so Right-Command still reaches us) but type nothing.
        if ModeState.current != .korean {
            flush(client)
            // Unless we stripped the toggle's bit: passing the event through would
            // hand the app the original Cmd+key, so type the character ourselves.
            if flags != rawFlags, !chars.isEmpty {
                commit(chars, client)
                return true
            }
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
            return self.handleKeyEvent(keyCode: keyCode, flags: flags, chars: chars, timestamp: timestamp, client: client)
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
            let client = self.client(boxed.value)
            let app = client?.bundleIdentifier() ?? "(nil)"
            DebugLog.log("\(self.tag) activateServer app=\(app) tis=\(ModeSwitcher.currentID()) mode=\(ModeState.current.rawValue)")
            if let client, let wanted = Preferences.shared.defaultMode(forApp: client.bundleIdentifier()) {
                // Not immediately: macOS restores the app's remembered source right
                // after activateServer and re-asserts it once more ~16ms later
                // (on-device: setValue korean +0ms, our roman +7ms, korean again
                // +16ms, then the switch never lands). Wait that dance out, then
                // check TIS and only switch if macOS left us on the wrong side.
                let boxedClient = UncheckedSendableBox(value: client)
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(Self.appDefaultDelayMs)) {
                    MainActor.assumeIsolated {
                        if let active = ModeSwitcher.currentMode() { ModeState.current = active }
                        self.apply(wanted, client: boxedClient.value)
                    }
                }
            }
        }
    }

    // ponytail: measured 16ms re-assert on this machine; raise if a slower box
    // still shows "did NOT land" after an app-default APPLY.
    private static let appDefaultDelayMs = 150

    /// Force `mode` for the focused app. Same optimistic-cache + IMK `selectMode`
    /// path as the toggle (see `handleToggleFlags` for why not TIS directly).
    private func apply(_ mode: InputMode, client: IMKTextInput) {
        guard mode != ModeState.current else { return }
        ModeState.current = mode
        let boxedClient = UncheckedSendableBox(value: client)
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                DebugLog.log("  \(self.tag) APPLY app-default=\(mode.rawValue) via=imk-selectMode")
                ModeSwitcher.selectViaIMK(mode) { id in boxedClient.value.selectMode(id) }
            }
        }
    }

    @objc nonisolated func openPreferences(_ sender: Any!) {
        MainActor.assumeIsolated {
            DebugLog.log("\(self.tag) openPreferences")
            PreferencesWindow.shared.show()
        }
    }

    /// Menu action for "이 앱의 기본 입력". IMK invokes it with a dictionary sender:
    /// `kIMKCommandMenuItemName` → the NSMenuItem, `kIMKCommandClientName` → the client.
    @objc nonisolated func setAppDefault(_ sender: Any!) {
        let boxed = UncheckedSendableBox(value: sender)
        MainActor.assumeIsolated {
            let dict = boxed.value as? [String: Any]
            let item = dict?[kIMKCommandMenuItemName] as? NSMenuItem
            let client = (dict?[kIMKCommandClientName] as? IMKTextInput) ?? self.client(nil)
            DebugLog.log("\(self.tag) setAppDefault sender=\(type(of: boxed.value as Any)) "
                         + "item=\(item?.title ?? "(nil)") tag=\(item?.tag ?? -1) client=\(client == nil ? "nil" : "ok")")
            guard let bundleID = client?.bundleIdentifier() else { return }
            let mode = MenuBuilder.mode(forTag: item?.tag ?? MenuBuilder.tagNone)
            Preferences.shared.setDefaultMode(mode, forApp: bundleID)
            DebugLog.log("\(self.tag) setAppDefault app=\(bundleID) mode=\(mode?.rawValue ?? "(none)")")
            if let mode, let client { self.apply(mode, client: client) }
        }
    }

    /// A client can ask for a forced commit at any moment, including mid-syllable.
    /// Apple Mail's recipient field does exactly that while its completion runs:
    /// measured on-device, ~150ms after a keystroke it asks for a commit with the
    /// syllable still half-built (`preedit='혀'`, `preedit='ㄹ'`). Honouring it
    /// commits a partial syllable, so the following jamo can no longer join it and
    /// the field fills with loose jamo ('김ㅕㄴ') — which then matches no contact and
    /// takes the suggestion list down with it. Apple's own 2-Set Korean does not
    /// break here, so it does not commit on this request either.
    ///
    /// Ignoring the request costs nothing, because every real end of composition
    /// still flushes through another path: `deactivateServer` (focus/app change),
    /// `setValue` (language change), and the modifier/passthrough branches of
    /// `handleKeyEvent`.
    ///
    /// Ignoring it is NOT free after all — reported 2026-08-24: the field now reads
    /// correctly but Mail selects an unrelated contact. This is the moment Mail
    /// syncs its completion with us, so the probe below records what the client
    /// holds right here; that is what decides whether the match saw the marked
    /// syllable or only the committed prefix.
    nonisolated override func commitComposition(_ sender: Any!) {
        let boxed = UncheckedSendableBox(value: sender)
        MainActor.assumeIsolated {
            let resolved = self.client(boxed.value)
            let app = resolved?.bundleIdentifier() ?? "(nil)"
            DebugLog.log("\(self.tag) commitComposition app=\(app) preedit='\(self.composer.preedit)' IGNORED")
            if let resolved { self.probeClient(resolved, "at commitComposition") }
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
                if !tail.isEmpty {
                    DebugLog.log("\(self.tag) deactivateServer LOST '\(tail)': no IMKTextInput client")
                }
            }
            DebugLog.log("\(self.tag) deactivateServer tis=\(ModeSwitcher.currentID()) mode=\(ModeState.current.rawValue)")
        }
    }

    nonisolated override func menu() -> NSMenu! {
        let boxed: UncheckedSendableBox<NSMenu> = MainActor.assumeIsolated {
            let app = self.client(nil)?.bundleIdentifier()
            let appDefault = Preferences.shared.defaultMode(forApp: app)
            DebugLog.log("\(self.tag) menu() app=\(app ?? "(nil)") appDefault=\(appDefault?.rawValue ?? "(none)")")
            return UncheckedSendableBox(value: MenuBuilder.build(mode: ModeState.current, appDefault: appDefault))
        }
        return boxed.value
    }
}
