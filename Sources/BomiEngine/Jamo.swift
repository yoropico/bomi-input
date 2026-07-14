import Foundation

public enum JamoSlot: Equatable {
    case cho, jung, jong
}

public enum Jamo {
    public static let choBase: UInt32 = 0x1100, choLast: UInt32 = 0x1112
    public static let jungBase: UInt32 = 0x1161, jungLast: UInt32 = 0x1175
    public static let jongBase: UInt32 = 0x11A8, jongLast: UInt32 = 0x11C2

    public static func isCho(_ u: UInt32) -> Bool { (choBase...choLast).contains(u) }
    public static func isJung(_ u: UInt32) -> Bool { (jungBase...jungLast).contains(u) }
    public static func isJong(_ u: UInt32) -> Bool { (jongBase...jongLast).contains(u) }

    public static func slot(of u: UInt32) -> JamoSlot? {
        if isCho(u) { return .cho }
        if isJung(u) { return .jung }
        if isJong(u) { return .jong }
        return nil
    }

    /// Index into the syllable formula.
    public static func choIndex(_ u: UInt32) -> Int { Int(u - choBase) }        // 0..18
    public static func jungIndex(_ u: UInt32) -> Int { Int(u - jungBase) }      // 0..20
    public static func jongIndex(_ u: UInt32) -> Int { Int(u - jongBase) + 1 }  // 1..27
}
