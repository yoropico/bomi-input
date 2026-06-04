//
//  Configuration.swift
//  Gureum
//
//  Created by Jeong YunWon on 2018. 4. 19..
//  Copyright © 2018 youknowone.org. All rights reserved.
//

import AppKit
import Foundation

/// 환경 설정 이름을 정의한 열거형.
enum ConfigurationName {
    /// 마지막 한글 입력 모드.
    public static let lastHangulInputMode = "LastHangulInputMode"
    /// 마지막 로마자 입력 모드.
    public static let lastRomanInputMode = "LastRomanInputMode"
    /// 마지막 입력 모드(한글/로마자 무관). 새 입력 세션의 초기 모드로 사용.
    public static let lastInputMode = "LastInputMode"

    /// 입력기 바꾸기 단축키.
    public static let inputModeExchangeKey = "InputModeExchangeKey"
    /// 한자 및 이모지 검색 단축키.
    public static let inputModeSearchKey = "InputModeHanjaKey"
    /// 로마자로 바꾸기 단축키.
    public static let inputModeEnglishKey = "InputModeEnglishKey"
    /// 한글로 바꾸기 단축키.
    public static let inputModeKoreanKey = "InputModeKoreanKey"
    /// 옵션 키 동작.
    public static let optionKeyBehavior = "OptionKeyBehavior"
    /// 기본 키보드 레이아웃.
    public static let overridingKeyboardName = "OverridingKeyboardName"

    /// Esc 키로 로마자 자판으로 전환 (vi 모드).
    public static let romanModeByEscapeKey = "ExchangeToRomanModeByEscapeKey"
    /// 한글 입력기일 때 역따옴표(`)로 원화 기호(₩) 입력.
    public static let hangulWonCurrencySymbolForBackQuote = "HangulWonCurrencySymbolForBackQuote"
    /// 완성되지 않은 낱자 자동 교정 (모아치기).
    public static let hangulAutoReorder = "HangulAutoReorder"
    /// 두벌식 초성 조합 중에도 종성 결합 허용 (MS윈도 호환).
    public static let hangulNonChoseongCombination = "HangulNonChoseongCombination"
    /// 모든 글자를 조합 중인 글자로 취급 (JDK 호환).
    public static let hangulDeferredSymbolCommit = "HangulDeferredSymbolCommit"
    /// 세벌식 정석 강요.
    public static let hangulForceStrictCombinationRule = "HangulForceStrictCombinationRule"
    /// 우측 키로 언어 전환
    public static let rightToggleKey = "RightToggleKey"

    /// 인라인 직접 입력 기능 (DKST 방식 이식, MIT) 마스터 스위치.
    public static let inlineCompositionEnabled = "InlineCompositionEnabled"
    /// 인라인 직접 입력 기능 (DKST 방식 이식, MIT) 시 모든 클라이언트에서 marked-text 강제.
    public static let inlineCompositionAlwaysMarked = "InlineCompositionAlwaysMarked"
    /// 인라인 직접 입력 기능에서 marked-text를 강제할 사용자 지정 번들 식별자 목록.
    public static let inlineCompositionForcedMarkedBundleIDs = "InlineCompositionForcedMarkedBundleIDs"

    /// 업데이트 알림 받기
    public static let updateNotification = "UpdateNotification"
    /// 실험버전 업데이트 알림 받기
    public static let updateNotificationExperimental = "UpdateNotificationExperimental"
}

// MARK: - Configuration 클래스

public enum UpdateMode {
    case Stable
    case Experimental
}

/// 입력기의 환경 설정을 담당하는 오브젝트.
public class Configuration: UserDefaults {
    public static let sharedSuiteName = "com.yoropico.bomi-input"
    public static var shared = Configuration()

    var enableCapslockToToggleInputMode: Bool = false

    public typealias Shortcut = (KeyCode, NSEvent.ModifierFlags)

    class func convertShortcutToConfiguration(_ shortcut: Shortcut?) -> [String: Any] {
        guard let shortcut = shortcut else {
            return [:]
        }
        return ["modifier": shortcut.1.rawValue, "keyCode": shortcut.0.rawValue]
    }

    class func convertConfigurationToShortcut(_ configuration: [String: Any]) -> Shortcut? {
        guard let modifier = configuration["modifier"] as? UInt,
              let keyCodeRawValue = configuration["keyCode"] as? Int,
              let keyCode = KeyCode(rawValue: keyCodeRawValue)
        else {
            return nil
        }
        return (keyCode, NSEvent.ModifierFlags(rawValue: modifier))
    }

