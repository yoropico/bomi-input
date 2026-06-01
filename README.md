![logo](OSX/Assets.xcassets/AppIcon.appiconset/icon_256x256.png)

![platform](https://img.shields.io/badge/platform-macos-lightgrey)

# 구름 입력기 (yoropico 포크)

macOS를 위한 한글 입력기 — [gureum/gureum](https://github.com/gureum/gureum)의 포크입니다.

> **이 저장소는 구름 입력기의 포크입니다.**
> 최신 macOS에 맞춰 일부 코드를 현대화하고, 빠른 포커스 전환 시 한글 입력이
> 영어로 고착되던 버그를 고쳤습니다. 자세한 변경 내역은
> [CHANGELOG.md](CHANGELOG.md)를 참고해 주세요. 원본 프로젝트의 일반적인
> 소개·사용법은 [gureum/gureum](https://github.com/gureum/gureum)에 있습니다.

## 소개

구름 입력기는 빠르고 쓰기 편한 macOS용 한글 입력기입니다.

- **편리하게.** [libhangul](https://github.com/libhangul/libhangul) 기반으로 모아치기를 지원합니다. 모아치기 기능은 세벌식 사용자에게 특히 더 유용합니다.
- **가볍게.** 최소한의 기능만 구현하여 가볍게 돌아갑니다.
- **자유롭게.** 오픈 소스 소프트웨어이며, 소스 코드는 BSD와 LGPL로 배포됩니다.

`libhangul` 기반이라 두벌식·세벌식 등 다양한 한글 자판을 지원하고, 드보락이나
콜맥을 포함한 어떤 시스템 자판과도 결합해 사용할 수 있습니다. 입력기 전환을
막기 위해 쿼티 자판을 내장하고 있어 한글-쿼티 전환이 빠릅니다.

## 이 포크의 변경사항

upstream(`gureum/gureum`) 대비 이 포크에서 추가된 변경입니다. 전체 목록은
[CHANGELOG.md](CHANGELOG.md)에 있습니다.

- **한글 입력이 영어로 고착되는 문제 수정** ([#2](https://github.com/yoropico/gureum/pull/2)) — Edge/Chromium처럼 포커스가 빠르게 바뀌는 앱에서 입력 소스는 한글로 보이는데 실제로는 영어가 입력되던 문제를 고쳤습니다. 새 입력 세션이 직전 한/영 상태를 이어받도록 했습니다.
- **알림 시스템 현대화** ([#1](https://github.com/yoropico/gureum/pull/1)) — deprecated된 `NSUserNotification`을 최신 `UserNotifications` 프레임워크로 마이그레이션했습니다.
- **Preferences 빌드 오류 수정** ([#1](https://github.com/yoropico/gureum/pull/1)) — Xcode의 explicitly-built modules 환경에서 `SwiftIOKit` 대신 `IOKit.hid`를 사용하도록 바꿔 빌드 실패를 해결했습니다.

## 설치

이 포크는 Homebrew Cask나 공식 설치 패키지로 배포되지 않습니다. 소스에서 직접
빌드해 설치합니다.

### 빌드

전체 개발 환경 설정과 빌드 방법은 [개발하기(HACKING.md)](HACKING.md) 문서를 참고해 주세요. 요약하면 다음과 같습니다.

```sh
git clone https://github.com/yoropico/gureum.git
cd gureum
make init          # libhangul 등 submodule 가져오기
git fetch --tags   # 버전 정보(태그) 가져오기
open Gureum.xcodeproj
```

Xcode에서 `Gureum` 타겟을 빌드하면 의존성과 함께 구름 입력기가 빌드됩니다. 빌드
결과물은 `Gureum.app`입니다.

> 빌드 시 태그에서 유도된 버전 문자열이 비어 있으면 입력기가 등록되지 않을 수
> 있습니다. `git fetch --tags`로 태그를 먼저 받아 두세요.

### 입력기 등록

1. 빌드한 `Gureum.app`을 `/Library/Input Methods`에 복사합니다. (Finder에서 루트 디스크 → 라이브러리 → Input Methods)
2. 로그아웃 후 다시 로그인합니다.
3. '시스템 설정 → 키보드 → 입력 소스'에서 구름 입력기가 제공하는 입력 소스를 추가합니다.
4. 사용할 한글 자판을 한 번 수동으로 선택해 줍니다. `Caps Lock 키로 입력 소스 전환`을 켜 두었다면, 이후 <kbd>Caps Lock</kbd>으로 자동 전환됩니다. <kbd>⇧Space</kbd> 같은 단축키를 쓰려면 환경설정에서 자판 전환 단축키를 지정해 주세요.

> 직접 서명하지 않은(ad-hoc 서명) 빌드를 다시 설치하면 입력 소스에서 빠지거나
> '입력 모니터링' 권한이 초기화될 수 있습니다. 이 경우 입력 소스를 다시 추가하고
> 권한을 재허용한 뒤 로그아웃/로그인해 주세요.

## 제거

제거하기 전에 **사용 중인 입력기를 OS 기본 입력기로 전환**해 주세요.

1. `활성 상태 보기.app (Activity Monitor.app)`을 실행하고 `gureum`을 검색하여 프로세스를 종료합니다.
2. Finder에서 `/Library/Input Methods`로 이동하여 `Gureum.app`을 삭제합니다.
3. 로그아웃 후 다시 로그인합니다.

## 개발 / 기여

- 개발 환경 설정과 디버깅: [개발하기(HACKING.md)](HACKING.md)
- 기여 가이드와 이슈 작성: [기여하기(CONTRIBUTING.md)](CONTRIBUTING.md)

버그를 발견하면 재현 방법과 사용 환경을 [이슈 페이지](https://github.com/yoropico/gureum/issues)에 남겨 주세요.

## upstream

이 포크는 [gureum/gureum](https://github.com/gureum/gureum)을 기반으로 합니다.
upstream의 기능 개선과 버그 수정을 주기적으로 반영하며, 이 포크의 변경 중 일부는
upstream에 기여 제안될 수 있습니다.

## 라이선스

구름 입력기는 BSD와 LGPL로 배포됩니다. `libhangul`은 LGPL 라이선스를 따릅니다.

## 만든 사람들

구름 입력기는 [많은 분들의 도움](https://github.com/gureum/gureum/graphs/contributors)으로 함께 개발되고 있습니다. 원본 프로젝트의 재정 후원은 [후원하기](https://opencollective.com/gureum/contribute)에서 할 수 있습니다.

[![](https://opencollective.com/gureum/contributors.svg?width=890&button=false)](https://github.com/gureum/gureum/graphs/contributors)
