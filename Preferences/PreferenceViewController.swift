//
//  PreferenceViewController.swift
//  Preferences
//
//  Created by Jeong YunWon on 2017. 11. 29..
//  Copyright © 2017 youknowone.org. All rights reserved.
//

import Cocoa
import Foundation
import IOKit.hid

import MASShortcut
#if !USE_PREFPANE
    import GureumCore
#endif

@objc(PreferenceViewController)
final class PreferenceViewController: NSViewController {
    @IBOutlet private var debugButton: NSButton!
    /// 옵션 키 동작.
    @IBOutlet private var optionKeyBehaviorButton: NSPopUpButton!
    /// 기본 키보드 레이아웃.
    @IBOutlet private var overridingKeyboardNameComboBox: NSComboBoxCell!

    /// 한글 입력기일 때 역따옴표(`)로 원화 기호(₩) 입력.
    @IBOutlet private var hangulWonCurrencySymbolForBackQuoteButton: NSButton!
    /// 완성되지 않은 낱자 자동 교정 (모아치기).
    @IBOutlet private var hangulAutoReorderButton: NSButton!
    /// 두벌식 초성 조합 중에도 종성 결합 허용 (MS윈도 호환).
    @IBOutlet private var hangulNonChoseongCombinationButton: NSButton!
    /// 모든 글자를 조합중인 글자로 취급 (JDK 호환).
    @IBOutlet private var hangulDeferredSymbolCommitButton: NSButton!
    /// 세벌식 정석 강요.
    @IBOutlet private var hangulForceStrictCombinationRuleButton: NSButton!
    /// Esc 키로 로마자 자판으로 전환 (vi 모드).
    @IBOutlet private var romanModeByEscapeKeyButton: NSButton!
    /// 우측 키로 언어 전환
    @IBOutlet private var rightToggleKeyButton: NSPopUpButton!

    /// 입력기 바꾸기 단축키.
    @IBOutlet private var inputModeExchangeShortcutView: MASShortcutView!
    /// 한자 및 이모지 검색 단축키.
    @IBOutlet private var inputModeSearchShortcutView: MASShortcutView!
    /// 로마자로 바꾸기 단축키.
    @IBOutlet private var inputModeEnglishShortcutView: MASShortcutView!
    /// 한글로 바꾸기 단축키.
    @IBOutlet private var inputModeKoreanShortcutView: MASShortcutView!

    /// 업데이트 알림 받기
    @IBOutlet private var updateNotificationButton: NSButton!
    /// 실험버전 업데이트 알림 받기
    @IBOutlet private var updateNotificationExperimentalButton: NSButton!

    /// 설정 항목들이 담긴 최상위 세로 스택뷰. 인라인 직접 입력 섹션을
    /// 코드로 만들어 여기에 덧붙인다(취약한 컨트롤 XML을 xib에 추가하지 않기 위함).
    @IBOutlet private var inlineSettingsStackView: NSStackView!

    /// 강제 marked 번들 ID 편집기. textDidChange에서 식별하기 위해 참조를 보관한다.
    private weak var inlineForcedMarkedTextView: NSTextView?

    private let configuration = Configuration()
    private let pane: GureumPreferencePane! = nil
    private let shortcutValidator = GureumShortcutValidator()
    private let backgroundQueue = DispatchQueue.global(qos: .background)

    private lazy var inputSources: [(identifier: String, localizedName: String)] = {
        let abcIdentifier = "com.apple.keylayout.ABC"

        guard let rawSources = TISInputSource.sources(withProperties: [kTISPropertyInputSourceType!: kTISTypeKeyboardLayout!, kTISPropertyInputSourceIsASCIICapable!: true], includeAllInstalled: true) else {
            return []
        }

        let unsortedSources = rawSources.map { (identifier: $0.identifier, localizedName: $0.localizedName, enabled: $0.enabled) }
        let sortedSources = unsortedSources.sorted {
            if $0.identifier == abcIdentifier {
                return true
            } else if $1.identifier == abcIdentifier {
                return false
            }
            if $0.enabled != $1.enabled {
                return $0.enabled
            }
            return $0.localizedName < $1.localizedName
        }
        let sources = sortedSources.map { (identifier: $0.identifier, localizedName: $0.localizedName) }
        return sources
    }()

