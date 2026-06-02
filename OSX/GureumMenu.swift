//
//  GureumMenu.swift
//  OSX
//
//  Created by KMLee on 2018. 8. 24..
//  Copyright © 2018 youknowone.org. All rights reserved.
//

import Cocoa
import Foundation
import GureumCore

let preferencesWindow: NSWindowController = NSStoryboard(name: "Configuration", bundle: Bundle.main).instantiateInitialController() as! NSWindowController

// 왜 App delegate가 아니라 여기 붙는건지 모르겠다
extension InputController {
    @IBAction func showStandardAboutPanel(_ sender: Any) {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(sender)
    }

    @IBAction func showPreferencesWindow(_: Any) {
        NSApp.activate(ignoringOtherApps: true)
        preferencesWindow.showWindow(nil)
    }

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
                    done.informativeText = "새 버전을 설치했습니다. 로그아웃 후 다시 로그인하면 적용됩니다.\n\n적용 후 입력 소스 목록에서 구름이 사라졌으면 시스템 설정 > 키보드 > 입력 소스에서 다시 추가하고, 한/영 전환이 안 되면 시스템 설정 > 개인정보 보호 및 보안 > 입력 모니터링에서 구름을 다시 허용한 뒤 로그아웃·로그인 해 주세요."
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

    @IBAction func checkRecentVersion(_: Any) {
        checkVersion(mode: .Stable)
    }

    @IBAction func checkExperimentalVersion(_: Any) {
        checkVersion(mode: .Experimental)
    }

    @IBAction func openWebsite(_: Any) {
        let url = URL(string: "http://gureum.io")!
        NSWorkspace.shared.open(url)
    }

    @IBAction func openWebsiteHelp(_: Any) {
        let url = URL(string: "http://dan.gureum.io")!
        NSWorkspace.shared.open(url)
    }

    @IBAction func openWebsiteSource(_: Any) {
        let url = URL(string: "http://ssi.gureum.io")!
        NSWorkspace.shared.open(url)
    }

    @IBAction func openWebsiteIssues(_: Any) {
        let url = URL(string: "http://meok.gureum.io")!
        NSWorkspace.shared.open(url)
    }

    @IBAction func openWebsiteDonation(_: Any) {
        let url = URL(string: "http://donation.gureum.io")!
        NSWorkspace.shared.open(url)
    }
}
