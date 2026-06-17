# 변경 이력

이 프로젝트의 주요 변경 사항을 기록합니다. 형식은
[Keep a Changelog](https://keepachangelog.com/ko/1.1.0/)를 따르며,
[유의적 버전](https://semver.org/lang/ko/)을 사용합니다.

이 저장소는 [gureum/gureum](https://github.com/gureum/gureum)의 포크입니다.
아래 항목은 upstream 대비 이 포크에서 추가된 변경 사항이며, upstream 자체의
변경 이력은 원본 저장소를 참고해 주세요.

## [1.15.1] - 2026-06-17

### 고침 (Fixed)

- **macOS Secure Event Input 상태에서 한/영 토글이 안 되던 문제 수정.** 다른 앱(비밀번호 입력 칸, 터미널 sudo/ssh 등)이 Secure Event Input을 켜면 전역 `IOHIDManager` 키 모니터가 시스템 전역으로 차단되어, 오른쪽 Command(한/영) 토글이 먹통이 되고 다른 곳을 클릭해야 풀리던 문제를 고쳤습니다. 토글 키 감지를 그 전역 모니터 대신 **입력기 자신이 받는 `flagsChanged` 이벤트의 `keyCode`**(우측 Command=54 등)로 하도록 바꿨습니다 — 이 `keyCode`는 Secure Event Input 하에서도 입력기에 그대로 전달되므로(on-device 확인: secure 상태에서도 우측 Command가 keyCode=54로 도착), secure 상태에서도 토글이 동작합니다. `IOHIDManager` 경로는 `keyCode`가 전달되지 않는 환경용 폴백으로 유지합니다. (참고: 좌/우 구분 모디파이어 비트는 입력기에 전달되지 않아 — on-device 확인 — `keyCode`로 판정합니다. 또한 토글 시 macOS가 별도로 등록된 한글/로마자 입력 소스 사이를 전환(`selectMode`)하는 데 따른 전환 지연은 기존과 동일하게 남습니다 — 입력기 처리 자체는 즉시입니다.) (`OSXCore/InputController.swift`, `OSXCore/InputMethodServer.swift`, 신규 `GureumTests/RightToggleKeyTests.swift`)
- **타이핑 지연 감소** — 키 입력 경로 진입부(`InputReceiver.input(text:)`)에서 매 글자마다 호출하던 `selectedRange()`·`markedRange()`(포커스된 앱으로의 동기 IPC 왕복) 두 호출을 제거했습니다. 그 값을 쓰던 분기가 전부 주석 처리되어 결과가 버려지고 있었으므로 동작 변화 없이 글자당 앱 왕복만 줄어듭니다. (`OSXCore/InputReceiver.swift`)
- **"bomi-input에 관하여"(정보/About) 패널에 버전 표시.** 빌드 버전(`CFBundleShortVersionString`/`CFBundleVersion`)이 비어 정보 창에 버전이 안 보이던 문제를 고쳤습니다. 빌드에 버전을 채우고, 정보 패널에 버전 문자열을 코드에서 직접 전달하도록 했습니다(`OSX/GureumMenu.swift`). 재설치 시 IME가 옛 바이너리로 재실행되던 레이스(설치 순서)도 함께 정리했습니다.

## [1.15.0] - 2026-06-01

코드 정리와 현대화 릴리스입니다. 죽은 코드와 무거운 의존성을 크게 줄였습니다.
최소 macOS 버전 상향을 제외하면 입력 동작에는 변화가 없습니다.

### 바뀜 (Changed)

- **최소 macOS 버전 상향: 10.13 → 11.0 (Big Sur).** macOS 11.0 미만에서는 더 이상 동작하지 않습니다. 이에 맞춰 소스의 macOS 10.14 / 10.15 / 11.0 `@available` 가드를 모두 걷어냈습니다. (Preferences의 macOS 13 가드는 유지)

### 제거 (Removed)

- **Firebase Crashlytics 전체 제거.** `firebase-ios-sdk` SPM 의존성, `FirebaseCrashlytics` 링크, "Run Crashlytics" 빌드 페이즈, 번들되던 `GoogleService-Info.plist`, `FirebaseApp.configure()` 호출을 모두 제거했습니다. 크래시 리포트가 이 포크가 아닌 upstream 작성자의 Firebase 프로젝트로만 전송되던 것을 없애면서, gRPC·BoringSSL·protobuf 등 약 16개의 transitive SPM 패키지가 함께 사라졌습니다(남은 의존성: MASShortcut·Fuse·Alamofire·SwiftUp). 크래시 수집을 위해 켜 두던 `NSApplicationCrashOnExceptions` 등록도 함께 제거했습니다.
- **죽은 분석 코드(`AnswersHelper`) 제거.** Fabric/Answers SDK가 빠진 뒤 본문이 전부 주석 처리되어 아무 동작도 하지 않던 셸과 모든 호출부를 제거했습니다.
- **미사용 iOS 서브시스템 제거.** 어떤 활성 빌드(bomi-input.xcodeproj·Makefile·CI 모두 macOS 전용)에서도 참조되지 않고, 2020년에 종료된 Fabric/Crashlytics SDK를 import하던 iOS 소스 일체(`iOS/`, `iOSApp/`, `iOSShared/`, `iOSTests/`, `iOSTheme/`)와 독립 `iOS.xcodeproj`를 제거했습니다(약 1만 줄).

## [1.14.0] - 2026-06-01

upstream `1.13.2`를 기반으로 한 첫 포크 릴리스입니다.

### 고침 (Fixed)

- **한글 입력이 영어로 고착되는 문제** ([#2](https://github.com/yoropico/bomi-input/pull/2)) — Edge/Chromium 등 포커스가 빠르게 바뀌는(activate/deactivate가 잦은) 앱에서, 입력 소스 표시는 한글인데 실제로는 영어가 입력되던 문제를 고쳤습니다.
  - 원인 ① `GureumComposer`가 새 입력 세션을 항상 마지막 *로마자* 모드(쿼티)로 시작해, 시스템의 `setValue`(한/영 전환) 호출을 놓치면 한글 표시 상태인데도 영어로 고착되었습니다.
  - 원인 ② 초기화 시 `inputMode`를 설정한 뒤 `delegate`를 로마자 조합기로 덮어써, 한글 모드인데 영어가 입력되었습니다.
  - 수정: `Configuration`에 `lastInputMode`(한/영 무관, 마지막 실제 입력 모드)를 추가하고, `GureumComposer.init`이 이 값을 초기 모드로 이어받도록 했습니다. 또한 기본 `delegate`를 `inputMode` 설정보다 *먼저* 두어, `inputMode` setter가 정한 조합기가 항상 마지막에 적용되게 했습니다.
- **Preferences 타겟 빌드 실패** ([#1](https://github.com/yoropico/bomi-input/pull/1)) — Xcode의 explicitly-built modules 환경에서 `PreferenceViewController`가 `SwiftIOKit` 대신 `IOKit.hid`를 import 하도록 바꿔 빌드 오류를 해결했습니다.

### 바뀜 (Changed)

- **알림 시스템 현대화** ([#1](https://github.com/yoropico/bomi-input/pull/1)) — deprecated된 `NSUserNotification` / `NSUserNotificationCenter`를 최신 `UserNotifications` 프레임워크로 마이그레이션했습니다. (`OSX/GureumAppDelegate.swift`, `OSX/UpdateManager.swift`, 관련 테스트)

[1.15.0]: https://github.com/yoropico/bomi-input/compare/1.14.0...main
[1.14.0]: https://github.com/yoropico/bomi-input/compare/1.13.2...1.14.0
