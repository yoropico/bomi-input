//
//  UpdateManager.swift
//  OSX
//
//  Created by Jeong YunWon on 01/01/2019.
//  Copyright © 2019 youknowone.org. All rights reserved.
//

import Alamofire
import Foundation
import GureumCore
import UserNotifications

/// 업데이트 알림에 사용하는 `UNNotificationCategory` 식별자.
/// 카테고리 등록(`GureumAppDelegate`)과 알림 컨텐츠 생성(`UpdateManager`)이 공유한다.
let gureumUpdateNotificationCategoryIdentifier = "Gureum.update"
/// 업데이트 알림의 "업데이트" 액션 버튼 식별자.
let gureumUpdateNotificationActionIdentifier = "Gureum.update.action"

class UpdateManager {
    static let shared = UpdateManager()

    /// 두 버전 문자열을 의미 기반(semver 유사)으로 비교한다.
    /// 선행 v/V 제거 후 숫자·점으로 이뤄진 앞부분만 취해 점 단위 정수 비교한다.
    /// 프리릴리스 접미사(-rc1 등)는 숫자 비교에서 무시하며, 숫자가 같으면 newer로 보지 않는다.
    static func isNewer(_ remote: String, than current: String) -> Bool {
        func numericComponents(_ raw: String) -> [Int] {
            var value = raw
            if value.hasPrefix("v") || value.hasPrefix("V") { value.removeFirst() }
            let core = value.prefix { $0.isNumber || $0 == "." }
            return core.split(separator: ".").map { Int($0) ?? 0 }
        }
        let r = numericComponents(remote)
        let c = numericComponents(current)
        for index in 0 ..< max(r.count, c.count) {
            let rv = index < r.count ? r[index] : 0
            let cv = index < c.count ? c[index] : 0
            if rv != cv { return rv > cv }
        }
        return false
    }

    struct UpdateInfo: Decodable {
        let version: String
        let description: String
        let url: String

        enum CodingKeys: String, CodingKey {
            case version
            case description
            case url
        }
    }

    struct VersionInfo {
        let current: String? = Bundle.main.version
        let update: UpdateInfo
        let experimental: Bool
    }

    func requestVersionInfo(mode: UpdateMode, _ done: @escaping ((VersionInfo?) -> Void)) {
        let url: URL
        switch mode {
        case .Stable:
            url = URL(string: "https://gureum.io/version.json")!
        case .Experimental:
            url = URL(string: "https://gureum.io/version-experimental.json")!
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.timeoutInterval = 1.0
        urlRequest.cachePolicy = .reloadIgnoringCacheData

        let request = AF.request(urlRequest)
//        request.responseJSON {
//            data in
//            print("data!", data)
//        }
        request.validate().responseDecodable(of: UpdateInfo.self) { response in
            guard let update = response.value else { return done(nil) }
            let version = VersionInfo(update: update, experimental: mode == .Experimental)
            done(version)
        }
    }

    func requestAutoUpdateVersionInfo(_ done: @escaping ((VersionInfo?) -> Void)) {
        guard let mode = Configuration.shared.updateMode else {
            return
        }
        requestVersionInfo(mode: mode, done)
    }

    /// 업데이트 알림에 표시할 `UNNotificationContent`를 만든다.
    /// 전달(delivery)과 분리해 단위 테스트에서 컨텐츠만 검증할 수 있도록 한다.
    class func updateNotificationContent(info: VersionInfo) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        var title = "구름 입력기 업데이트 알림"
        if info.experimental {
            title += " (실험 버전)"
        }
        content.title = title
        content.body = "최신 버전: \(info.update.version) 현재 버전: \(info.current ?? "-")\n\(info.update.description)"
        content.userInfo = ["url": info.update.url]
        content.categoryIdentifier = gureumUpdateNotificationCategoryIdentifier
        return content
    }

    class func notifyUpdate(info: VersionInfo) {
        let content = updateNotificationContent(info: info)
        let request = UNNotificationRequest(
            identifier: gureumUpdateNotificationCategoryIdentifier,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    func notifyUpdateIfNeeded() {
        requestAutoUpdateVersionInfo { info in
            guard let info = info else {
                return
            }
            guard info.update.version != info.current else {
                return
            }
            UpdateManager.notifyUpdate(info: info)
        }
    }
}
