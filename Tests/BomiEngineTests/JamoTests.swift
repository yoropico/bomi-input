import Testing
@testable import BomiEngine

@Test func classifiesSlots() {
    #expect(Jamo.slot(of: 0x1100) == .cho)   // ㄱ choseong
    #expect(Jamo.slot(of: 0x1112) == .cho)   // ㅎ choseong (last)
    #expect(Jamo.slot(of: 0x1161) == .jung)  // ㅏ jungseong
    #expect(Jamo.slot(of: 0x1175) == .jung)  // ㅣ jungseong (last)
    #expect(Jamo.slot(of: 0x11A8) == .jong)  // ㄱ jongseong
    #expect(Jamo.slot(of: 0x11C2) == .jong)  // ㅎ jongseong (last)
    #expect(Jamo.slot(of: 0x0041) == nil)    // 'A'
    #expect(Jamo.slot(of: 0x00B7) == nil)    // middot symbol
}
