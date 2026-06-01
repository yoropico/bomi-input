# GitHub Auto-Updater Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the fork check its own GitHub Releases and, on user confirmation, download + verify + install the new build (one admin prompt), replacing today's upstream-feed + manual-download flow.

**Architecture:** Extend `UpdateManager` (version check via GitHub Releases API + semver compare) and add a focused `Updater` (download `.zip` → verify codesign+team → install to `/Library/Input Methods` via one `osascript` admin call, with a graceful "open release page" fallback when sandboxed). Wire the existing menu + notification actions to the new install flow.

**Tech Stack:** Swift 5, Alamofire (already a dependency), Foundation `Process`, `NSAppleScript`, XCTest.

---

## Spec

`docs/superpowers/specs/2026-06-01-github-auto-updater-design.md`

## Verified context

- `OSX/UpdateManager.swift`: `class UpdateManager` with nested `struct UpdateInfo: Decodable {version, description, url}` and `struct VersionInfo {current = Bundle.main.version; update; experimental}`; `requestVersionInfo(mode:)` (Alamofire), `requestAutoUpdateVersionInfo`, `class func updateNotificationContent(info:)`, `class func notifyUpdate(info:)`, `notifyUpdateIfNeeded()`.
- `OSX/GureumMenu.swift`: `InputController.checkVersion(mode:)` shows alerts and `NSWorkspace.shared.open(info.update.url)`; `checkRecentVersion`/`checkExperimentalVersion` IBActions.
- `OSX/GureumAppDelegate.swift`: `NotificationCenterDelegate.userNotificationCenter(_:didReceive:)` reads `userInfo["url"]` and opens it when the update action fires.
- `OSXCore/Configuration.swift`: `enum UpdateMode { case Stable; case Experimental }`, `Configuration.shared.updateMode: UpdateMode?`.
- `OSXCore/BundleVersion.swift`: `Bundle.version` = `CFBundleVersion`.
- `GureumTests/GureumTests.swift`: already references `UpdateManager.UpdateInfo` / `.VersionInfo` / `.updateNotificationContent` (test `testNotifyUpdate`) — so new `UpdateManager` symbols are reachable from this test file with no extra import.
- Repo `yoropico/gureum`; app at `/Library/Input Methods/Gureum.app`; signing team `G7J2LY4LP9`.

## Build / test commands (used throughout)

Compile (signing disabled — this machine has no Developer ID; the compile is the gate):
```bash
xcodebuild -project Gureum.xcodeproj -scheme OSX -configuration Release \
  CURRENT_PROJECT_VERSION=1.13 MARKETING_VERSION=1.13.2 \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build
```
Unit tests:
```bash
xcodebuild -project Gureum.xcodeproj -scheme OSX -configuration Debug \
  CURRENT_PROJECT_VERSION=1.13 MARKETING_VERSION=1.13.2 \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  test -only-testing:GureumTests/GureumTests 2>&1 | tail -40
```
(The pre-existing `GureumObjCTests.testIPMDServerClientWrapper` failure under unsigned builds is known/unrelated — ignore it.)

## Git rules (a prior session corrupted history — follow exactly)

- Branch is `feature/github-auto-updater` (already checked out). ONE plain `git commit -m` per task; NEVER `git reset`/`--amend`/`rebase`/`checkout <branch>`. `git add` explicit paths only. If a build dirties `OSX/Version.xcconfig`, `git checkout -- OSX/Version.xcconfig` and don't stage it. Don't touch `docs/`/`.claude/`.

---

## Task 1: Semver-aware version comparison

**Files:**
- Modify: `OSX/UpdateManager.swift`
- Test: `GureumTests/GureumTests.swift`

- [ ] **Step 1: Write the failing test** — add this method inside `class GureumTests` in `GureumTests/GureumTests.swift`:

