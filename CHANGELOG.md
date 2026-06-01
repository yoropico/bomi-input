# 변경 이력

이 프로젝트의 주요 변경 사항을 기록합니다. 형식은
[Keep a Changelog](https://keepachangelog.com/ko/1.1.0/)를 따르며,
[유의적 버전](https://semver.org/lang/ko/)을 사용합니다.

이 저장소는 [gureum/gureum](https://github.com/gureum/gureum)의 포크입니다.
아래 항목은 upstream 대비 이 포크에서 추가된 변경 사항이며, upstream 자체의
변경 이력은 원본 저장소를 참고해 주세요.

## [1.14.0] - 2026-06-01

upstream `1.13.2`를 기반으로 한 첫 포크 릴리스입니다.

### 고침 (Fixed)

- **한글 입력이 영어로 고착되는 문제** ([#2](https://github.com/yoropico/gureum/pull/2)) — Edge/Chromium 등 포커스가 빠르게 바뀌는(activate/deactivate가 잦은) 앱에서, 입력 소스 표시는 한글인데 실제로는 영어가 입력되던 문제를 고쳤습니다.
  - 원인 ① `GureumComposer`가 새 입력 세션을 항상 마지막 *로마자* 모드(쿼티)로 시작해, 시스템의 `setValue`(한/영 전환) 호출을 놓치면 한글 표시 상태인데도 영어로 고착되었습니다.
  - 원인 ② 초기화 시 `inputMode`를 설정한 뒤 `delegate`를 로마자 조합기로 덮어써, 한글 모드인데 영어가 입력되었습니다.
  - 수정: `Configuration`에 `lastInputMode`(한/영 무관, 마지막 실제 입력 모드)를 추가하고, `GureumComposer.init`이 이 값을 초기 모드로 이어받도록 했습니다. 또한 기본 `delegate`를 `inputMode` 설정보다 *먼저* 두어, `inputMode` setter가 정한 조합기가 항상 마지막에 적용되게 했습니다.
- **Preferences 타겟 빌드 실패** ([#1](https://github.com/yoropico/gureum/pull/1)) — Xcode의 explicitly-built modules 환경에서 `PreferenceViewController`가 `SwiftIOKit` 대신 `IOKit.hid`를 import 하도록 바꿔 빌드 오류를 해결했습니다.

### 바뀜 (Changed)

- **알림 시스템 현대화** ([#1](https://github.com/yoropico/gureum/pull/1)) — deprecated된 `NSUserNotification` / `NSUserNotificationCenter`를 최신 `UserNotifications` 프레임워크로 마이그레이션했습니다. (`OSX/GureumAppDelegate.swift`, `OSX/UpdateManager.swift`, 관련 테스트)

[1.14.0]: https://github.com/yoropico/gureum/compare/1.13.2...main
