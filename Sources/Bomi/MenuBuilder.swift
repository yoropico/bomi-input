import AppKit
import BomiCore

enum MenuBuilder {
    static func build(mode: InputMode) -> NSMenu {
        let menu = NSMenu(title: "Bomi")

        let current = NSMenuItem(title: mode == .korean ? "한글 (세벌식 최종)" : "로마자 (English)",
                                 action: nil, keyEquivalent: "")
        current.isEnabled = false
        menu.addItem(current)
        menu.addItem(.separator())

        let toggleInfo = NSMenuItem(title: "한/영 전환 키: 오른쪽 Command", action: nil, keyEquivalent: "")
        toggleInfo.isEnabled = false
        menu.addItem(toggleInfo)

        let about = NSMenuItem(title: "Bomi 정보", action: nil, keyEquivalent: "")
        about.isEnabled = false
        menu.addItem(about)
        return menu
    }
}
