//
//  InlineComposition.swift
//  OSXCore
//
//  Ported from DKST (DINKIssTyle-IME-macOS).
//  MIT License. Copyright © 2025 DINKIssTyle.
//
//  This file is intentionally PURE: it must not import IMK/AppKit nor
//  produce any side effects, so the composition-mode policy can be unit
//  tested without a live `IMKTextInput` client.
//

import Foundation

/// 합성 중인 글자를 어떤 방식으로 클라이언트에 표시할지 나타내는 분류.
///
/// - `inline`: 클라이언트의 본문에 직접(인라인) 합성 결과를 반영한다.
/// - `marked`: 시스템이 제공하는 marked text(밑줄 표시)로 합성 결과를 보여 준다.
public enum CompositionMode: Equatable {
    case inline
    case marked
}

/// 합성 표시 방식을 결정하기 위해 필요한 클라이언트 정보를 추상화한 프로토콜.
///
/// 정책 결정 함수가 필요로 하는 모든 질의 표면을 이 프로토콜로 주입한다.
/// 라이브 `IMKTextInput` 클라이언트 없이도 정책을 테스트할 수 있도록
/// 이 프로토콜은 순수한 값 질의만 노출한다.
public protocol ClientCapabilities {
    /// 전역 "항상 marked text 사용" 설정 값.
    var alwaysMarkedGlobal: Bool { get }

    /// Apple이 제공하는 신호: 클라이언트가 합성 중인 글자를 marked text로
    /// 보여 주는지 여부.
    ///
    /// - Returns: `true`/`false`로 명확히 답할 수 있으면 해당 값을,
    ///   클라이언트가 이 API를 구현하지 않아 알 수 없으면 `nil`을 반환한다.
    ///
    /// - Important: `nil`은 "알 수 없음 / 미구현"을 뜻하며, 정책 체인이
    ///   다음 단계로 떨어질 수 있도록(fall through) 그대로 전달해야 한다.
    ///   이 함수에서 `nil`을 임의의 기본값으로 합쳐 버리면 안 된다.
    func showsComposingTextAsMarkedText() -> Bool?

    /// 클라이언트의 `selectedRange`를 인라인 합성에 쓸 수 있는지 여부.
    func selectedRangeIsQueryable() -> Bool

    /// 클라이언트(호스트 앱)의 번들 식별자.
    var bundleIdentifier: String? { get }

    /// 사용자가 "강제 marked text"로 지정한 번들 식별자 목록.
    ///
    /// 엔진 휴리스틱(WebKit/Chromium)보다 우선하는 사용자 명시 override다.
    /// (DKST `_forcedMarkedTextBundleIDs` 대응)
    var forcedMarkedBundleIDs: [String] { get }

    /// 호스트 앱이 Chromium/Electron 텍스트 스택을 쓰는지, `.app` 번들의
    /// `Contents/Frameworks`를 스캔해 판정한다(side-effecting; 결과는 캐시).
    ///
    /// 번들 식별자 prefix 목록(`bundleIdentifierUsesChromiumMarkedTextPolicy`)에
    /// 잡히지 않는 Electron 앱을 잡기 위한 폴백이다.
    /// (DKST `runningApplicationUsesChromiumTextStack:` 대응)
    func usesChromiumFrameworkTextStack() -> Bool
}

public extension ClientCapabilities {
    /// 기본값: 강제 marked 목록 없음. (P1 스텁/구형 conformer 호환)
    var forcedMarkedBundleIDs: [String] { [] }

    /// 기본값: 프레임워크 스캔 미수행. (P1 스텁/구형 conformer 호환)
    func usesChromiumFrameworkTextStack() -> Bool { false }
}

// MARK: - Bundle-identifier engine classification (pure, DKST port)

/// 번들 식별자가 주어진 prefix 중 하나와 "정확히 일치"하거나 `prefix + "."`로
/// 시작하는지 판정한다. 점 경계를 요구하므로 `com.apple.WebKitten`처럼 우연히
/// prefix로 시작하는 식별자는 제외된다. (DKST의 `isEqualToString:`/`hasPrefix:` 쌍)
private func bundleIdentifier(_ bundleID: String, matchesAnyPrefix prefixes: [String]) -> Bool {
    guard !bundleID.isEmpty else {
        return false
    }
    for prefix in prefixes {
        if bundleID == prefix || bundleID.hasPrefix(prefix + ".") {
            return true
        }
    }
    return false
}