    override init?(suiteName: String?) {
        super.init(suiteName: suiteName)

        register(defaults: [
            ConfigurationName.lastHangulInputMode: "com.yoropico.inputmethod.bomi-input.han2",
            ConfigurationName.lastRomanInputMode: "com.yoropico.inputmethod.bomi-input.qwerty",
            ConfigurationName.lastInputMode: "com.yoropico.inputmethod.bomi-input.qwerty",

            ConfigurationName.inputModeSearchKey: Configuration.convertShortcutToConfiguration((.return, .option)),
            ConfigurationName.optionKeyBehavior: 1,
            ConfigurationName.overridingKeyboardName: "com.apple.keylayout.ABC",

            ConfigurationName.romanModeByEscapeKey: false,
            ConfigurationName.hangulWonCurrencySymbolForBackQuote: true,
            ConfigurationName.hangulAutoReorder: false,
            ConfigurationName.hangulNonChoseongCombination: false,
            ConfigurationName.hangulDeferredSymbolCommit: false,
            ConfigurationName.hangulForceStrictCombinationRule: false,
            ConfigurationName.rightToggleKey: kHIDUsage_KeyboardRightAlt,

            ConfigurationName.inlineCompositionEnabled: false,
            ConfigurationName.inlineCompositionAlwaysMarked: false,
            ConfigurationName.inlineCompositionForcedMarkedBundleIDs: [String](),

            ConfigurationName.updateNotification: true,
            ConfigurationName.updateNotificationExperimental: false,
        ])
    }

    convenience init() {
        self.init(suiteName: Configuration.sharedSuiteName)!
    }

    public func persistentDomain() -> [String: Any] {
        return persistentDomain(forName: Configuration.sharedSuiteName) ?? [:]
    }

    // TODO: code generation

    /// 마지막 한글 입력 모드.
    public var lastHangulInputMode: String {
        get {
            string(forKey: ConfigurationName.lastHangulInputMode)!
        }
        set {
            set(newValue, forKey: ConfigurationName.lastHangulInputMode)
        }
    }

    /// 마지막 로마자 입력 모드.
    public var lastRomanInputMode: String {
        get {
            string(forKey: ConfigurationName.lastRomanInputMode)!
        }
        set {
            set(newValue, forKey: ConfigurationName.lastRomanInputMode)
        }
    }

    /// 마지막 입력 모드(한글/로마자 무관). 새 입력 세션의 초기 모드로 사용해,
    /// 시스템 setValue가 누락되어도 직전 한/영 상태를 유지한다.
    public var lastInputMode: String {
        get {
            string(forKey: ConfigurationName.lastInputMode)!
        }
        set {
            set(newValue, forKey: ConfigurationName.lastInputMode)
        }
    }

    /// 옵션 키 동작.
    public var optionKeyBehavior: Int {
        get {
            integer(forKey: ConfigurationName.optionKeyBehavior)
        }
        set {
            set(newValue, forKey: ConfigurationName.optionKeyBehavior)
        }
    }

    /// 기본 키보드 레이아웃.
    public var overridingKeyboardName: String {
        get {
            string(forKey: ConfigurationName.overridingKeyboardName)!
        }
        set {
            set(newValue, forKey: ConfigurationName.overridingKeyboardName)
        }
    }

    /// 입력기 바꾸기 단축키.
    public var inputModeExchangeKey: Shortcut? {
        get {
            shortcut(forKey: ConfigurationName.inputModeExchangeKey)
        }
        set {
            setShortcut(newValue, forKey: ConfigurationName.inputModeExchangeKey)
        }
    }

    /// 한자 및 이모지 검색 단축키.
    public var inputModeSearchKey: Shortcut? {
        get {
            shortcut(forKey: ConfigurationName.inputModeSearchKey)
        }
        set {
            setShortcut(newValue, forKey: ConfigurationName.inputModeSearchKey)
        }
    }

    /// 로마자로 바꾸기 단축키.
    public var inputModeEnglishKey: Shortcut? {
        get {
            shortcut(forKey: ConfigurationName.inputModeEnglishKey)
        }
        set {
            setShortcut(newValue, forKey: ConfigurationName.inputModeEnglishKey)
        }
    }

    /// 한글로 바꾸기 단축키.
    public var inputModeKoreanKey: Shortcut? {
        get {
            shortcut(forKey: ConfigurationName.inputModeKoreanKey)
        }
        set {
            setShortcut(newValue, forKey: ConfigurationName.inputModeKoreanKey)
        }
    }

    /// Esc 키로 로마자 자판으로 전환 (vi 모드).
    public var romanModeByEscapeKey: Bool {
        get {
            bool(forKey: ConfigurationName.romanModeByEscapeKey)
        }
        set {
            set(newValue, forKey: ConfigurationName.romanModeByEscapeKey)
        }
    }

