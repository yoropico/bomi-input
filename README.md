![logo](OSX/Assets.xcassets/AppIcon.appiconset/icon_256x256.png)

![platform](https://img.shields.io/badge/platform-macOS%2011.0%2B-lightgrey)

# bomi-input

macOS를 위한 한글 입력기 — [gureum/gureum](https://github.com/gureum/gureum)(구름 입력기) 기반의 포크를 `bomi-input`으로 리브랜드한 것입니다.

> **이 저장소는 구름 입력기의 포크입니다.**
> 빠른 포커스 전환 시 한글 입력이 영어로 고착되던 버그를 고치고, 최신 macOS에 맞춰
> 코드를 현대화했습니다. 죽은 코드와 무거운 의존성(Firebase 등)을 걷어내고 최소
> macOS 버전을 11.0으로 올렸으며, 이름과 아이콘을 `bomi-input`으로 새로 입혔습니다.
> 자세한 변경 내역은 [CHANGELOG.md](CHANGELOG.md)를 참고해 주세요. 원본 프로젝트의
> 일반적인 소개·사용법은 [gureum/gureum](https://github.com/gureum/gureum)에 있습니다.

## 소개

bomi-input은 빠르고 쓰기 편한 macOS용 한글 입력기입니다. 구름 입력기를 기반으로 합니다.

- **편리하게.** [libhangul](https://github.com/libhangul/libhangul) 기반으로 모아치기를 지원합니다. 모아치기 기능은 세벌식 사용자에게 특히 더 유용합니다.
- **가볍게.** 최소한의 기능만 구현하여 가볍게 돌아갑니다. 이 포크는 Firebase·분석 코드 등 불필요한 의존성을 제거해 더 가볍습니다.
- **자유롭게.** 오픈 소스 소프트웨어이며, 소스 코드는 BSD와 LGPL로 배포됩니다.

`libhangul` 기반이라 두벌식·세벌식 등 다양한 한글 자판을 지원하고, 드보락이나
콜맥을 포함한 어떤 시스템 자판과도 결합해 사용할 수 있습니다. 입력기 전환을
막기 위해 쿼티 자판을 내장하고 있어 한글-쿼티 전환이 빠릅니다.

메뉴 막대에는 현재 입력 상태를 한눈에 보여주는 인디케이터가 뜹니다 — 한국어는
**ㅂ**, 영문은 **B**(모노크롬 템플릿이라 라이트·다크 모드에 자동으로 맞춰집니다).

## 이 포크의 변경사항

upstream(`gureum/gureum`) 대비 이 포크에서 추가된 변경입니다. 전체 목록과 상세는
[CHANGELOG.md](CHANGELOG.md)에 있습니다.

### 리브랜드 — bomi-input

- **이름·아이콘 변경** — 앱·번들 ID·입력 소스 ID를 `bomi-input`(`com.yoropico.inputmethod.bomi-input`) 체계로 바꾸고, 앱 아이콘과 메뉴 막대 인디케이터를 자체 제작한 **ㅂ / B** 브랜드 글리프로 교체했습니다. 라이선스가 비상업·변경불가(CC BY-NC-ND)였던 구름의 원본 로고·아이콘 리소스는 제거했습니다.
- **메뉴 막대 인디케이터 정리** — 입력 소스 메뉴 아이콘을 모노크롬 템플릿으로 단순화하고(라이트·다크 자동 틴팅), 한/영 상태를 가로 폭 제약 없이 또렷이 보여주는 상태 막대(NSStatusItem) 인디케이터를 추가했습니다.

### 정리·최신화 (1.15.0)

- **Firebase Crashlytics 제거** — 크래시 리포팅용으로만 쓰이던 Firebase를 통째로 들어내, gRPC·protobuf 등 약 16개의 transitive 의존성이 함께 사라졌습니다(남은 SPM 의존성: MASShortcut·Fuse·Alamofire·SwiftUp).
- **죽은 코드 제거** — 동작하지 않던 분석 셸(`AnswersHelper`)과, 어떤 활성 빌드에서도 쓰이지 않던 iOS 소스 일체(독립 `iOS.xcodeproj` 포함, 약 1만 줄)를 제거했습니다.
- **최소 macOS 11.0으로 상향** — 더 이상 필요 없는 구버전 `@available` 분기를 정리했습니다.

### 버그 수정·현대화 (1.14.0)

- **한글 입력이 영어로 고착되는 문제 수정** ([#2](https://github.com/yoropico/bomi-input/pull/2)) — Edge/Chromium처럼 포커스가 빠르게 바뀌는 앱에서 입력 소스는 한글로 보이는데 실제로는 영어가 입력되던 문제를 고쳤습니다. 새 입력 세션이 직전 한/영 상태를 이어받도록 했습니다.
- **알림 시스템 현대화** ([#1](https://github.com/yoropico/bomi-input/pull/1)) — deprecated된 `NSUserNotification`을 최신 `UserNotifications` 프레임워크로 마이그레이션했습니다.
- **Preferences 빌드 오류 수정** ([#1](https://github.com/yoropico/bomi-input/pull/1)) — Xcode의 explicitly-built modules 환경에서 `SwiftIOKit` 대신 `IOKit.hid`를 사용하도록 바꿔 빌드 실패를 해결했습니다.

## 설치

**요구 사항: macOS 11.0 (Big Sur) 이상.**

이 포크는 Homebrew Cask나 공식 설치 패키지로 배포되지 않습니다. 소스에서 직접
빌드해 설치합니다.

### 빌드

전체 개발 환경 설정과 빌드 방법은 [개발하기(HACKING.md)](HACKING.md) 문서를 참고해 주세요. 요약하면 다음과 같습니다.

```sh
git clone https://github.com/yoropico/bomi-input.git
cd bomi-input
make init          # libhangul 등 submodule 가져오기
git fetch --tags   # 버전 정보(태그) 가져오기
open bomi-input.xcodeproj
```

Xcode에서 `OSX` 스킴을 빌드하면 의존성과 함께 bomi-input이 빌드됩니다. 빌드
결과물은 `bomi-input.app`입니다.

> 빌드 시 태그에서 유도된 버전 문자열이 비어 있으면 입력기가 등록되지 않을 수
> 있습니다. `git fetch --tags`로 태그를 먼저 받아 두세요.

### 입력기 등록

1. 빌드한 `bomi-input.app`을 `/Library/Input Methods`에 복사합니다. (Finder에서 루트 디스크 → 라이브러리 → Input Methods)
2. 로그아웃 후 다시 로그인합니다.
3. '시스템 설정 → 키보드 → 입력 소스'에서 bomi-input이 제공하는 입력 소스를 추가합니다.
4. 사용할 한글 자판을 한 번 수동으로 선택해 줍니다. `Caps Lock 키로 입력 소스 전환`을 켜 두었다면, 이후 <kbd>Caps Lock</kbd>으로 자동 전환됩니다. <kbd>⇧Space</kbd> 같은 단축키를 쓰려면 환경설정에서 자판 전환 단축키를 지정해 주세요.

> 직접 서명하지 않은(ad-hoc 서명) 빌드를 다시 설치하면 입력 소스에서 빠지거나
> '입력 모니터링' 권한이 초기화될 수 있습니다. 이 경우 입력 소스를 다시 추가하고
> 권한을 재허용한 뒤 로그아웃/로그인해 주세요.

## 제거

제거하기 전에 **사용 중인 입력기를 OS 기본 입력기로 전환**해 주세요.

1. `활성 상태 보기.app (Activity Monitor.app)`을 실행하고 `bomi-input`을 검색하여 프로세스를 종료합니다.
2. Finder에서 `/Library/Input Methods`로 이동하여 `bomi-input.app`을 삭제합니다.
3. 로그아웃 후 다시 로그인합니다.

## 개발 / 기여

- 개발 환경 설정과 디버깅: [개발하기(HACKING.md)](HACKING.md)
- 기여 가이드와 이슈 작성: [기여하기(CONTRIBUTING.md)](CONTRIBUTING.md)

버그를 발견하면 재현 방법과 사용 환경을 [이슈 페이지](https://github.com/yoropico/bomi-input/issues)에 남겨 주세요.

## upstream

이 포크는 [gureum/gureum](https://github.com/gureum/gureum)을 기반으로 합니다.
upstream의 기능 개선과 버그 수정을 주기적으로 반영하며, 이 포크의 변경 중 일부는
upstream에 기여 제안될 수 있습니다.

## 라이선스

bomi-input의 소스 코드는 구름 입력기에서 이어받아 BSD와 LGPL로 배포됩니다.
`libhangul`은 LGPL 라이선스를 따릅니다. 구름의 원본 로고·아이콘(CC BY-NC-ND)은
제거했고, bomi-input의 앱 아이콘·인디케이터는 이 포크에서 자체 제작했습니다.

## 만든 사람들

기반이 된 구름 입력기는 [많은 분들의 도움](https://github.com/gureum/gureum/graphs/contributors)으로 함께 개발되고 있습니다. 원본 프로젝트의 재정 후원은 [후원하기](https://opencollective.com/gureum/contribute)에서 할 수 있습니다. `bomi-input`은 [yoropico](https://github.com/yoropico)가 구름 입력기를 포크해 리브랜드한 것입니다.

[![](https://opencollective.com/gureum/contributors.svg?width=890&button=false)](https://github.com/gureum/gureum/graphs/contributors)
