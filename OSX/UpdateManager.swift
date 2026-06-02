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

    struct GitHubAsset: Decodable {
        let name: String
        let browserDownloadURL: String
        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    struct GitHubRelease: Decodable {
        let tagName: String
        let body: String?
        let htmlURL: String
        let prerelease: Bool
        let assets: [GitHubAsset]
        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case body
            case htmlURL = "html_url"
            case prerelease
            case assets
        }

        /// 첫 번째 `.zip` 자산의 다운로드 URL.
        var zipAssetURL: String? {
            assets.first(where: { $0.name.hasSuffix(".zip") })?.browserDownloadURL
        }
    }

    struct VersionInfo {
        let current: String? = Bundle.main.version
        let update: UpdateInfo
        let experimental: Bool
        var pageURL: String? = nil
    }

    func requestVersionInfo(mode: UpdateMode, _ done: @escaping ((VersionInfo?) -> Void)) {
        let urlString: String
        switch mode {
        case .Stable:
            urlString = "https://api.github.com/repos/yoropico/gureum/releases/latest"
        case .Experimental:
            urlString = "https://api.github.com/repos/yoropico/gureum/releases"
        }
        var urlRequest = URLRequest(url: URL(string: urlString)!)
        urlRequest.timeoutInterval = 5.0
        urlRequest.cachePolicy = .reloadIgnoringCacheData
        // GitHub API requires a User-Agent; without it the request gets 403.
        urlRequest.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        urlRequest.setValue("Gureum-Updater", forHTTPHeaderField: "User-Agent")

        let handle: (GitHubRelease?) -> Void = { release in
            guard let release = release else { return done(nil) }
            let info = UpdateInfo(
                version: release.tagName,
                description: release.body ?? "",
                url: release.zipAssetURL ?? release.htmlURL
            )
            let version = VersionInfo(
                update: info,
                experimental: mode == .Experimental,
                pageURL: release.htmlURL
            )
            done(version)
        }

        // 상태 코드만 검증한다. 기본 `validate()`는 응답 Content-Type을 요청 Accept
        // 헤더와 대조하는데, GitHub는 Accept가 application/vnd.github+json이어도
        // application/json으로 응답하므로 content-type 검증이 실패해 nil이 된다.
        let request = AF.request(urlRequest).validate(statusCode: 200 ..< 300)
        switch mode {
        case .Stable:
            request.responseDecodable(of: GitHubRelease.self) { handle($0.value) }
        case .Experimental:
            request.responseDecodable(of: [GitHubRelease].self) { handle($0.value?.first) }
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
        content.userInfo = [
            "url": info.update.url,
            "version": info.update.version,
            "pageURL": info.pageURL ?? info.update.url,
        ]
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
            guard UpdateManager.isNewer(info.update.version, than: info.current ?? "") else {
                return
            }
            UpdateManager.notifyUpdate(info: info)
        }
    }
}