```swift
func testIsNewer() throws {
    XCTAssertTrue(UpdateManager.isNewer("1.16.0", than: "1.15.0"))
    XCTAssertFalse(UpdateManager.isNewer("1.15.0", than: "1.15.0"))
    XCTAssertTrue(UpdateManager.isNewer("1.10.0", than: "1.9.0"))   // 10 > 9 numerically
    XCTAssertFalse(UpdateManager.isNewer("1.9.0", than: "1.10.0"))
    XCTAssertTrue(UpdateManager.isNewer("v1.16.0", than: "1.15.0")) // leading v stripped
    XCTAssertFalse(UpdateManager.isNewer("1.16.0-rc1", than: "1.16.0")) // numeric core equal
    XCTAssertFalse(UpdateManager.isNewer("1.16.0", than: "1.16.0-rc1"))
    XCTAssertTrue(UpdateManager.isNewer("1.16.1", than: "1.16.0-rc1"))
}
```

- [ ] **Step 2: Run it to confirm it fails (no such member)**

Run the unit-test command above with `-only-testing:GureumTests/GureumTests/testIsNewer`.
Expected: compile failure `type 'UpdateManager' has no member 'isNewer'`.

- [ ] **Step 3: Implement `isNewer`** — add this static method inside `class UpdateManager` in `OSX/UpdateManager.swift` (e.g. just below `static let shared`):

```swift
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
```

- [ ] **Step 4: Run the test to confirm it passes**

Run the same `-only-testing:GureumTests/GureumTests/testIsNewer`. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add OSX/UpdateManager.swift GureumTests/GureumTests.swift
git commit -m "Add semver-aware UpdateManager.isNewer

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Read version info from the GitHub Releases API

**Files:**
- Modify: `OSX/UpdateManager.swift`
- Test: `GureumTests/GureumTests.swift`

- [ ] **Step 1: Write the failing test** — add inside `class GureumTests`:

```swift
func testGitHubReleaseDecodeAndAsset() throws {
    let json = """
    {
      "tag_name": "1.16.0",
      "body": "release notes",
      "html_url": "https://github.com/yoropico/gureum/releases/tag/1.16.0",
      "prerelease": false,
      "assets": [
        {"name": "Gureum-1.16.0.zip", "browser_download_url": "https://example.com/Gureum-1.16.0.zip"},
        {"name": "source.txt", "browser_download_url": "https://example.com/source.txt"}
      ]
    }
    """.data(using: .utf8)!
    let release = try JSONDecoder().decode(UpdateManager.GitHubRelease.self, from: json)
    XCTAssertEqual(release.tagName, "1.16.0")
    XCTAssertEqual(release.body, "release notes")
    XCTAssertFalse(release.prerelease)
    XCTAssertEqual(release.zipAssetURL, "https://example.com/Gureum-1.16.0.zip")

    let noZip = """
    {"tag_name":"1.16.0","html_url":"https://h","prerelease":false,"assets":[]}
    """.data(using: .utf8)!
    let r2 = try JSONDecoder().decode(UpdateManager.GitHubRelease.self, from: noZip)
    XCTAssertNil(r2.body)
    XCTAssertNil(r2.zipAssetURL)
}
```

- [ ] **Step 2: Run it to confirm it fails**

`-only-testing:GureumTests/GureumTests/testGitHubReleaseDecodeAndAsset`. Expected: compile failure `no member 'GitHubRelease'`.

- [ ] **Step 3: Add the GitHub structs** — inside `class UpdateManager`, next to `UpdateInfo`/`VersionInfo`, add:

```swift
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
```

Also add `pageURL` to `VersionInfo` so the release page is available for fallback. Change the `VersionInfo` struct to:

```swift
struct VersionInfo {
    let current: String? = Bundle.main.version
    let update: UpdateInfo
    let experimental: Bool
    var pageURL: String? = nil
}
```

- [ ] **Step 4: Run the test to confirm it passes**

`-only-testing:GureumTests/GureumTests/testGitHubReleaseDecodeAndAsset`. Expected: PASS. Also re-run `testNotifyUpdate` (unchanged `VersionInfo(update:experimental:)` call still compiles because `pageURL` is defaulted).