    override func viewDidLoad() {
        hangulWonCurrencySymbolForBackQuoteButton.state = isOn(configuration.hangulWonCurrencySymbolForBackQuote)
        romanModeByEscapeKeyButton.state = isOn(configuration.romanModeByEscapeKey)
        hangulAutoReorderButton.state = isOn(configuration.hangulAutoReorder)
        hangulNonChoseongCombinationButton.state = isOn(configuration.hangulNonChoseongCombination)
        hangulDeferredSymbolCommitButton.state = isOn(configuration.hangulDeferredSymbolCommit)
        hangulForceStrictCombinationRuleButton.state = isOn(configuration.hangulForceStrictCombinationRule)
        switch configuration.rightToggleKey {
        case kHIDUsage_KeyboardRightGUI:
            rightToggleKeyButton.selectItem(at: 1)
        case kHIDUsage_KeyboardRightAlt:
            rightToggleKeyButton.selectItem(at: 2)
        case kHIDUsage_KeyboardRightControl:
            rightToggleKeyButton.selectItem(at: 3)
        default:
            rightToggleKeyButton.selectItem(at: 0)
        }
        if (0 ..< optionKeyBehaviorButton.numberOfItems).contains(configuration.optionKeyBehavior) {
            optionKeyBehaviorButton.selectItem(at: configuration.optionKeyBehavior)
        }

        overridingKeyboardNameComboBox.reloadData()
        if let selectedIndex = inputSources.firstIndex(where: { $0.identifier == configuration.overridingKeyboardName }) {
            overridingKeyboardNameComboBox.selectItem(at: selectedIndex)
        }

        inputModeExchangeShortcutView.shortcutValidator = shortcutValidator
        inputModeSearchShortcutView.shortcutValidator = shortcutValidator
        inputModeEnglishShortcutView.shortcutValidator = shortcutValidator
        inputModeKoreanShortcutView.shortcutValidator = shortcutValidator

        loadShortcutValues()
        setupShortcutViewValueChangeEvents()

        updateNotificationButton.state = isOn(configuration.updateNotification)
        if Bundle.main.isExperimental {
            updateNotificationExperimentalButton.state = .on
            updateNotificationExperimentalButton.isEnabled = false
        } else {
            updateNotificationExperimentalButton.state = isOn(configuration.updateNotificationExperimental)
        }

        #if DEBUG
            debugButton.isHidden = false
        #endif

        setupInlineDirectInputSection()
    }

    private func runAppleScript(_ script: String) {
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: script) {
            let output: NSAppleEventDescriptor = scriptObject.executeAndReturnError(
                &error
            )
            print("pref event descriptor: \(output.stringValue ?? "nil")")
        }
    }

    // MARK: IBAction

    @IBAction private func debug(sender _: NSControl) {
        print("killing myself")
        let x = [0]
        _ = x[1]
    }

    @IBAction private func openKeyboardShortcutsPreference(sender _: NSControl) {
        if #available(OSX 13, *) {
            runAppleScript("""
                do shell script "open -b com.apple.systempreferences /System/Library/PreferencePanes/Keyboard.prefPane"
            """)
        } else {
            runAppleScript("""
                tell application "System Preferences"
                    activate
                    reveal anchor "ShortcutsTab" of pane id "com.apple.preference.keyboard"
                end tell
            """)
        }
    }

    @IBAction private func openKeyboardInputSourcesPreference(sender _: NSControl) {
        if #available(OSX 13, *) {
            runAppleScript("""
                do shell script "open -b com.apple.systempreferences /System/Library/PreferencePanes/Keyboard.prefPane"
            """)
        } else {
            runAppleScript("""
                tell application "System Preferences"
                    activate
                    reveal anchor "InputSources" of pane id "com.apple.preference.keyboard"
                end tell
            """)
        }
    }

    @IBAction private func openInputMonitoringPreference(sender _: NSControl) {
        if #available(OSX 13, *) {
            runAppleScript("""
                do shell script "open x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
            """)
        } else {
            runAppleScript("""
                tell application "System Preferences"
                    activate
                    reveal anchor "Privacy" of pane id "com.apple.preference.security"
                end tell
            """)
        }
    }

    @IBAction private func updateCheck(sender _: NSControl) {
        updateCheck()
    }

    @IBAction private func optionKeyBehaviorValueChanged(_ sender: NSPopUpButton) {
        configuration.optionKeyBehavior = sender.indexOfSelectedItem
    }

    @IBAction private func overridingKeyboardNameComboBoxValueChanged(_ sender: NSComboBox) {
        guard (0 ..< inputSources.count).contains(sender.indexOfSelectedItem) else {
            return
        }
        configuration.overridingKeyboardName = inputSources[sender.indexOfSelectedItem].identifier
    }

    @IBAction private func romanModeByEscapeKeyValueChanged(_ sender: NSButton) {
        configuration.romanModeByEscapeKey = sender.state == .on
    }

    @IBAction private func hangulWonCurrencySymbolForBackQuoteValueChanged(_ sender: NSButton) {
        configuration.hangulWonCurrencySymbolForBackQuote = sender.state == .on
    }

    @IBAction private func hangulAutoReorderValueChanged(_ sender: NSButton) {
        configuration.hangulAutoReorder = sender.state == .on
    }

    @IBAction private func hangulNonChoseongCombinationValueChanged(_ sender: NSButton) {
        configuration.hangulNonChoseongCombination = sender.state == .on
    }

    @IBAction private func hangulDeferredSymbolCommitValueChanged(_ sender: NSButton) {
        configuration.hangulDeferredSymbolCommit = sender.state == .on
    }

    @IBAction private func hangulForceStrictCombinationRuleValueChanged(_ sender: NSButton) {
        configuration.hangulForceStrictCombinationRule = sender.state == .on
    }

    @IBAction private func rightToggleKeyValueChanged(_ sender: NSPopUpButton) {
        configuration.rightToggleKey = {
            switch sender.indexOfSelectedItem {
            case 1:
                return kHIDUsage_KeyboardRightGUI
            case 2:
                return kHIDUsage_KeyboardRightAlt
            case 3:
                return kHIDUsage_KeyboardRightControl
            default:
                return 0
            }
        }()
    }

    @IBAction private func updateNotificationValueChanged(_ sender: NSButton) {
        configuration.updateNotification = sender.state == .on
        if !Bundle.main.isExperimental {
            updateNotificationExperimentalButton.isEnabled = sender.state == .on
        }
        backgroundQueue.async {
            self.updateCheck()
        }
    }

    @IBAction private func updateNotificationExperimentalValueChanged(_ sender: NSButton) {
        configuration.updateNotificationExperimental = sender.state == .on
        backgroundQueue.async {
            self.updateCheck()
        }
    }

    // MARK: 인라인 직접 입력 (프로그램적으로 구성한 컨트롤의 액션)

    @objc private func inlineCompositionEnabledValueChanged(_ sender: NSButton) {
        configuration.inlineCompositionEnabled = sender.state == .on
    }

    @objc private func inlineCompositionAlwaysMarkedValueChanged(_ sender: NSButton) {
        configuration.inlineCompositionAlwaysMarked = sender.state == .on
    }
}

