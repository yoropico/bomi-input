import Testing
@testable import BomiEngine

private func type(_ s: String) -> String {
    var c = HangulComposer()
    var out = ""
    for ch in s.unicodeScalars { out += c.inputASCII(ch.value) }
    out += c.flush()
    return out
}

@Test func basicSyllables() {
    #expect(type("kf") == "가")        // ㄱㅏ
    #expect(type("kfs") == "간")       // ㄱㅏㄴ(jong)
    #expect(type("kkf") == "까")       // ㄱ+ㄱ->ㄲ, ㅏ
    #expect(type("krw") == "갤")       // ㄱㅐㄹ(jong)
}

@Test func multipleSyllables() {
    #expect(type("kfsu") == "간ㄷ")    // 간 commits, ㄷ(cho u) lone -> compat ㄷ
    #expect(type("kfhf") == "가나")    // ㄱㅏ | ㄴ(cho h) starts new, ㅏ -> 나
}

@Test func compoundVowelAndJong() {
    #expect(type("kvf") == "과")       // ㄱ + ㅗ(v) + ㅏ(f) -> ㅘ -> 과
    #expect(type("yvwx") == "롥")      // ㄹ ㅗ ㄹ(jong) ㄱ(jong)->ㄺ => 롥
}

@Test func backspaceRevertsCompound() {
    var c = HangulComposer()
    _ = c.inputASCII(0x79) // ㄹ cho
    _ = c.inputASCII(0x76) // ㅗ jung
    _ = c.inputASCII(0x77) // ㄹ jong
    _ = c.inputASCII(0x78) // ㄱ jong -> ㄺ
    #expect(c.preedit == "롥")
    #expect(c.backspace() == true)     // remove ㄱ -> back to ㄹ jong
    #expect(c.preedit == "롤")
    #expect(c.backspace() == true)     // remove ㄹ jong
    #expect(c.preedit == "로")
}

@Test func symbolCommitsThenAppends() {
    // '.' (0x2E) maps to '.' symbol -> commits current then appends '.'
    #expect(type("kf.") == "가.")
}

@Test func dedicatedVsCombinationJongEquivalence() {
    // ㄺ reachable both via dedicated key '@' (0x40) and via combination ㄹ(w)+ㄱ(x).
    // Both paths must produce the same committed syllable through the composer.
    #expect(type("yv@") == type("yvwx"))
    #expect(type("yv@") == "롥")
}

@Test func choPlusChoFormingJongIsRejected() {
    // ㄱ(cho)+ㅅ(cho) has a combination entry -> ㄳ(jong), but it must be rejected
    // during choseong input (allowChoToJong:false wired in inputASCII's .cho branch).
    // Each commits as its own compatibility consonant.
    #expect(type("kn") == "ㄱㅅ")
}

@Test func loneJongAsFirstKey() {
    // jong fills unconditionally even with empty cho; renders as a compat consonant.
    #expect(type("x") == "ㄱ") // 'x' -> ㄱ jongseong
}
