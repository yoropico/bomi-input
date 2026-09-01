import XCTest
@testable import BomiCore

/// Measured client states at `deactivateServer`, right after a `commitComposition`
/// we ignored (durable log, 2026-08/09). See `BlurCommit`.
final class BlurCommitTests: XCTestCase {
    /// Mail subject 16:34:55 / Calendar 20:51:44: the field already turned the
    /// marked syllable into committed text — caret after it, nothing selected.
    func testAppKitFieldAlreadyHoldsTheSyllable() {
        XCTAssertTrue(BlurCommit.clientAlreadyHolds("내", text: "자금일보 사이트 오픈 안내",
                                                    selection: NSRange(location: 14, length: 0)))
        XCTAssertTrue(BlurCommit.clientAlreadyHolds("팅", text: "미팅",
                                                    selection: NSRange(location: 2, length: 0)))
    }

    /// Mail recipient 19:53:29: the field dropped the marked syllable instead.
    func testDroppedSyllableMustStillBeWritten() {
        XCTAssertFalse(BlurCommit.clientAlreadyHolds("호", text: "최승",
                                                     selection: NSRange(location: 2, length: 0)))
    }

    /// Mail recipient 16:35:46: still marked — the syllable sits under a selection,
    /// so the client has not committed anything yet.
    func testStillMarkedSelectionIsNotACommit() {
        XCTAssertFalse(BlurCommit.clientAlreadyHolds("형", text: "김형",
                                                     selection: NSRange(location: 1, length: 1)))
    }

    /// BCT / Edge report no text at all (len=0): never assume, always write.
    func testClientWithoutTextReportsNothing() {
        XCTAssertFalse(BlurCommit.clientAlreadyHolds("성", text: nil,
                                                     selection: NSRange(location: 0, length: 0)))
        XCTAssertFalse(BlurCommit.clientAlreadyHolds("성", text: "",
                                                     selection: NSRange(location: 0, length: 0)))
    }

    func testEmptyTailNeverHolds() {
        XCTAssertFalse(BlurCommit.clientAlreadyHolds("", text: "미팅",
                                                     selection: NSRange(location: 2, length: 0)))
    }
}
