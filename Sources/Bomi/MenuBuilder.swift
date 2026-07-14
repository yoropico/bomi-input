import AppKit
import BomiCore

enum MenuBuilder {
    static func build(korean: Bool, target: AnyObject) -> NSMenu {
        let menu = NSMenu(title: "Bomi")
        let mode = NSMenuItem(title: korean ? "한글 (Korean)" : "English", action: nil, keyEquivalent: "")
        mode.isEnabled = false
        menu.addItem(mode)
        menu.addItem(.separator())

        let toggleInfo = NSMenuItem(title: "한/영 전환 키: 오른쪽 Command", action: nil, keyEquivalent: "")
        toggleInfo.isEnabled = false
        menu.addItem(toggleInfo)

        let mem = NSMenuItem(title: "앱별 한/영 기억", action: #selector(BomiInputController.togglePerAppMemory(_:)), keyEquivalent: "")
        mem.target = target
        mem.state = Preferences.shared.perAppMemory ? .on : .off
        menu.addItem(mem)

        menu.addItem(.separator())

        let prefs = NSMenuItem(title: "환경설정…", action: nil, keyEquivalent: "")
        prefs.isEnabled = false
        menu.addItem(prefs)

        let about = NSMenuItem(title: "Bomi 정보", action: nil, keyEquivalent: "")
        about.isEnabled = false
        menu.addItem(about)
        return menu
    }
}
