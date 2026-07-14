import Testing
@testable import BomiEngine

@Test func combinesJamo() {
    #expect(Combination.combine(0x1100, 0x1100) == 0x1101)  // ㄱ+ㄱ -> ㄲ (cho)
    #expect(Combination.combine(0x1169, 0x1161) == 0x116A)  // ㅗ+ㅏ -> ㅘ
    #expect(Combination.combine(0x11AF, 0x11A8) == 0x11B0)  // ㄹ+ㄱ -> ㄺ (jong)
    #expect(Combination.combine(0x11BA, 0x11BA) == 0x11BB)  // ㅅ+ㅅ -> ㅆ (jong)
    #expect(Combination.combine(0x1100, 0x1102) == 0)       // ㄱ+ㄴ -> none
}

@Test func rejectsChoToJongWhenDisallowed() {
    // ㄱ(cho)+ㅅ(cho) has a table entry -> ㄳ(jong); must be rejected during choseong input.
    #expect(Combination.combine(0x1100, 0x1109, allowChoToJong: false) == 0)
    #expect(Combination.combine(0x1100, 0x1109, allowChoToJong: true) == 0x11AA)
}