// MARK: - 비공개 메소드

private extension PreferenceViewController {
    func isOn(_ value: Bool) -> NSButton.StateValue {
        return value ? .on : .off
    }

    /// 인라인 직접 입력 설정 섹션을 코드로 구성해 설정 스택뷰에 덧붙인다.
    /// xib에는 스택뷰 outlet 한 줄만 추가하고, 컨트롤은 전부 여기서 만든다.
    func setupInlineDirectInputSection() {
        guard let stack = inlineSettingsStackView else {
            return
        }

        let header = makeSectionLabel("인라인 직접 입력 (실험적)")

        let enabledCheckbox = makeCheckbox(
            title: "인라인 직접 입력 사용 (밑줄 없는 조합)",
            state: isOn(configuration.inlineCompositionEnabled),
            action: #selector(inlineCompositionEnabledValueChanged(_:))
        )

        let alwaysMarkedCheckbox = makeCheckbox(
            title: "항상 밑줄 조합(marked text) 사용",
            state: isOn(configuration.inlineCompositionAlwaysMarked),
            action: #selector(inlineCompositionAlwaysMarkedValueChanged(_:))
        )

        let listLabel = makeHelpLabel("밑줄 조합(marked)을 강제할 앱 (번들 ID, 한 줄에 하나):")

        let scrollView = NSTextView.scrollableTextView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.borderType = .bezelBorder
        scrollView.hasVerticalScroller = true
        if let textView = scrollView.documentView as? NSTextView {
            textView.isRichText = false
            textView.font = NSFont.userFixedPitchFont(ofSize: 11) ?? NSFont.systemFont(ofSize: 11)
            textView.isAutomaticQuoteSubstitutionEnabled = false
            textView.isAutomaticDashSubstitutionEnabled = false
            textView.isAutomaticSpellingCorrectionEnabled = false
            textView.isAutomaticTextReplacementEnabled = false
            textView.delegate = self
            textView.string = formatForcedMarkedBundleIDList(configuration.inlineCompositionForcedMarkedBundleIDs)
            inlineForcedMarkedTextView = textView
        }
        NSLayoutConstraint.activate([
            scrollView.heightAnchor.constraint(equalToConstant: 84),
            scrollView.widthAnchor.constraint(greaterThanOrEqualToConstant: 320),
        ])

        let helpLabel = makeHelpLabel("Safari·Chrome 등 브라우저는 자동 판정됩니다. 조합이 깨지는 앱을 여기에 추가하세요. (인라인 사용이 켜져 있을 때만 적용)")

        let section = NSStackView(views: [header, enabledCheckbox, alwaysMarkedCheckbox, listLabel, scrollView, helpLabel])
        section.orientation = .vertical
        section.alignment = .leading
        section.spacing = 8
        section.translatesAutoresizingMaskIntoConstraints = false

        stack.addArrangedSubview(section)
    }

