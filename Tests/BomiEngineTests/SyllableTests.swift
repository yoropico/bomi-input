import Testing
@testable import BomiEngine

@Test func sebeolsikLookup() {
    #expect(SebeolsikFinal.jamo(forASCII: 0x6B) == 0x1100) // 'k' -> ㄱ cho
    #expect(SebeolsikFinal.jamo(forASCII: 0x66) == 0x1161) // 'f' -> ㅏ jung
    #expect(SebeolsikFinal.jamo(forASCII: 0x73) == 0x11AB) // 's' -> ㄴ jong
    #expect(SebeolsikFinal.jamo(forASCII: 0x21) == 0x11A9) // '!' -> ㄲ jong
    #expect(SebeolsikFinal.jamo(forASCII: 0x2F) == 0x1169) // '/' -> ㅗ jung
    #expect(SebeolsikFinal.jamo(forASCII: 0x48) == 0x0030) // 'H' -> '0' (digit passthrough)
    #expect(SebeolsikFinal.jamo(forASCII: 0x20) == nil)    // space not in map
}

@Test func compatMapping() {
    #expect(SebeolsikFinal.compat(0x1100) == 0x3131) // ㄱ cho -> compat ㄱ
    #expect(SebeolsikFinal.compat(0x1161) == 0x314F) // ㅏ jung -> compat ㅏ
    #expect(SebeolsikFinal.compat(0x11AF) == 0x3139) // ㄹ jong -> compat ㄹ
}

@Test func rendersSyllables() {
    #expect(Syllable.render(cho: 0x1100, jung: 0x1161, jong: 0)      == "가")
    #expect(Syllable.render(cho: 0x1100, jung: 0x1161, jong: 0x11AB) == "간")
    #expect(Syllable.render(cho: 0x1101, jung: 0x1161, jong: 0)      == "까") // ㄲ
    #expect(Syllable.render(cho: 0x1100, jung: 0x1162, jong: 0x11AF) == "갤") // ㄱ+ㅐ+ㄹ
}

@Test func rendersIncompleteAsCompat() {
    #expect(Syllable.render(cho: 0x1100, jung: 0, jong: 0) == "ㄱ") // lone cho -> compat
    #expect(Syllable.render(cho: 0, jung: 0x1161, jong: 0) == "ㅏ") // lone jung -> compat
    #expect(Syllable.render(cho: 0, jung: 0, jong: 0x11BA) == "ㅅ") // lone jong -> compat
}
