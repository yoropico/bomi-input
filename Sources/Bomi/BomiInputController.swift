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

    /// The active input source IS the Han/Eng state — macOS owns it. IMK reports
    /// it via `setValue(_:forTag:client:)` with `kTextServiceInputModePropertyTag`.
    private var mode: InputMode = .korean

    /// Keys that end/interrupt composition and are handled by the app itself:
    /// Enter(0x24), Return(0x4C), Tab(0x30), Escape(0x35), arrows(0x7B-0x7E), space(0x31).
    private static let passthroughKeys: Set<UInt16> = [0x24, 0x4C, 0x30, 0x35, 0x7B, 0x7C, 0x7D, 0x7E, 0x31]

    nonisolated override init() {
        super.init()
    }

    nonisolated override init(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        super.init(server: server, delegate: delegate, client: inputClient)
    }

    private func client(_ sender: Any!) -> IMKTextInput? { sender as? IMKTextInput }
    private let noRange = NSRange(location: NSNotFound, length: NSNotFound)

    private func showPreedit(_ client: IMKTextInput) {
        let s = composer.preedit
        client.setMarkedText(s, selectionRange: NSRange(location: s.utf16.count, length: 0),
                             replacementRange: noRange)
    }

    private func commit(_ text: String, _ client: IMKTextInput) {
        guard !text.isEmpty else { return }
        client.insertText(text, replacementRange: noRange)
    }

    /// Flush any in-progress syllable to the client. Used on blur/commit/mode change.
    private func flush(_ client: IMKTextInput) {
        let tail = composer.flush()
        if !tail.isEmpty { client.insertText(tail, replacementRange: noRange) }
    }

    /// Han/Eng toggle. Fires on the PRESS of Right-Command — not the release,
    /// because switching the input source makes the key-up land elsewhere.
    /// Returns whether the event was consumed.
    private func handleToggleFlags(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags,
                                   client: IMKTextInput) -> Bool {
        let outcome = gate.flagsChanged(keyCode: keyCode,
                                        flagsRaw: modifierFlags.rawValue,
                                        toggleKeyCode: Preferences.shared.toggleKeyCode,
                                        now: ProcessInfo.processInfo.systemUptime)
        switch outcome {
        case .notPress:
            return false
        case .suppressed:
            // A duplicate press (the source switch / a Chromium app emits two).
            // Consume it — toggling again would flip straight back.
            return true
        case .fire:
            // Commit what's in flight, then let macOS do the switch. `mode` is not
            // set here — IMK reports the new mode via setValue(_:forTag:client:).
            flush(client)
            ModeSwitcher.select(mode.other) { id in client.selectMode(id) }
            return true
        }
    }

    private func handleKeyEvent(keyCode: UInt16, flags: NSEvent.ModifierFlags, client: IMKTextInput) -> Bool {
        // Modifiers other than Shift: commit and pass through (e.g. Cmd+C).
        if flags.contains(.command) || flags.contains(.control) || flags.contains(.option) {
            flush(client)
            return false
        }

        // Roman mode: we stay active (so Right-Command still reaches us) but type nothing.
        if mode != .korean {
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

        let committed = composer.inputASCII(ascii)
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
                guard let client = boxed.value as? IMKTextInput else { return false }
                return self.handleToggleFlags(keyCode: keyCode, modifierFlags: modifierFlags, client: client)
            }
        }

        guard event.type == .keyDown else { return false }
        let keyCode = event.keyCode
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return MainActor.assumeIsolated {
            guard let client = boxed.value as? IMKTextInput else { return false }
            return self.handleKeyEvent(keyCode: keyCode, flags: flags, client: client)
        }
    }

    /// IMK tells us which of our modes is active here. This is the ONLY place
    /// `mode` changes.
    nonisolated override func setValue(_ value: Any!, forTag tag: Int, client sender: Any!) {
        let boxed = UncheckedSendableBox(value: sender)
        let boxedValue = UncheckedSendableBox(value: value)
        if tag == kTextServiceInputModePropertyTag {
            MainActor.assumeIsolated {
                let newMode = InputMode.from(id: boxedValue.value as? String)
                if newMode != self.mode {
                    self.mode = newMode
                    // A mode change means the key-up of the toggle key went elsewhere.
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

    nonisolated override func recognizedEvents(_ sender: Any!) -> Int {
        Int(NSEvent.EventTypeMask.keyDown.rawValue | NSEvent.EventTypeMask.flagsChanged.rawValue)
    }

    nonisolated override func activateServer(_ sender: Any!) {
        MainActor.assumeIsolated {
            // Clear accumulated modifier state: a key-up delivered to another
            // controller must not wedge the next press.
            self.gate.reset()
            // macOS decides which mode activates; it reports it via setValue.
            _ = self.composer.flush()
        }
    }

    nonisolated override func commitComposition(_ sender: Any!) {
        let boxed = UncheckedSendableBox(value: sender)
        MainActor.assumeIsolated {
            if let client = self.client(boxed.value) { self.flush(client) } else { _ = self.composer.flush() }
        }
    }

    nonisolated override func deactivateServer(_ sender: Any!) {
        let boxed = UncheckedSendableBox(value: sender)
        MainActor.assumeIsolated {
            self.gate.reset()
            if let client = self.client(boxed.value) { self.flush(client) } else { _ = self.composer.flush() }
        }
    }

    nonisolated override func menu() -> NSMenu! {
        let boxed: UncheckedSendableBox<NSMenu> = MainActor.assumeIsolated {
            UncheckedSendableBox(value: MenuBuilder.build(mode: self.mode))
        }
        return boxed.value
    }
}