    func makeSectionLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    func makeHelpLabel(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        label.preferredMaxLayoutWidth = 360
        return label
    }

    func makeCheckbox(title: String, state: NSButton.StateValue, action: Selector) -> NSButton {
        let button = NSButton(checkboxWithTitle: title, target: self, action: action)
        button.state = state
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    func loadShortcutValues() {
        if let key = configuration.inputModeExchangeKey {
            inputModeExchangeShortcutView.shortcutValue = MASShortcut(keyCode: key.0.rawValue, modifierFlags: key.1)
        } else {
            inputModeExchangeShortcutView.shortcutValue = nil
        }

        if let key = configuration.inputModeSearchKey {
            inputModeSearchShortcutView.shortcutValue = MASShortcut(keyCode: key.0.rawValue, modifierFlags: key.1)
        } else {
            inputModeSearchShortcutView.shortcutValue = nil
        }

        if let key = configuration.inputModeEnglishKey {
            inputModeEnglishShortcutView.shortcutValue = MASShortcut(keyCode: key.0.rawValue, modifierFlags: key.1)
        } else {
            inputModeEnglishShortcutView.shortcutValue = nil
        }

        if let key = configuration.inputModeKoreanKey {
            inputModeKoreanShortcutView.shortcutValue = MASShortcut(keyCode: key.0.rawValue, modifierFlags: key.1)
        } else {
            inputModeKoreanShortcutView.shortcutValue = nil
        }
    }

    func setupShortcutViewValueChangeEvents() {
        func masShortcutToShortcut(_ mas: MASShortcut?) -> Configuration.Shortcut? {
            guard let mas = mas, let keyCode = KeyCode(rawValue: mas.keyCode) else { return nil }
            return (keyCode, mas.modifierFlags)
        }
        inputModeExchangeShortcutView.shortcutValueChange = { sender in
            self.configuration.inputModeExchangeKey = masShortcutToShortcut(sender.shortcutValue)
        }

        inputModeSearchShortcutView.shortcutValueChange = { sender in
            self.configuration.inputModeSearchKey = masShortcutToShortcut(sender.shortcutValue)
        }

        inputModeEnglishShortcutView.shortcutValueChange = { sender in
            self.configuration.inputModeEnglishKey = masShortcutToShortcut(sender.shortcutValue)
        }

        inputModeKoreanShortcutView.shortcutValueChange = { sender in
            self.configuration.inputModeKoreanKey = masShortcutToShortcut(sender.shortcutValue)
        }
    }

    func updateCheck() {
        #if !USE_PREFPANE
            UpdateManager.shared.requestAutoUpdateVersionInfo { info in
                guard let info = info else {
                    return
                }
                UpdateManager.notifyUpdate(info: info)
            }
        #endif
    }
}

// MARK: - NSComboBoxDataSource 구현

extension PreferenceViewController: NSComboBoxDataSource {
    func numberOfItems(in _: NSComboBox) -> Int {
        return inputSources.count
    }

    func comboBox(_: NSComboBox, objectValueForItemAt index: Int) -> Any? {
        return inputSources[index].localizedName
    }

    func comboBox(_: NSComboBox, indexOfItemWithStringValue string: String) -> Int {
        return inputSources.firstIndex(where: { $0.localizedName == string }) ?? NSNotFound
    }

    func comboBox(_: NSComboBox, completedString string: String) -> String? {
        for source in inputSources {
            if source.localizedName.starts(with: string) {
                return source.localizedName
            }
        }
        overridingKeyboardNameComboBox.stringValue = ""
        return ""
    }
}

// MARK: - NSTextViewDelegate (강제 marked 번들 ID 편집기)

extension PreferenceViewController: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView,
              textView === inlineForcedMarkedTextView
        else {
            return
        }
        // 편집 중에는 정규화된 값만 저장하고 편집기 텍스트는 그대로 둔다
        // (입력 도중 재포맷하면 커서/타이핑이 깨지므로). 다음 열람 시 정규화 표시.
        configuration.inlineCompositionForcedMarkedBundleIDs = parseForcedMarkedBundleIDList(textView.string)
    }
}
