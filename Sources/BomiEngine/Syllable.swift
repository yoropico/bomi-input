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
            let code = Int(sBase) + (ci * 21 + ji) * 28 + ki
            if code >= 0, let scalar = UnicodeScalar(UInt32(code)) {
                return String(scalar)
            }
            // Invalid jamo: fall through to the compatibility jamo below.
        }
        var s = ""
        if cho != 0,  let c = UnicodeScalar(SebeolsikFinal.compat(cho))  { s.unicodeScalars.append(c) }
        if jung != 0, let c = UnicodeScalar(SebeolsikFinal.compat(jung)) { s.unicodeScalars.append(c) }
        if jong != 0, let c = UnicodeScalar(SebeolsikFinal.compat(jong)) { s.unicodeScalars.append(c) }
        return s
    }
}