- [ ] **Step 5: Repoint `requestVersionInfo` to GitHub** — replace the entire body of `func requestVersionInfo(mode:_:)` in `OSX/UpdateManager.swift` with:

```swift
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

    let request = AF.request(urlRequest).validate()
    switch mode {
    case .Stable:
        request.responseDecodable(of: GitHubRelease.self) { handle($0.value) }
    case .Experimental:
        request.responseDecodable(of: [GitHubRelease].self) { handle($0.value?.first) }
    }
}
```

- [ ] **Step 6: Build to confirm it compiles**

Run the compile command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add OSX/UpdateManager.swift GureumTests/GureumTests.swift
git commit -m "Point UpdateManager at the fork's GitHub Releases API

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Use isNewer in the auto-check and carry version/pageURL in the notification

**Files:**
- Modify: `OSX/UpdateManager.swift`

- [ ] **Step 1: Use `isNewer` in `notifyUpdateIfNeeded`** — replace the `guard info.update.version != info.current else { return }` line in `notifyUpdateIfNeeded()` with:

```swift
            guard UpdateManager.isNewer(info.update.version, than: info.current ?? "") else {
                return
            }
```

- [ ] **Step 2: Carry version + pageURL in the notification userInfo** — in `class func updateNotificationContent(info:)`, replace `content.userInfo = ["url": info.update.url]` with:

```swift
        content.userInfo = [
            "url": info.update.url,
            "version": info.update.version,
            "pageURL": info.pageURL ?? info.update.url,
        ]
```

- [ ] **Step 3: Build to confirm it compiles**

Run the compile command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add OSX/UpdateManager.swift
git commit -m "Use semver compare for auto-check; carry version/pageURL in update notification

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: The Updater (download → verify → privileged install → fallback)

**Files:**
- Create: `OSX/Updater.swift`

This unit performs network + filesystem + privileged operations and is not unit-testable; the gate is a clean compile here and the manual end-to-end check in Task 6.

- [ ] **Step 1: Create `OSX/Updater.swift`** with this complete content:

