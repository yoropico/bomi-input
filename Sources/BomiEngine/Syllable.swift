import Foundation

public enum Syllable {
    static let sBase: UInt32 = 0xAC00

    /// Render the buffer. 0 means an empty slot. cho+jung present -> precomposed syllable;
    /// otherwise fall back to Hangul Compatibility Jamo for whichever slots are filled.
    public static func render(cho: UInt32, jung: UInt32, jong: UInt32) -> String {
        if cho != 0, jung != 0 {
            let ci = Jamo.choIndex(cho)
            let ji = Jamo.jungIndex(jung)
            let ki = jong == 0 ? 0 : Jamo.jongIndex(jong)
            let code = sBase + UInt32((ci * 21 + ji) * 28 + ki)
            return String(UnicodeScalar(code)!)
        }
        var s = ""
        if cho != 0  { s.unicodeScalars.append(UnicodeScalar(SebeolsikFinal.compat(cho))!) }
        if jung != 0 { s.unicodeScalars.append(UnicodeScalar(SebeolsikFinal.compat(jung))!) }
        if jong != 0 { s.unicodeScalars.append(UnicodeScalar(SebeolsikFinal.compat(jong))!) }
        return s
    }
}
