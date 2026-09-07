import Testing
@testable import BomiCore

// A key that overlapped the Han/Eng toggle has its Cmd bit stripped; what the
// controller then does with it must never be "pass the original event through"
// (that is the Cmd+key shortcut leak), and in roman mode must not be a bare
// one-character insertText either (Chromium then still fires the accelerator).

@Test func romanLetterIsMarkedThenCommitted() {
    #expect(HeldKeyPolicy.action(korean: false, composable: true, chars: "a") == .markThenCommit("a"))
}

@Test func koreanLetterGoesToTheComposer() {
    #expect(HeldKeyPolicy.action(korean: true, composable: true, chars: "a") == .compose)
}

@Test func spaceIsTypedInEitherMode() {
    #expect(HeldKeyPolicy.action(korean: true, composable: false, chars: " ") == .markThenCommit(" "))
    #expect(HeldKeyPolicy.action(korean: false, composable: false, chars: " ") == .markThenCommit(" "))
}

@Test func nonPrintableKeysAreSwallowed() {
    #expect(HeldKeyPolicy.action(korean: false, composable: false, chars: "\r") == .swallow)      // return
    #expect(HeldKeyPolicy.action(korean: true, composable: false, chars: "\u{7F}") == .swallow)   // backspace
    #expect(HeldKeyPolicy.action(korean: false, composable: false, chars: "\u{F702}") == .swallow) // left arrow
    #expect(HeldKeyPolicy.action(korean: false, composable: false, chars: "") == .swallow)
}
