import AppKit
import InputMethodKit

/// IMK always invokes `handle(_:client:)` on the main thread, but the ObjC
/// `sender` parameter isn't `Sendable`. This box lets us carry it across the
/// (statically required, dynamically already-satisfied) hop into the
/// `MainActor.assumeIsolated` closure below.
private nonisolated struct UncheckedSendableBox<Value>: @unchecked Sendable {
    let value: Value
}

@objc(BomiInputController)
final class BomiInputController: IMKInputController {
    nonisolated override init() {
        super.init()
    }

    nonisolated override init(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        super.init(server: server, delegate: delegate, client: inputClient)
    }

    nonisolated override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event, event.type == .keyDown else { return false }
        let boxed = UncheckedSendableBox(value: sender)
        return MainActor.assumeIsolated {
            guard let client = boxed.value as? IMKTextInput else { return false }
            client.insertText("보미", replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
            return true
        }
    }
}
