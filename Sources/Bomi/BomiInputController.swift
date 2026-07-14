import AppKit
import InputMethodKit
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
    private let language = LanguageMode()
    private var korean = false
    private var appID: String?
    private var gate = ToggleGate()

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

    /// Flush any in-progress syllable to the client. Used on blur/commit.
    private func flush(_ client: IMKTextInput) {
        let tail = composer.flush()
        if !tail.isEmpty { client.insertText(tail, replacementRange: noRange) }
    }

    private func handleToggleFlags(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags, client: IMKTextInput) {
        let isToggleKey = keyCode == Preferences.shared.toggleKeyCode
        let toggleKeyDown = modifierFlags.contains(.command)
        let otherModifiers = !modifierFlags.intersection([.shift, .control, .option]).isEmpty
        if gate.flagsChanged(isToggleKey: isToggleKey, toggleKeyDown: toggleKeyDown,
                             otherModifiersPresent: otherModifiers) {
            flush(client)
            language.toggle(forApp: appID)
            korean = language.isKorean(forApp: appID)
        }
    }

    private func handleKeyEvent(keyCode: UInt16, flags: NSEvent.ModifierFlags, client: IMKTextInput) -> Bool {
        // Any non-modifier keyDown means Right-Command (if held) is part of a chord,
        // not a bare tap — disarm so releasing it does NOT fire the Han/Eng toggle.
        // (e.g. Right-Command + C to copy must not silently flip the input language.)
        gate.chordInterrupt()

        // Modifiers other than Shift: commit and pass through (e.g. Cmd+C).
        if flags.contains(.command) || flags.contains(.control) || flags.contains(.option) {
            flush(client)
            return false
        }

        if !korean {
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

        // Han/Eng toggle: bare Right-Command tap (down with no chord).
        if event.type == .flagsChanged {
            let keyCode = event.keyCode
            let modifierFlags = event.modifierFlags
            MainActor.assumeIsolated {
                guard let client = boxed.value as? IMKTextInput else { return }
                self.handleToggleFlags(keyCode: keyCode, modifierFlags: modifierFlags, client: client)
            }
            return false
        }

        guard event.type == .keyDown else { return false }
        let keyCode = event.keyCode
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return MainActor.assumeIsolated {
            guard let client = boxed.value as? IMKTextInput else { return false }
            return self.handleKeyEvent(keyCode: keyCode, flags: flags, client: client)
        }
    }

    nonisolated override func recognizedEvents(_ sender: Any!) -> Int {
        Int(NSEvent.EventTypeMask.keyDown.rawValue | NSEvent.EventTypeMask.flagsChanged.rawValue)
    }

    nonisolated override func activateServer(_ sender: Any!) {
        let boxed = UncheckedSendableBox(value: sender)
        MainActor.assumeIsolated {
            self.appID = (boxed.value as? IMKTextInput)?.bundleIdentifier()
            self.korean = self.language.isKorean(forApp: self.appID)
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
            if let client = self.client(boxed.value) { self.flush(client) } else { _ = self.composer.flush() }
        }
    }

    nonisolated override func menu() -> NSMenu! {
        let boxed: UncheckedSendableBox<NSMenu> = MainActor.assumeIsolated {
            UncheckedSendableBox(value: MenuBuilder.build(korean: self.korean, target: self))
        }
        return boxed.value
    }

    @objc func togglePerAppMemory(_ sender: NSMenuItem) {
        let d = UserDefaults.standard
        d.set(!Preferences.shared.perAppMemory, forKey: "perAppMemory")
    }
}
