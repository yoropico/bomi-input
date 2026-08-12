import Testing
@testable import BomiEngine

// 모아치기 (chord typing): keys arriving within the chord window may fill empty
// syllable slots out of canonical order. Sebeolsik-final keys are slot-distinct
// (cho/jung/jong are different keys), so the fill is unambiguous.

private func typeTimed(_ keys: [(Character, Double)]) -> String {
    var c = HangulComposer()
    var out = ""
    for (ch, t) in keys { out += c.inputASCII(ch.unicodeScalars.first!.value, at: t) }
    out += c.flush()
    return out
}

@Test func rolledJungBeforeCho() {
    // The real logged case (2026-08-12 08:49, BCT): '지' typed as ㅣ(d) then ㅈ(l)
    // 90ms apart. Legacy committed "ㅣㅈ"; chord assembly must give "지".
    #expect(typeTimed([("d", 0), ("l", 0.09)]) == "지")
}

@Test func hanInEveryArrivalOrder() {
    // '한' = ㅎ(m, cho) ㅏ(f, jung) ㄴ(s, jong) — all 6 arrival orders within
    // the window must assemble the same syllable.
    for perm in [["m","f","s"], ["m","s","f"], ["f","m","s"],
                 ["f","s","m"], ["s","m","f"], ["s","f","m"]] {
        let keys = perm.enumerated().map { (Character($0.element), Double($0.offset) * 0.05) }
        #expect(typeTimed(keys) == "한", "order \(perm)")
    }
}

@Test func outsideWindowKeepsLegacySplit() {
    // Same keys, but slower than the window: deliberate lone-jamo input must
    // keep its old meaning.
    #expect(typeTimed([("d", 0), ("l", 0.5)]) == "ㅣㅈ")
}

@Test func untimedAPIUnchanged() {
    // The no-timestamp entry point never chords.
    var c = HangulComposer()
    var out = ""
    for ch in "dl".unicodeScalars { out += c.inputASCII(ch.value) }
    out += c.flush()
    #expect(out == "ㅣㅈ")
}

@Test func fastSequentialTypingUnaffected() {
    // Canonical-order fast typing hits occupied slots, which never chord-fill:
    // "가나" and "한글" at 50ms per key must come out unchanged.
    #expect(typeTimed([("k", 0), ("f", 0.05), ("h", 0.10), ("f", 0.15)]) == "가나")
    #expect(typeTimed([("m", 0), ("f", 0.05), ("s", 0.10),
                       ("k", 0.15), ("g", 0.20), ("w", 0.25)]) == "한글")
}

@Test func chordFillUpdatesPreedit() {
    // jung arrives first: preedit shows the lone vowel, then the cho fills in
    // and the preedit becomes the assembled syllable.
    var c = HangulComposer()
    _ = c.inputASCII(0x66, at: 0)      // ㅏ
    #expect(c.preedit == "ㅏ")
    _ = c.inputASCII(0x6D, at: 0.08)   // ㅎ fills cho
    #expect(c.preedit == "하")
}

@Test func backspaceAfterChordFill() {
    // Stack keeps arrival order: backspace removes the most recent key (the
    // late-arriving cho), reverting to the lone vowel.
    var c = HangulComposer()
    _ = c.inputASCII(0x66, at: 0)      // ㅏ
    _ = c.inputASCII(0x6D, at: 0.08)   // ㅎ -> 하
    #expect(c.backspace() == true)
    #expect(c.preedit == "ㅏ")
}
