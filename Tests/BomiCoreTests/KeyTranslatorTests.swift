import Testing
@testable import BomiCore

// Regression cover for the US-ANSI keyCode -> ASCII table (previously untested).

@Test func translatesLettersHonoringShift() {
    #expect(KeyTranslator.ascii(keyCode: 0x00, shift: false) == 0x61) // a
    #expect(KeyTranslator.ascii(keyCode: 0x00, shift: true)  == 0x41) // A
    #expect(KeyTranslator.ascii(keyCode: 0x06, shift: false) == 0x7A) // z
}

@Test func returnsNilForNonCharacterKeys() {
    #expect(KeyTranslator.ascii(keyCode: 0x31, shift: false) == nil) // space
    #expect(KeyTranslator.ascii(keyCode: 0x24, shift: false) == nil) // return
    #expect(KeyTranslator.ascii(keyCode: 0x33, shift: false) == nil) // backspace
}