```swift
//
//  Updater.swift
//  OSX
//
//  Downloads a GitHub Release .zip, verifies its code signature, and installs
//  it to /Library/Input Methods via a single administrator prompt. Falls back
//  to opening the release page when the privileged install is unavailable
//  (e.g. a sandboxed build).
//

import Alamofire
import AppKit
import Foundation

enum UpdaterError: Error {
    case noAsset
    case download
    case unzip
    case verification
    case install
    case sandboxed
    case cancelled
}

final class Updater {
    static let shared = Updater()

    private let installPath = "/Library/Input Methods/Gureum.app"
    private let inputMethodsDir = "/Library/Input Methods"
    private let expectedTeamIdentifier = "G7J2LY4LP9"
    private let lsregisterPath =
        "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

    /// 업데이트 zip을 받아 검증하고 설치한다. completion은 메인 스레드에서 호출된다.
    func performUpdate(info: UpdateManager.VersionInfo,
                       completion: @escaping (Result<Void, UpdaterError>) -> Void)
    {
        let downloadString = info.update.url
        guard let downloadURL = URL(string: downloadString), downloadString.hasSuffix(".zip") else {
            openReleasePage(info)
            return finish(completion, .failure(.noAsset))
        }

        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GureumUpdate-\(UUID().uuidString)")
        let destination: DownloadRequest.Destination = { _, _ in
            try? FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
            return (workDir.appendingPathComponent("Gureum.zip"), [.removePreviousFile, .createIntermediateDirectories])
        }

        AF.download(downloadURL, to: destination).validate().response { [weak self] response in
            guard let self = self else { return }
            guard response.error == nil, let zipURL = response.fileURL else {
                return self.finish(completion, .failure(.download))
            }
            self.installFromZip(zipURL, workDir: workDir, info: info, completion: completion)
        }
    }

    private func installFromZip(_ zipURL: URL,
                                workDir: URL,
                                info: UpdateManager.VersionInfo,
                                completion: @escaping (Result<Void, UpdaterError>) -> Void)
    {
        let extractDir = workDir.appendingPathComponent("extracted")
        guard run("/usr/bin/ditto", ["-x", "-k", zipURL.path, extractDir.path]).status == 0,
              let appURL = findApp(in: extractDir)
        else {
            return finish(completion, .failure(.unzip))
        }

        guard run("/usr/bin/codesign", ["--verify", "--strict", appURL.path]).status == 0,
              teamIdentifier(of: appURL) == expectedTeamIdentifier
        else {
            return finish(completion, .failure(.verification))
        }

        installWithPrivileges(appURL: appURL, info: info, completion: completion)
    }

    private func installWithPrivileges(appURL: URL,
                                       info: UpdateManager.VersionInfo,
                                       completion: @escaping (Result<Void, UpdaterError>) -> Void)
    {
        let src = appURL.path
        // 셸 경로는 작은따옴표로 감싼다(AppleScript 문자열은 큰따옴표).
        let shell = "rm -rf '\(installPath)' && cp -R '\(src)' '\(inputMethodsDir)/' && "
            + "/usr/bin/killall -TERM Gureum 2>/dev/null; '\(lsregisterPath)' -f '\(installPath)'; true"
        let source = "do shell script \"\(shell)\" with administrator privileges"

        DispatchQueue.global().async { [weak self] in
            guard let self = self else { return }
            var errorDict: NSDictionary?
            let script = NSAppleScript(source: source)
            _ = script?.executeAndReturnError(&errorDict)
            if let error = errorDict {
                let code = (error[NSAppleScript.errorNumber] as? Int) ?? 0
                if code == -128 { // userCanceledErr
                    return self.finish(completion, .failure(.cancelled))
                }
                // 샌드박스 등으로 권한 실행이 막힌 경우: 릴리스 페이지로 폴백.
                self.openReleasePage(info)
                return self.finish(completion, .failure(.sandboxed))
            }
            self.finish(completion, .success(()))
        }
    }

    // MARK: - Helpers

    private func findApp(in directory: URL) -> URL? {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)) ?? []
        return contents.first(where: { $0.pathExtension == "app" })
    }

    /// codesign -dvv 출력을 파싱해 TeamIdentifier를 얻는다.
    private func teamIdentifier(of appURL: URL) -> String? {
        let result = run("/usr/bin/codesign", ["-dvv", appURL.path])
        // codesign는 -dvv 정보를 stderr로 출력한다.
        for line in result.stderr.split(separator: "\n") {
            if line.hasPrefix("TeamIdentifier=") {
                return String(line.dropFirst("TeamIdentifier=".count))
            }
        }
        return nil
    }

    private func openReleasePage(_ info: UpdateManager.VersionInfo) {
        let urlString = info.pageURL ?? info.update.url
        if let url = URL(string: urlString) {
            DispatchQueue.main.async { NSWorkspace.shared.open(url) }
        }
    }

    private func run(_ launchPath: String, _ arguments: [String]) -> (status: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        do {
            try process.run()
        } catch {
            return (-1, "", "\(error)")
        }
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus,
                String(data: outData, encoding: .utf8) ?? "",
                String(data: errData, encoding: .utf8) ?? "")
    }

    private func finish(_ completion: @escaping (Result<Void, UpdaterError>) -> Void,
                        _ result: Result<Void, UpdaterError>)
    {
        DispatchQueue.main.async { completion(result) }
    }
}
```

- [ ] **Step 2: Add `OSX/Updater.swift` to the OSX target in the project**

`Updater.swift` must be a member of the `OSX` target's Compile Sources. Open `Gureum.xcodeproj` in Xcode, drag `OSX/Updater.swift` into the OSX group with the OSX target checked — OR confirm the pbxproj has it. After this step, the file must appear in the OSX target's `PBXSourcesBuildPhase`.

- [ ] **Step 3: Build to confirm it compiles and is in the target**

Run the compile command. Expected: `** BUILD SUCCEEDED **` (and no "cannot find 'Updater' in scope" later). If `Updater` is not compiled, the build of Task 5 will fail — fix target membership now.