/// 주어진 번들 식별자가 WebKit 텍스트 스택(Safari/WebKit)을 쓰는지 판정한다.
///
/// DKST `bundleIdentifierUsesWebKitTextStack:` (InputController.m:401) 포팅.
public func bundleIdentifierUsesWebKitTextStack(_ bundleID: String) -> Bool {
    bundleIdentifier(bundleID, matchesAnyPrefix: [
        "com.apple.Safari",
        "com.apple.WebKit",
        "com.apple.mobilesafari",
    ])
}

/// 주어진 번들 식별자가 Chromium 계열(marked-text 정책 대상)인지 판정한다.
///
/// DKST `bundleIdentifierUsesChromiumMarkedTextPolicy:` (InputController.m:430) 포팅.
public func bundleIdentifierUsesChromiumMarkedTextPolicy(_ bundleID: String) -> Bool {
    bundleIdentifier(bundleID, matchesAnyPrefix: [
        "org.chromium.Chromium",
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "com.microsoft.edgemac",
        "com.brave.Browser",
        "com.vivaldi.Vivaldi",
        "com.operasoftware.Opera",
        "com.naver.Whale",
        "company.thebrowser.Browser", // Arc
        "ai.perplexity.comet",
        "com.perplexity.Comet",
        "com.perplexity.comet",
        "com.openai.atlas",
        "com.openai.Atlas",
        "com.openai.chatgpt.atlas",
    ])
}

/// 번들 식별자가 사용자 강제 marked 목록에 (대소문자 무시) 포함되는지 판정한다.
///
/// macOS 번들 식별자는 대소문자를 구분하지 않으므로 비교도 대소문자 무시로 한다.
public func bundleIdentifierMatchesForcedMarkedList(_ bundleID: String, _ list: [String]) -> Bool {
    guard !bundleID.isEmpty else {
        return false
    }
    let needle = bundleID.lowercased()
    return list.contains { $0.lowercased() == needle }
}

// MARK: - Composition mode policy

/// 주어진 클라이언트 정보(`caps`)만으로 합성 표시 방식을 결정하는 순수 함수.
///
/// DKST의 `-[InputController shouldUseMarkedTextForClient:]`
/// (Sources/InputController.m:840)을 포팅한 것이다.
/// IMK/AppKit에 접근하지 않으며 전역 상태(`Configuration.shared` 등)를
/// 내부에서 읽지 않는다. 모든 입력은 `caps`로만 들어온다.
///
/// 우선순위 체인:
/// 1. `caps.alwaysMarkedGlobal`이면 → `.marked` (전역 강제).
/// 2. `caps.showsComposingTextAsMarkedText()`가 non-nil이면 즉시 반영:
///    `true → .marked`, `false → .inline` (Apple 신호 우선).
/// 3. 사용자 강제 marked 목록에 있으면 → `.marked` (엔진 휴리스틱보다 우선).
/// 4. WebKit 텍스트 스택이면 → `.inline`.
/// 5. Chromium 텍스트 스택(번들 prefix 또는 프레임워크 스캔)이면 → `.marked`.
/// 6. `caps.selectedRangeIsQueryable()`가 거짓이면 → `.marked` (안전 측면).
/// 7. 그 외 기본값 → `.inline`.
public func classifyComposition(_ caps: ClientCapabilities) -> CompositionMode {
    // 1. 전역 "항상 marked text" 설정.
    if caps.alwaysMarkedGlobal {
        return .marked
    }

    // 2. Apple 신호: non-nil이면 즉시 반영하고, nil이면 다음 단계로 떨어진다.
    if let showsMarked = caps.showsComposingTextAsMarkedText() {
        return showsMarked ? .marked : .inline
    }

    // 3. 사용자 강제 marked 목록(엔진 휴리스틱보다 우선하는 사용자 override).
    if let bundleID = caps.bundleIdentifier,
       bundleIdentifierMatchesForcedMarkedList(bundleID, caps.forcedMarkedBundleIDs)
    {
        return .marked
    }

    // 4. WebKit 텍스트 스택(Safari/WebKit) → 인라인.
    if let bundleID = caps.bundleIdentifier,
       bundleIdentifierUsesWebKitTextStack(bundleID)
    {
        return .inline
    }

    // 5. Chromium 텍스트 스택 → marked. 번들 prefix 목록을 먼저 보고,
    //    잡히지 않으면 `.app` 프레임워크 스캔(side-effecting)으로 폴백한다.
    if let bundleID = caps.bundleIdentifier,
       bundleIdentifierUsesChromiumMarkedTextPolicy(bundleID)
    {
        return .marked
    }
    if caps.usesChromiumFrameworkTextStack() {
        return .marked
    }

    // 6. selectedRange를 인라인 합성에 쓸 수 없으면 안전하게 marked.
    if !caps.selectedRangeIsQueryable() {
        return .marked
    }

    // 7. 기본값: 인라인 합성.
    return .inline
}
