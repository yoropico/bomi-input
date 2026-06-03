//
//  GureumAppDelegate.swift
//  Gureum
//
//  Created by 혜원 on 2018. 8. 27..
//  Copyright © 2018 youknowone.org. All rights reserved.
//

import Carbon
import Cocoa
import Foundation
import GureumCore
import Hangul
import UserNotifications

class NotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let appDefault = NotificationCenterDelegate()

    // 입력기는 백그라운드(Agent) 프로세스이므로 실행 중에도 알림을 노출한다.
    func userNotificationCenter(_: UNUserNotificationCenter,
                                willPresent _: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void)
    {
        completionHandler([.banner, .list])
    }

    func userNotificationCenter(_: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void)
    {
        defer { completionHandler() }
        let userInfo = response.notification.request.content.userInfo
        guard let download = userInfo["url"] as? String else {
            return
        }
        switch response.actionIdentifier {
        case gureumUpdateNotificationActionIdentifier, UNNotificationDefaultActionIdentifier:
            let version = userInfo["version"] as? String ?? ""
            let pageURL = userInfo["pageURL"] as? String
            let info = UpdateManager.VersionInfo(
                update: UpdateManager.UpdateInfo(version: version, description: "", url: download),
                experimental: false,
                pageURL: pageURL
            )
            Updater.shared.performUpdate(info: info) { _ in }
        default:
            break
        }
    }
}

class GureumAppDelegate: NSObject, NSApplicationDelegate, GureumApplicationDelegate {
    @IBOutlet var menu: NSMenu!

    let configuration = Configuration.shared
    var statusController: CloudStatusItemController?

    func applicationDidFinishLaunching(_: Notification) {
        let center = UNUserNotificationCenter.current()
        center.delegate = NotificationCenterDelegate.appDefault

        let updateAction = UNNotificationAction(
            identifier: gureumUpdateNotificationActionIdentifier,
            title: "업데이트",
            options: [.foreground]
        )
        let updateCategory = UNNotificationCategory(
            identifier: gureumUpdateNotificationCategoryIdentifier,
            actions: [updateAction],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([updateCategory])
        center.requestAuthorization(options: [.alert]) { _, _ in }

        #if DEBUG
            let content = UNMutableNotificationContent()
            content.title = "디버그 빌드 알림"
            content.body = "이 버전은 디버그 빌드입니다. 키 입력이 로그로 남을 수 있어 안전하지 않습니다."
            center.add(
                UNNotificationRequest(identifier: "Gureum.debug", content: content, trigger: nil),
                withCompletionHandler: nil
            )
        #endif

        #if DEBUG
            preferencesWindow.showWindow(nil)
        #endif

        UpdateManager.shared.notifyUpdateIfNeeded()

        // 입력 모니터링 권한 요청
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)

        // IMKServer를 띄워야만 입력기가 동작한다
        _ = InputMethodServer.shared

        // OneDrive 식 가로 구름 인디케이터(상태바). 입력 핫패스는 건드리지 않고
        // 선택 입력 소스 변경 알림으로만 갱신한다.
        statusController = CloudStatusItemController()

        watcher.reloadConfiguration()
    }
}

/// 현재 선택된 키보드 입력 소스의 (id, 주 언어)를 읽는다.
private func currentInputSourceInfo() -> (id: String, language: String?)? {
    guard let src = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
    func stringProp(_ key: CFString) -> String? {
        guard let ptr = TISGetInputSourceProperty(src, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }
    guard let id = stringProp(kTISPropertyInputSourceID) else { return nil }
    var language: String?
    if let ptr = TISGetInputSourceProperty(src, kTISPropertyInputSourceLanguages) {
        let arr = Unmanaged<CFArray>.fromOpaque(ptr).takeUnretainedValue() as? [String]
        language = arr?.first
    }
    return (id, language)
}

/// 메뉴 막대에 OneDrive 식 가로 구름을 띄우는 상태바 아이템. 시스템 입력 소스 메뉴 아이콘과 달리
/// 상태바 슬롯은 가로 폭이 유연해 가로 구름이 왜곡되지 않는다. 한국어=채움, 영문=윤곽.
final class CloudStatusItemController: NSObject {
    enum CloudState { case korean, english, hidden }

    /// 순수 함수(단위 검증 대상): 입력 소스 → 보여줄 구름(또는 숨김).
    static func classify(inputSourceID id: String, primaryLanguage lang: String?) -> CloudState {
        let prefix = "org.youknowone.inputmethod.Gureum."
        guard id.hasPrefix(prefix) else { return .hidden } // 구름 외 입력 소스 → 숨김
        if let lang = lang { return lang == "ko" ? .korean : .english }
        // 언어 메타데이터가 없을 때만 모드 id로 추론(로마자 레이아웃은 영문).
        let romanModes: Set<String> = ["qwerty", "colemak", "dvorak"]
        return romanModes.contains(String(id.dropFirst(prefix.count))) ? .english : .korean
    }

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    override init() {
        super.init()
        item.button?.imageScaling = .scaleProportionallyDown
        buildMenu()
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(inputSourceChanged),
            name: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil
        )
        update()
    }

    deinit { DistributedNotificationCenter.default().removeObserver(self) }

    @objc private func inputSourceChanged() {
        DispatchQueue.main.async { [weak self] in self?.update() }
    }

    private func update() {
        let state: CloudState = currentInputSourceInfo()
            .map { Self.classify(inputSourceID: $0.id, primaryLanguage: $0.language) } ?? .hidden
        switch state {
        case .hidden:
            item.isVisible = false
        case .korean, .english:
            item.isVisible = true
            // Apple SF Symbol cloud, drawn directly (vector -> crisp; status-item slot is
            // width-flexible -> the wide cloud shows undistorted). Korean = filled, English = outline.
            let symbol = state == .korean ? "icloud.fill" : "icloud"
            let config = NSImage.SymbolConfiguration(pointSize: 21, weight: .regular)
            let image = NSImage(systemSymbolName: symbol,
                                accessibilityDescription: state == .korean ? "한국어" : "영문")?
                .withSymbolConfiguration(config)
            image?.isTemplate = true
            item.button?.image = image
        }
    }

    private func buildMenu() {
        let menu = NSMenu()
        let prefs = NSMenuItem(title: "환경설정…", action: #selector(openPreferences), keyEquivalent: "")
        prefs.target = self
        let about = NSMenuItem(title: "구름 입력기 정보…", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(prefs)
        menu.addItem(.separator())
        menu.addItem(about)
        item.menu = menu
    }

    @objc private func openPreferences() {
        NSApp.activate(ignoringOtherApps: true)
        preferencesWindow.showWindow(nil)
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }
}
