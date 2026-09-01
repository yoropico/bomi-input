import Foundation

/// After a commit request we ignored (`commitComposition`), the client has
/// almost always finalised the marked syllable by itself:
///
/// - AppKit fields unmark it and keep it (Mail subject, Calendar: '건건',
///   '미팅팅' when we wrote it again at blur).
/// - Chromium confirms it in Blink on a mouse click or blur, then discards
///   the marked text — that discard is what reaches us as the commit request.
///   Edge reports no text at all, so nothing can be read back there.
/// - BCT's terminal force-writes it to the PTY before asking.
///
/// The one client that keeps composing after such a request is Mail's
/// recipient field, and it has been measured to DROP the syllable later. So at
/// blur the write is skipped unless a client that reports its text proves the
/// syllable is gone.
public enum BlurCommit {
    /// Should the blur flush still write `tail`? Only when the client reports
    /// text and that text no longer ends with the syllable.
    public static func mustWrite(_ tail: String, text: String?) -> Bool {
        guard !tail.isEmpty, let text, !text.isEmpty else { return false }
        return !text.hasSuffix(tail)
    }
}
