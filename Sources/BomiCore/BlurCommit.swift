import Foundation

/// Blur-time question: has the client already committed our pending syllable by
/// itself, so that writing it would double it?
///
/// AppKit text fields ask for a commit (`commitComposition`) as they lose focus.
/// We ignore that request (Mail's recipient field sends the same request
/// mid-syllable), and AppKit then finalises the marked text on its own: measured
/// in Mail's subject field and Calendar, the field already holds the syllable as
/// committed text — caret right after it, nothing selected — when
/// `deactivateServer` arrives 1–15 ms later, and our flush appended it again
/// ('안내내', '미팅팅', '건건'; six cases, both flush variants).
///
/// Only a client that REPORTS its text can be judged. Terminals and Chromium
/// answer len=0 and are always written to, and BCT's terminal in particular
/// discards marked text on `unmarkText`, so skipping the write there would lose
/// the syllable.
public enum BlurCommit {
    public static func clientAlreadyHolds(_ tail: String, text: String?, selection: NSRange) -> Bool {
        guard !tail.isEmpty, let text, !text.isEmpty, text.hasSuffix(tail) else { return false }
        // A caret at the very end, no selection. Mail keeps a still-marked
        // syllable under a selection (sel=1+1), which must not count.
        return selection.length == 0 && selection.location == text.utf16.count
    }
}