- [ ] **Step 4: Commit**

```bash
git add OSX/Updater.swift Gureum.xcodeproj/project.pbxproj
git commit -m "Add Updater: download + verify + privileged install of GitHub release

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: Wire the menu and notification action to the Updater

**Files:**
- Modify: `OSX/GureumMenu.swift`
- Modify: `OSX/GureumAppDelegate.swift`

- [ ] **Step 1: Replace `checkVersion(mode:)` in `OSX/GureumMenu.swift`** with a version that offers an Update button driving the Updater. Replace the whole `private func checkVersion(mode:)` method with:

```swift
    private func checkVersion(mode: UpdateMode) {
        let title: String
        let version: String
        switch mode {
        case .Stable:
            title = "업데이트"
            version = "버전"
        case .Experimental:
            title = "실험 버전"
            version = "실험 버전"
        }
        UpdateManager.shared.requestVersionInfo(mode: mode) { info in
            guard let info = info else {
                let alert = NSAlert()
                alert.messageText = "구름 입력기 \(title) 확인"
                alert.addButton(withTitle: "확인")
                alert.informativeText = "\(title) 정보에 접근할 수 없습니다. 인터넷에 연결되어 있지 않거나 구름 업데이트의 버그일 수 있습니다."
                alert.runModal()
                return
            }
            guard UpdateManager.isNewer(info.update.version, than: info.current ?? "") else {
                let alert = NSAlert()
                alert.messageText = "구름 입력기 \(title) 확인"
                alert.addButton(withTitle: "확인")
                alert.informativeText = "현재 사용하고 있는 구름 입력기 \(info.current ?? "-") 는 최신 \(version)입니다."
                alert.runModal()
                return
            }
            var message = "현재 버전 \(info.current ?? "-"), 최신 \(version) \(info.update.version). 지금 업데이트하면 다운로드 후 설치하며, 로그아웃하거나 재부팅해야 적용됩니다."
            if !info.update.description.isEmpty {
                message += "\n\n\(info.update.description)"
            }
            let alert = NSAlert()
            alert.messageText = "구름 입력기 \(title) 확인"
            alert.informativeText = message
            alert.addButton(withTitle: "지금 업데이트")
            alert.addButton(withTitle: "나중에")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            Updater.shared.performUpdate(info: info) { result in
                let done = NSAlert()
                switch result {
                case .success:
                    done.messageText = "업데이트 완료"
                    done.informativeText = "로그아웃 후 다시 로그인하면 적용됩니다."
                case let .failure(error):
                    done.messageText = "업데이트 실패"
                    switch error {
                    case .cancelled: return
                    case .verification:
                        done.informativeText = "다운로드한 앱의 서명 검증에 실패해 설치를 중단했습니다."
                    case .sandboxed, .noAsset:
                        done.informativeText = "자동 설치를 진행할 수 없어 릴리스 페이지를 열었습니다. 직접 설치해 주세요."
                    default:
                        done.informativeText = "업데이트 중 문제가 발생했습니다. 잠시 후 다시 시도해 주세요."
                    }
                }
                done.addButton(withTitle: "확인")
                done.runModal()
            }
        }
    }
```

- [ ] **Step 2: Route the notification action to the Updater in `OSX/GureumAppDelegate.swift`** — in `NotificationCenterDelegate.userNotificationCenter(_:didReceive:withCompletionHandler:)`, replace the body that computes `updating` and opens the URL. Replace this block:

```swift
        var updating = false
        switch response.actionIdentifier {
        case gureumUpdateNotificationActionIdentifier, UNNotificationDefaultActionIdentifier:
            updating = true
        default:
            break
        }
        if updating {
            NSWorkspace.shared.open(URL(string: download)!)
        }
