import AppKit
import BomiCore

enum MenuBuilder {
    /// `tag` values carried by the per-app default items. The input menu is
    /// rendered by a separate process (TextInputMenuAgent) and the item comes back
    /// serialized, so only plist-safe scalars like `tag` survive the round trip —
    /// no `representedObject`, and no submenus (kept flat for the same reason).
    static let tagNone = 1
    static let tagKorean = 2
    static let tagRoman = 3

    static func mode(forTag tag: Int) -> InputMode? {
        switch tag {
        case tagKorean: return .korean
        case tagRoman: return .roman
        default: return nil
        }
    }

    static func build(mode: InputMode, appDefault: InputMode?) -> NSMenu {
        let menu = NSMenu(title: "Bomi")

        let current = NSMenuItem(title: mode == .korean ? "세벌식 최종" : "영어",
                                 action: nil, keyEquivalent: "")
        current.isEnabled = false
        menu.addItem(current)
        menu.addItem(.separator())

        // Per-app default input. Target stays nil: IMK routes the action to the
        // input controller with a {menuItem, client} dictionary as sender.
        for (title, tag, value) in [("이 앱 기본 입력: 한글", tagKorean, InputMode.korean),
                                    ("이 앱 기본 입력: 영어", tagRoman, .roman),
                                    ("이 앱 기본 입력: 없음", tagNone, nil)] as [(String, Int, InputMode?)] {
            let item = NSMenuItem(title: title, action: #selector(BomiInputController.setAppDefault(_:)),
                                  keyEquivalent: "")
            item.tag = tag
            item.state = value == appDefault ? .on : .off
            menu.addItem(item)
        }
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
