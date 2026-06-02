//
//  GureumAppDelegate.swift
//  Gureum
//
//  Created by 혜원 on 2018. 8. 27..
//  Copyright © 2018 youknowone.org. All rights reserved.
//

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

        watcher.reloadConfiguration()
    }
}