```

with:

```swift
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
```

(`download` is the existing `guard let download = userInfo["url"] as? String` binding above this block — keep it.)

- [ ] **Step 3: Build to confirm it compiles**

Run the compile command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add OSX/GureumMenu.swift OSX/GureumAppDelegate.swift
git commit -m "Wire menu + notification update actions to the Updater

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: Non-sandboxed personal entitlements + end-to-end verification

**Files:**
- Create: `OSX/Gureum-personal.entitlements`

- [ ] **Step 1: Create `OSX/Gureum-personal.entitlements`** (no sandbox; non-sandboxed apps have unrestricted IOHID/network so no entitlements are required):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
</dict>
</plist>
```

- [ ] **Step 2: Commit the entitlements file**

```bash
git add OSX/Gureum-personal.entitlements
git commit -m "Add non-sandbox entitlements for personal updater-enabled build

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

- [ ] **Step 3: Build the signed, non-sandboxed personal build**

```bash
xcodebuild -project Gureum.xcodeproj -scheme OSX -configuration Release \
  -derivedDataPath build/DerivedData-updater \
  CURRENT_PROJECT_VERSION=1.13 MARKETING_VERSION=1.13.2 \
  DEVELOPMENT_TEAM=G7J2LY4LP9 CODE_SIGN_STYLE=Automatic \
  CODE_SIGN_IDENTITY="Apple Development" \
  CODE_SIGN_ENTITLEMENTS=OSX/Gureum-personal.entitlements \
  -allowProvisioningUpdates build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`. Confirm non-sandboxed: `codesign -d --entitlements :- build/DerivedData-updater/Build/Products/Release/Gureum.app 2>/dev/null` shows NO `com.apple.security.app-sandbox`.

- [ ] **Step 4: Manual end-to-end verification (cannot be automated — needs network, admin, and a published release)**

1. Install this build to `/Library/Input Methods` (osascript admin), re-grant Input Monitoring once, log out/in.
2. Publish a TEST GitHub release with a tag higher than the installed `CFBundleVersion` (e.g. `1.16.0-test`) and a `Gureum-1.16.0-test.zip` asset built the same signed way (`ditto -c -k --keepParent Gureum.app Gureum-1.16.0-test.zip`).
3. In the IME menu choose "버전 확인" → confirm it reports the new version → click "지금 업데이트".
4. Expected: one admin password prompt → "업데이트 완료 — 로그아웃 후 적용" → after re-login the new version is installed and Korean input still works.
5. Delete the test release afterward.

Report the observed result of steps 3–4 (this is the feature's real acceptance test).

- [ ] **Step 5: Push branch and open PR**

```bash
git push -u origin feature/github-auto-updater
gh pr create --base main --head feature/github-auto-updater \
  --title "GitHub-based lightweight auto-updater" \
  --body "$(cat <<'EOF'
Check the fork's own GitHub Releases and install updates with one click.

- UpdateManager → GitHub Releases API (Stable=releases/latest, Experimental=releases[0]) + semver compare.
- Updater: download .zip → verify codesign+team (G7J2LY4LP9) → install to /Library/Input Methods via one admin prompt; falls back to opening the release page when sandboxed.
- Menu + notification update actions drive the Updater.
- Personal build is non-sandboxed (OSX/Gureum-personal.entitlements) so the privileged install works.

Spec: docs/superpowers/specs/2026-06-01-github-auto-updater-design.md
Plan: docs/superpowers/plans/2026-06-01-github-auto-updater.md

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

## Notes for the implementer

- **Full-code edit invariant:** when a step says "replace the method/block", emit the complete updated file, not a diff.
- **Korean strings** (alerts, comments) are user-facing/inherently-Korean — keep them as written.
- Tasks 1–3 are TDD'd (pure logic). Task 4 (Updater) is integration code: the compile is the in-loop gate; Task 6 step 4 is its real acceptance test. Do not fake an automated test for the download/install path.
- `UpdateManager.UpdateInfo` / `.VersionInfo` / `.GitHubRelease` are nested types referenced from `OSX/Updater.swift`, `OSX/GureumMenu.swift`, `OSX/GureumAppDelegate.swift`, and `GureumTests` — all in or linked to the OSX target, so no extra imports are needed (mirror existing `testNotifyUpdate`).
