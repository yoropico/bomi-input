import Foundation

final class Preferences {
    static let shared = Preferences()
    private let d = UserDefaults.standard
    private init() {
        d.register(defaults: ["toggleKeyCode": 0x36, "perAppMemory": true])
    }
    var toggleKeyCode: UInt16 { UInt16(d.integer(forKey: "toggleKeyCode")) }
    var perAppMemory: Bool { d.bool(forKey: "perAppMemory") }
}
