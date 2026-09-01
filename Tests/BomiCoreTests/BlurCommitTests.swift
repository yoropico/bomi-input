import XCTest
@testable import BomiCore

/// Measured client states at `deactivateServer`, right after a `commitComposition`
/// we ignored (durable log, 2026-08/09). See `BlurCommit`.
final class BlurCommitTests: XCTestCase {
    /// Mail subject 16:34:55 / Calendar 20:51:44: the field already holds the
    /// syllable as committed text. Writing it again doubled it.
    func testAppKitFieldAlreadyHoldsTheSyllable() {
        XCTAssertFalse(BlurCommit.mustWrite("내", text: "자금일보 사이트 오픈 안내"))
        XCTAssertFalse(BlurCommit.mustWrite("팅", text: "미팅"))
    }

    /// Mail recipient 16:35:46: still marked, but present — AppKit will keep it.
    func testStillMarkedSyllableIsNotWrittenAgain() {
        XCTAssertFalse(BlurCommit.mustWrite("형", text: "김형"))
    }

    /// Mail recipient 19:53:29: the field dropped the marked syllable — only a
    /// client that shows the syllable gone gets it written.
    func testDroppedSyllableMustBeWritten() {
        XCTAssertTrue(BlurCommit.mustWrite("호", text: "최승"))
    }

    /// Edge / BCT report no text (len=0): the commit request is trusted, no write.
    func testClientWithoutTextIsTrusted() {
        XCTAssertFalse(BlurCommit.mustWrite("성", text: nil))
        XCTAssertFalse(BlurCommit.mustWrite("성", text: ""))
    }

    func testEmptyTailNeverWrites() {
        XCTAssertFalse(BlurCommit.mustWrite("", text: "최승"))
    }
}
