import Testing
@testable import BomiCore

@Test func otherFlipsBetweenKoreanAndRoman() {
    #expect(InputMode.korean.other == .roman)
    #expect(InputMode.roman.other == .korean)
}

@Test func modeIdsMatchInfoPlist() {
    #expect(InputMode.korean.rawValue == "com.bomi.inputmethod.bomi.korean")
    #expect(InputMode.roman.rawValue == "com.bomi.inputmethod.bomi.roman")
}

@Test func fromIdParsesKnownIdsAndDefaultsToKorean() {
    #expect(InputMode.from(id: "com.bomi.inputmethod.bomi.roman") == .roman)
    #expect(InputMode.from(id: "com.bomi.inputmethod.bomi.korean") == .korean)
    #expect(InputMode.from(id: nil) == .korean)                        // no mode reported yet
    #expect(InputMode.from(id: "com.apple.keylayout.ABC") == .korean)  // unknown id
}