    /// 한글 입력기일 때 역따옴표(`)로 원화 기호(₩) 입력.
    public var hangulWonCurrencySymbolForBackQuote: Bool {
        get {
            bool(forKey: ConfigurationName.hangulWonCurrencySymbolForBackQuote)
        }
        set {
            set(newValue, forKey: ConfigurationName.hangulWonCurrencySymbolForBackQuote)
        }
    }

    /// 완성되지 않은 낱자 자동 교정 (모아치기).
    public var hangulAutoReorder: Bool {
        get {
            bool(forKey: ConfigurationName.hangulAutoReorder)
        }
        set {
            set(newValue, forKey: ConfigurationName.hangulAutoReorder)
        }
    }

    /// 두벌식 초성 조합 중에도 종성 결합 허용 (MS윈도 호환).
    public var hangulNonChoseongCombination: Bool {
        get {
            bool(forKey: ConfigurationName.hangulNonChoseongCombination)
        }
        set {
            set(newValue, forKey: ConfigurationName.hangulNonChoseongCombination)
        }
    }

    /// 모든 글자를 조합중인 글자로 취급 (JDK 호환).
    public var hangulDeferredSymbolCommit: Bool {
        get {
            bool(forKey: ConfigurationName.hangulDeferredSymbolCommit)
        }
        set {
            set(newValue, forKey: ConfigurationName.hangulDeferredSymbolCommit)
        }
    }

    /// 세벌식 정석 강요.
    public var hangulForceStrictCombinationRule: Bool {
        get {
            bool(forKey: ConfigurationName.hangulForceStrictCombinationRule)
        }
        set {
            set(newValue, forKey: ConfigurationName.hangulForceStrictCombinationRule)
        }
    }

    /// 우측 키로 언어 전환
    public var rightToggleKey: Int {
        get {
            integer(forKey: ConfigurationName.rightToggleKey)
        }
        set {
            set(newValue, forKey: ConfigurationName.rightToggleKey)
        }
    }

    /// 인라인 직접 입력 기능 (DKST 방식 이식, MIT) 마스터 스위치.
    /// 이 값이 true일 때만 인라인 조합이 동작한다.
    public var inlineCompositionEnabled: Bool {
        get {
            bool(forKey: ConfigurationName.inlineCompositionEnabled)
        }
        set {
            set(newValue, forKey: ConfigurationName.inlineCompositionEnabled)
        }
    }

    /// 인라인 직접 입력 기능 (DKST 방식 이식, MIT) 전역 강제 옵션.
    /// true이면 모든 클라이언트에서 marked-text 방식을 사용한다.
    public var inlineCompositionAlwaysMarked: Bool {
        get {
            bool(forKey: ConfigurationName.inlineCompositionAlwaysMarked)
        }
        set {
            set(newValue, forKey: ConfigurationName.inlineCompositionAlwaysMarked)
        }
    }

    /// 인라인 직접 입력 기능에서 marked-text를 강제할 사용자 지정 번들 식별자 목록.
    /// 엔진 휴리스틱(WebKit/Chromium)보다 우선하는 사용자 명시 override다.
    public var inlineCompositionForcedMarkedBundleIDs: [String] {
        get {
            stringArray(forKey: ConfigurationName.inlineCompositionForcedMarkedBundleIDs) ?? []
        }
        set {
            set(newValue, forKey: ConfigurationName.inlineCompositionForcedMarkedBundleIDs)
        }
    }

    /// 업데이트 알림 받기
    public var updateNotification: Bool {
        get {
            bool(forKey: ConfigurationName.updateNotification)
        }
        set {
            set(newValue, forKey: ConfigurationName.updateNotification)
        }
    }

    /// 실험버전 업데이트 알림 받기
    public var updateNotificationExperimental: Bool {
        get {
            if Bundle.main.isExperimental {
                return true
            } else {
                return bool(forKey: ConfigurationName.updateNotificationExperimental)
            }
        }
        set {
            assert(!Bundle.main.isExperimental)
            set(newValue, forKey: ConfigurationName.updateNotificationExperimental)
        }
    }

    public var updateMode: UpdateMode? {
        switch (updateNotification, updateNotificationExperimental) {
        case (false, _):
            return nil
        case (true, false):
            return .Stable
        case (true, true):
            return .Experimental
        }
    }
}

private extension Configuration {
    func shortcut(forKey key: String) -> Shortcut? {
        guard let value = dictionary(forKey: key) else { return nil }
        return Configuration.convertConfigurationToShortcut(value)
    }

    func setShortcut(_ newValue: Shortcut?, forKey key: String) {
        set(Configuration.convertShortcutToConfiguration(newValue), forKey: key)
    }
}
