//
//  InputController.swift
//  Gureum
//
//  Created by KMLee on 2018. 9. 12..
//  Copyright © 2018 youknowone.org. All rights reserved.
//

import Foundation
import InputMethodKit

let DEBUG_LOGGING = false
let DEBUG_INPUTCONTROLLER = false
let DEBUG_SPYING = true

/*!
 @enum
 @brief  최종적으로 InputController가 처리할 결과
 */

public enum InputAction: Equatable {
    case none
    case commit
    case cancel
    case layout(String)
    case candidatesEvent(KeyCode) // keyCode
}

struct InputResult: Equatable {
    let processed: Bool
    let action: InputAction

    static let processed = InputResult(processed: true, action: .none)
    static let notProcessed = InputResult(processed: false, action: .none)
}

enum ChangeLayout {
    case toggle
    case toggleByCapsLock
    case toggleByRightKey
    case hangul
    case roman
    case search
}

enum InputEvent {
    case changeLayout(ChangeLayout, Bool)
}

@objc(GureumInputController)
public class InputController: IMKInputController {
    var receiver: InputReceiver!
    var lastFlags = NSEvent.ModifierFlags(rawValue: 0)
    var updating = false

    // MARK: - inline-direct-input state (DKST-style port, MIT)

    /// Document range currently holding the in-progress composedString in inline mode.
    /// nil = nothing is inline-composing.
    var directRange: NSRange?
    /// The text currently occupying `directRange` in inline mode; used to validate the
    /// range still holds the previous composedString before replacing it.
    var directText: String = ""
    /// Per-client composition policy. Default true = safe (marked) fallback until computed.
    var useMarkedText = true

    /// 직전 인라인 렌더 직후의 기대 caret(selectedRange.location), 즉 directRange의 끝.
    /// ② 커서이동 무효화가 사용한다. nil = 추적 안 함.
    var expectedCaret: Int?

    /// Port of DKST `directInputRangeIsCurrent:` — confirms `range` in `client` still holds `expected`.
    func directRangeIsCurrent(_ expected: String, range: NSRange, client: (IMKTextInput & IMKUnicodeTextInput)) -> Bool {
        if range.location == NSNotFound || range.length == 0 || expected.isEmpty || (expected as NSString).length != range.length {
            return false
        }
        return client.attributedSubstring(from: range)?.string == expected
    }

    // MARK: - PHASE 2 B층: 런타임 append-only 학습 캐시 (세션 한정)

    /// 사후 검증에서 append-only로 판명된 클라이언트의 번들 식별자 집합. IMK 이벤트는
    /// 메인 스레드에서만 처리되므로 별도 동기화 없이 안전하다. 프로세스 생명주기 한정
    /// (영구화는 후속 과제).
    private static var learnedAppendOnlyCache: Set<String> = []

    /// 사후 검증에서 append-only로 판명된 클라이언트를 기록한다(빈 식별자는 무시).
    static func recordLearnedAppendOnly(bundleID: String) {
        guard !bundleID.isEmpty else { return }
        learnedAppendOnlyCache.insert(bundleID)
    }

    /// 주어진 번들 식별자가 append-only로 학습됐는지.
    static func isLearnedAppendOnly(bundleID: String) -> Bool {
        learnedAppendOnlyCache.contains(bundleID)
    }

    /// 테스트 격리용: 학습 캐시를 비운다.
    static func resetLearnedAppendOnlyCache() {
        learnedAppendOnlyCache.removeAll()
    }

    override init!(server: IMKServer, delegate: Any!, client inputClient: Any) {
        super.init(server: server, delegate: delegate, client: inputClient)
        guard let inputClient = inputClient as? (IMKTextInput & IMKUnicodeTextInput) else {
            return nil
        }
        dlog(DEBUG_INPUTCONTROLLER, "**** NEW INPUT CONTROLLER INIT **** WITH SERVER: \(server) / DELEGATE: \(String(describing: delegate)) / CLIENT: \(inputClient) \(inputClient.bundleIdentifier() ?? "nil")")
        assert(InputMethodServer.shared.server === server)
        receiver = InputReceiver(server: server, delegate: delegate, client: inputClient, controller: self)
    }

    override init() {
        super.init()
    }

    override public func inputControllerWillClose() {
        super.inputControllerWillClose()
    }

    func asClient(_ sender: Any!) -> IMKTextInput & IMKUnicodeTextInput {
        #if DEBUG
            return sender as! (IMKTextInput & IMKUnicodeTextInput)
        #else
            guard let sender = sender as? (IMKTextInput & IMKUnicodeTextInput) else {
                return client() as! (IMKTextInput & IMKUnicodeTextInput)
            }
            return sender
        #endif
    }

    #if DEBUG
        override public func responds(to aSelector: Selector) -> Bool {
            let r = super.responds(to: aSelector)
            dlog(DEBUG_SPYING, "controller responds to: \(aSelector) \(r)")
            return r
        }

        override public func modes(_ sender: Any!) -> [AnyHashable: Any]! {
            let modes = super.modes(sender)
            dlog(DEBUG_SPYING, "modes: \(String(describing: modes))")
            return modes
        }

        override public func value(forTag tag: Int, client _: Any!) -> Any! {
            let v = super.value(forTag: tag, client: client)
            dlog(DEBUG_SPYING, "value: \(String(describing: v)) for tag: \(tag)")
            return v
        }
    #endif
}

// MARK: - Live ClientCapabilities adapter (inline-direct-input, DKST-style port, MIT)

/// 라이브 IMK 컨트롤러/클라이언트로 뒷받침되는 구체적인 `ClientCapabilities`.
///
/// `InlineComposition.swift`는 순수하게 유지하기 위해 IMK를 import하지 않으므로,
/// IMK에 의존하는 이 어댑터는 (이미 InputMethodKit을 import하는) 이 파일에 둔다.
///
/// - Note: `IMKTextInput & IMKUnicodeTextInput` 프로토콜 합성 타입은
///   `NSObjectProtocol`(`responds(to:)`, `perform(...)`, `value(forKey:)`)를
///   노출하지 않는다. 따라서 동적 호출은 모두 `(x as? NSObject)`로 캐스팅해
///   수행한다. 반면 `selectedRange()`/`bundleIdentifier()`는 직접 프로토콜
///   메서드이므로 그대로 호출한다.
struct LiveClientCapabilities: ClientCapabilities {
    weak var controller: IMKInputController?
    let client: (IMKTextInput & IMKUnicodeTextInput)

    var alwaysMarkedGlobal: Bool { Configuration.shared.inlineCompositionAlwaysMarked }

    /// 호스트 앱의 번들 식별자. (P2의 blocklist/WebKit/Chromium 판정에서 소비)
    var bundleIdentifier: String? { client.bundleIdentifier() }

    /// DKST `InputController.m:848-874` 포팅.
    ///
    /// IMK textDocument 프록시를 먼저, 그다음 클라이언트를 대상으로 비공개
    /// 셀렉터 `showsComposingTextAsMarkedText`를 동적으로 질의한다. 두 객체
    /// 모두 응답하지 않으면 `nil`을 반환해 정책 체인이 다음 단계로 떨어지도록
    /// 한다(임의의 기본값으로 합치지 않는다).
    func showsComposingTextAsMarkedText() -> Bool? {
        let selectorName = "showsComposingTextAsMarkedText"
        let selector = NSSelectorFromString(selectorName)

        // 1. textDocument 프록시에 먼저 질의한다.
        if let textDocument = resolveTextDocument(),
           textDocument.responds(to: selector),
           let value = textDocument.value(forKey: selectorName) as? Bool
        {
            return value
        }

        // 2. 클라이언트에 직접 질의한다.
        if let clientObject = client as? NSObject,
           clientObject.responds(to: selector),
           let value = clientObject.value(forKey: selectorName) as? Bool
        {
            return value
        }

        // 3. 둘 다 응답하지 않음 → 알 수 없음.
        return nil
    }

    /// DKST `InputController.m:899-911` 포팅.
    ///
    /// `client.selectedRange()`는 직접 프로토콜 메서드이지만, 방어적으로
    /// `(client as? NSObject)?.responds(to:)`로 응답 가능 여부를 먼저 확인한 뒤
    /// 호출한다. 어떤 이유로든 실패하면 `false`를 반환한다.
    func selectedRangeIsQueryable() -> Bool {
        guard let clientObject = client as? NSObject,
              clientObject.responds(to: NSSelectorFromString("selectedRange"))
        else {
            return false
        }
        return client.selectedRange().location != NSNotFound
    }

    /// 사용자가 지정한 강제 marked 번들 식별자 목록. (Configuration에서 읽음)
    var forcedMarkedBundleIDs: [String] {
        Configuration.shared.inlineCompositionForcedMarkedBundleIDs
    }

    /// DKST `runningApplicationUsesChromiumTextStack:` (InputController.m:515) 포팅.
    ///
    /// 호스트 앱의 `.app/Contents/Frameworks`를 스캔해 Chromium/Electron
    /// 텍스트 스택 여부를 판정한다. 입력 hot-path에서 매번 디스크를 두드리지
    /// 않도록 결과(YES/NO 모두)를 번들 식별자별로 캐시한다.
    func usesChromiumFrameworkTextStack() -> Bool {
        guard let bundleID = bundleIdentifier, !bundleID.isEmpty else {
            return false
        }
        return LiveClientCapabilities.chromiumTextStack(forBundleID: bundleID)
    }

    /// 런타임 학습 캐시에서 이 클라이언트(번들 식별자)가 append-only로 판명됐는지 조회.
    func learnedAppendOnly() -> Bool {
        guard let bundleID = bundleIdentifier, !bundleID.isEmpty else {
            return false
        }
        return InputController.isLearnedAppendOnly(bundleID: bundleID)
    }

    /// 컨트롤러의 `textDocument` 프록시를 동적으로 얻는다.
    ///
    /// 컨트롤러를 `NSObject`로 캐스팅한 뒤 `textDocument` 셀렉터에 응답할 때에만
    /// `perform(...)`으로 시도한다. 응답하지 않으면 `nil`을 반환한다. KVC
    /// `value(forKey:)` 폴백은 비-KVC 객체에서 `NSUnknownKeyException`을 일으켜
    /// (Swift에서 잡을 수 없어) 크래시를 내므로 사용하지 않는다.
    private func resolveTextDocument() -> NSObject? {
        guard let controllerObject = controller as? NSObject else {
            return nil
        }
        let selector = NSSelectorFromString("textDocument")
        guard controllerObject.responds(to: selector) else {
            return nil
        }
        return controllerObject.perform(selector)?.takeUnretainedValue() as? NSObject
    }

    // MARK: - Chromium 텍스트 스택 감지 (DKST 포팅, 디스크 스캔 + 캐시)

    /// 번들 식별자별 Chromium 감지 결과 캐시. IMK 이벤트는 메인 스레드에서만
    /// 처리되므로 별도 동기화 없이 안전하다.
    private static var chromiumDetectionCache: [String: Bool] = [:]

    /// 알려진 Chromium/Electron 프레임워크 디렉터리 이름들.
    private static let chromiumFrameworkNames: Set<String> = [
        "Electron Framework.framework",
        "Chromium Embedded Framework.framework",
        "Google Chrome Framework.framework",
        "Microsoft Edge Framework.framework",
        "Brave Browser Framework.framework",
        "Vivaldi Framework.framework",
        "Opera Framework.framework",
    ]

    /// DKST `runningApplicationUsesChromiumTextStack:` 본체. 캐시 미스 시
    /// 실행 중인 동일 번들 앱들을 열거해 이름/프레임워크를 검사하고 결과를 캐시한다.
    private static func chromiumTextStack(forBundleID bundleID: String) -> Bool {
        if let cached = chromiumDetectionCache[bundleID] {
            return cached
        }

        var result = false
        let chromiumNames: Set<String> = ["comet", "atlas", "chatgpt atlas"]
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) {
            let appName = (app.localizedName ?? "").lowercased()
            let bundleName = app.bundleURL?.deletingPathExtension().lastPathComponent.lowercased() ?? ""
            if chromiumNames.contains(appName) || chromiumNames.contains(bundleName) {
                result = true
                break
            }
            if let url = app.bundleURL, bundleUsesChromiumFrameworks(at: url) {
                result = true
                break
            }
        }

        chromiumDetectionCache[bundleID] = result
        return result
    }

    /// DKST `applicationBundleUsesChromiumTextStack:` 포팅. `.app` 번들의
    /// `Contents/Frameworks`에 Chromium/Electron 프레임워크가 있는지 검사한다.
    private static func bundleUsesChromiumFrameworks(at bundleURL: URL) -> Bool {
        let frameworksURL = bundleURL.appendingPathComponent("Contents/Frameworks", isDirectory: true)
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: frameworksURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              let names = try? fileManager.contentsOfDirectory(atPath: frameworksURL.path)
        else {
            return false
        }

        for name in names {
            if chromiumFrameworkNames.contains(name) {
                return true
            }
            if name.range(of: "Chromium", options: .caseInsensitive) != nil
                || name.range(of: "Electron", options: .caseInsensitive) != nil
            {
                return true
            }
        }
        return false
    }
}

// IMKServerInputTextData, IMKServerInputHandleEvent, IMKServerInputKeyBinding 중 하나를 구현하여 입력 구현
public extension InputController { // IMKServerInputHandleEvent
    // Receiving Events Directly from the Text Services Manager

    override func handle(_ event: NSEvent, client sender: Any) -> Bool {
        // dlog(DEBUG_INPUTCONTROLLER, "event: \(event)")
        // sender is (IMKTextInput & IMKUnicodeTextInput & IMTSMSupport)
        let client = asClient(sender)

        switch event.type {
        case .keyDown:
            guard let keyCode = KeyCode(rawValue: Int(event.keyCode)) else {
                return false
            }

            dlog(DEBUG_INPUTCONTROLLER, "** InputController KEYDOWN -handleEvent:client: with event: %@ / key: %d / modifier: %lu / chars: %@ / chars ignoreMod: %@ / client: %@", event, event.keyCode, event.modifierFlags.rawValue, event.characters ?? "(empty)", event.charactersIgnoringModifiers ?? "(empty)", client.bundleIdentifier() ?? "(no client bundle)")

            let imkCandidates = InputMethodServer.shared.candidates
            if imkCandidates.isVisible() {
                let selectionKeys = imkCandidates.selectionKeys() as? [NSNumber] ?? []
                let arrowModifier = NSEvent.ModifierFlags.numericPad.union(.function)
                let emptyModifier = NSEvent.ModifierFlags(rawValue: 0)

                let inputModifier = event.modifierFlags
                    .intersection(.deviceIndependentFlagsMask)
                    .subtracting(.capsLock)

                if inputModifier == arrowModifier && KeyCode.arrows.contains(keyCode) || inputModifier == emptyModifier && (keyCode == .return || selectionKeys.contains(NSNumber(value: event.keyCode))) {
                    // https://github.com/pkamb/NumberInput_IMKit_Sample/issues/1#issuecomment-633264470
                    imkCandidates.perform(Selector(("handleKeyboardEvent:")), with: event)
                    return true
                }
            }

            let result = receiver.input(text: event.characters, key: keyCode, modifiers: event.modifierFlags, client: client)
            dlog(DEBUG_LOGGING, "LOGGING::PROCESSED::\(result)")
            return result.processed
        case .flagsChanged:
            dlog(DEBUG_INPUTCONTROLLER, "** InputController FLAGCHANGED -handleEvent:client: with event: %@ / key: %d / modifier: %lu / client: %@", event, -1, event.modifierFlags.rawValue, client.bundleIdentifier() ?? "(no client bundle)")
            let changed = lastFlags.symmetricDifference(event.modifierFlags)
            lastFlags = event.modifierFlags

            if changed.contains(.capsLock), Configuration.shared.enableCapslockToToggleInputMode {
                if InputMethodServer.shared.io?.capsLockTriggered == true {
                    dlog(DEBUG_IOKIT_EVENT, "controller detected capslock to change layout")
                    let toggle = { [weak self] in _ = self?.receiver.input(event: .changeLayout(.toggleByCapsLock, true), client: client) }
                    toggle()
                    InputMethodServer.shared.io?.rollback = toggle
                } else {
                    dlog(DEBUG_IOKIT_EVENT, "controller detected capslock")
                    (sender as! IMKTextInput).selectMode(receiver.composer.inputMode)
                }
            }

            // 우측 토글 키(한/영) 감지.
            // 전역 IOHIDManager 모니터(IOKitty)는 다른 프로세스가 켠 secure input이
            // 입력 모니터링을 차단하면 키를 놓친다(한글은 입력되는데 한/영 전환만
            // 간헐적으로 먹통 — 다른 곳 클릭하면 복구되는 증상). 그래서 IME 자신이
            // 받는 이 flagsChanged 이벤트의 device-dependent 비트로 먼저 판정하고,
            // IOKitty 경로는 device 비트가 전달되지 않는 환경용 폴백으로만 둔다.
            let toggleUsage = Configuration.shared.rightToggleKey
            let toggleMask = deviceModifierMask(forKeyboardUsage: toggleUsage)
            let toggleKeyInvolved = toggleMask != 0 && (changed.rawValue & toggleMask) != 0
            if toggleKeyInvolved {
                // 이 경로가 권위를 가지므로, IOKitty가 뒤늦게 세팅한 플래그가
                // 다음 이벤트에서 중복 토글을 일으키지 않도록 소거한다.
                let iokitHadFlag = InputMethodServer.shared.io?.resolveRightKeyPressed() == true
                if rightToggleKeyDidPress(changed: changed.rawValue,
                                          current: event.modifierFlags.rawValue,
                                          toggleKeyUsage: toggleUsage)
                {
                    if !iokitHadFlag {
                        // 진단: 예전이라면 IOKitty가 키를 못 잡아 먹통이었을 순간을
                        // device-flag 경로가 살렸음을 기록한다(저빈도, 추후 제거 가능).
                        NSLog("bomi-input: right toggle handled via device flags while IOKitty had no event (secure input?)")
                    }
                    let result = receiver.input(event: .changeLayout(.toggleByRightKey, true), client: client)
                    dlog(DEBUG_IOKIT_EVENT, "controller detected right toggle key via device flags")
                    return result.processed
                }
                return false
            }

            if InputMethodServer.shared.io?.resolveRightKeyPressed() == true {
                let result = receiver.input(event: .changeLayout(.toggleByRightKey, true), client: client)
                dlog(DEBUG_IOKIT_EVENT, "controller detected right key (iokit fallback)")
                return result.processed
            }

            dlog(DEBUG_LOGGING, "LOGGING::UNHANDLED::%@/%@", event, sender as! NSObject)
            dlog(DEBUG_INPUTCONTROLLER, "** InputController -handleEvent:client: with event: %@ / sender: %@", event, sender as! NSObject)
            return false
        case .leftMouseDown, .leftMouseUp, .leftMouseDragged, .rightMouseDown, .rightMouseUp, .rightMouseDragged:
            commitComposition(sender)
        default:
            dlog(DEBUG_SPYING, "unhandled event: \(event)")
        }
        return false
    }
}

/*
 extension InputController { // IMKServerInputTextData
 override func inputText(_ string: String!, key keyCode: Int, modifiers flags: Int, client sender: Any) -> Bool {
 dlog(DEBUG_INPUTCONTROLLER, "** InputController -inputText:key:modifiers:client  with string: %@ / keyCode: %ld / modifier flags: %lu / client: %@", string, keyCode, flags, client()?.bundleIdentifier() ?? "nil")
 let processed = receiver.input(controller: self, inputText: string, key: keyCode, modifiers: NSEvent.ModifierFlags(rawValue: UInt(flags)), client: sender).rawValue > CIMInputTextProcessResult.notProcessed.rawValue
 return processed
 }
 }
 */
/*
 extension InputController { // IMKServerInputKeyBinding
 override func inputText(_: String!, client _: Any) -> Bool {
 // dlog(DEBUG_INPUTCONTROLLER, "** InputController -inputText:client: with string: %@ / client: %@", string, sender)
 return false
 }

 override func didCommand(by _: Selector!, client _: Any) -> Bool {
 // dlog(DEBUG_INPUTCONTROLLER, "** InputController -didCommandBySelector: with selector: %@", aSelector)
 return false
 }
 }
 */

public extension InputController { // IMKStateSetting
    //! @brief  마우스 이벤트를 잡을 수 있게 한다.
    override func recognizedEvents(_ sender: Any!) -> Int {
        let client = asClient(sender)
        return Int(receiver.recognizedEvents(client).rawValue)
    }

    //! @brief 자판 전환을 감지한다.
    override func setValue(_ value: Any, forTag tag: Int, client sender: Any) {
        let client = asClient(sender)
        receiver.setValue(value, forTag: tag, client: client)
    }

    override func activateServer(_ sender: Any!) {
        dlog(true, "server activated")
        super.activateServer(sender)
        // 클라이언트 활성화 시 합성 표시 방식을 한 번 계산해 캐시한다.
        // (DKST처럼 클라이언트 단위로 캐시 — 키 입력마다 비공개 API를 질의하지 않는다.)
        let client = asClient(sender)
        useMarkedText = classifyComposition(LiveClientCapabilities(controller: self, client: client)) == .marked
    }

    override func deactivateServer(_ sender: Any!) {
        dlog(true, "server deactivating")
        if responds(to: #selector(commitComposition(_:))) {
            self.commitComposition(sender)
        }
        directRange = nil
        directText = ""
        expectedCaret = nil
        super.deactivateServer(sender)
    }
}

public extension InputController { // IMKMouseHandling
    /*!
     @brief  마우스 입력 발생을 커서 옮기기로 간주하고 조합 중지. 만일 마우스 입력 발생을 감지하는 대신 커서 옮기기를 직접 알아낼 수 있으면 이 부분은 제거한다.
     */
    override func mouseDown(onCharacterIndex _: Int, coordinate _: NSPoint, withModifier _: Int, continueTracking _: UnsafeMutablePointer<ObjCBool>!, client sender: Any) -> Bool {
        dlog(DEBUG_LOGGING, "LOGGING::EVENT::MOUSEDOWN")
        commitComposition(sender)
        return false
    }
}

public extension InputController { // IMKCustomCommands
    override func menu() -> NSMenu! {
        return (NSApplication.shared.delegate! as! GureumApplicationDelegate).menu
    }
}

public extension InputController { // IMKServerInput
    // Committing a Composition
    // 조합을 중단하고 현재까지 조합된 글자를 커밋한다.
    @objc override func commitComposition(_ sender: Any!) {
        let client = asClient(sender)
        dlog(DEBUG_LOGGING, "LOGGING::EVENT::COMMIT-RAW?")
        _ = receiver.commitCompositionEvent(client)
        // super.commitComposition(sender)
    }

    @objc override func updateComposition() {
        dlog(DEBUG_LOGGING, "LOGGING::EVENT::UPDATE-RAW?")
        dlog(DEBUG_INPUTCONTROLLER, "** InputController -updateComposition")
        receiver.updateCompositionEvent()
        super.updateComposition()
        dlog(DEBUG_INPUTCONTROLLER, "** InputController -updateComposition ended")
    }

    @objc override func cancelComposition() {
        dlog(DEBUG_LOGGING, "LOGGING::EVENT::CANCEL-RAW?")
        receiver.cancelCompositionEvent()
        directRange = nil
        directText = ""
        expectedCaret = nil
        super.cancelComposition()
    }

    // Getting Input Strings and Candidates
    // 현재 입력 중인 글자를 반환한다. -updateComposition: 이 사용
    @objc override func composedString(_ sender: Any!) -> Any {
        let client = asClient(sender)
        return receiver.composedString(client)
    }

    @objc override func originalString(_ sender: Any!) -> NSAttributedString {
        let client = asClient(sender)
        return receiver.originalString(client)
    }

    @objc override func candidates(_ sender: Any!) -> [Any]! {
        let client = asClient(sender)
        return receiver.candidates(client)
    }

    @objc override func candidateSelected(_ candidateString: NSAttributedString!) {
        receiver.candidateSelected(candidateString)
    }

    @objc override func candidateSelectionChanged(_ candidateString: NSAttributedString!) {
        receiver.candidateSelectionChanged(candidateString)
    }
}

#if DEBUG
    @objcMembers public class MockInputController: InputController {
        override public init(server: IMKServer, delegate: Any!, client: Any) {
            super.init()
            receiver = InputReceiver(server: server, delegate: delegate, client: client as! (IMKTextInput & IMKUnicodeTextInput), controller: self)
        }

        func repoduceTextLog(_ text: String) throws {
            for row in text.components(separatedBy: "\n") {
                guard let regex = try? NSRegularExpression(pattern: "LOGGING::([A-Z]+)::(.*)", options: []) else {
                    throw NSException(name: NSExceptionName("MockInputControllerLogParserError"), reason: "Log is not readable format", userInfo: nil) as! Error
                }
                let matches = regex.matches(in: row, options: [], range: NSRangeFromString(row))
                let type = matches[1]
                let data = matches[2]
                print("test: \(type) \(data)")
            }
        }

        override public func client() -> (IMKTextInput & NSObjectProtocol)! {
            return receiver.inputClient as? (IMKTextInput & NSObjectProtocol)
        }

        override public func selectionRange() -> NSRange {
            return client().selectedRange()
        }
    }

    public extension MockInputController { // IMKServerInputTextData
        func inputFlags(_: Int, client sender: Any) -> Bool {
            let client = asClient(sender)
            let result = receiver.input(event: .changeLayout(.toggle, true), client: client)
            if !result.processed {
                // [self cancelComposition]
            }
            return result.processed
        }

        override func inputText(_ string: String!, key keyCode: Int, modifiers flags: Int, client sender: Any) -> Bool {
            let client = asClient(sender)
            print("** InputController -inputText:key:modifiers:client  with string: \(string ?? "(nil)") / keyCode: \(keyCode) / modifier flags: \(flags) / client: \(String(describing: client))")
            guard let key = KeyCode(rawValue: keyCode) else { return false }
            let result = receiver.input(text: string, key: key, modifiers: NSEvent.ModifierFlags(rawValue: UInt(flags)), client: client)
            if !result.processed {
                // [self cancelComposition]
            }
            return result.processed
        }

        // Committing a Composition
        // 조합을 중단하고 현재까지 조합된 글자를 커밋한다.
        @objc override func commitComposition(_ sender: Any) {
            let client = asClient(sender)
            receiver.commitCompositionEvent(client)
            // COMMIT triggered
        }

        override func updateComposition() {
            receiver.updateCompositionEvent()

            // 인라인(직접 입력) 모드에서는 프로덕션 입력 경로가 updateComposition을
            // 호출하지 않고 renderInline이 직접 insertText로 문서를 갱신한다.
            // 테스트 하니스(VirtualApp)가 매 키마다 updateComposition을 호출하더라도
            // marked text를 쓰지 않도록 하여 프로덕션 동작을 충실히 반영한다.
            if Configuration.shared.inlineCompositionEnabled, !useMarkedText {
                return
            }

            let client = receiver.inputClient
            let composed = composedString(client) as! String
            let markedRange = client.markedRange()
            let view = receiver.inputClient as! NSTextView
            view.setMarkedText(composed, selectedRange: NSRange(location: 0, length: composed.count), replacementRange: markedRange)
        }

        override func cancelComposition() {
            receiver.cancelCompositionEvent()
            // 실제 InputController.cancelComposition 과 동일하게 인라인 추적 상태를
            // 비운다. (이게 빠져 있어 인라인 commit 중복 버그가 테스트에서 가려졌었다.)
            directRange = nil
            directText = ""
            expectedCaret = nil

            let client = receiver.inputClient
            let view = receiver.inputClient as! NSTextView
            let markedRange = client.markedRange()
            view.setMarkedText("", selectedRange: NSRange(location: markedRange.location, length: 0), replacementRange: markedRange)
        }

        // Getting Input Strings and Candidates
        // 현재 입력 중인 글자를 반환한다. -updateComposition: 이 사용
        override func composedString(_ sender: Any) -> Any {
            let client = asClient(sender)
            return receiver.composedString(client)
        }

        override func originalString(_ sender: Any) -> NSAttributedString {
            let client = asClient(sender)
            return receiver.originalString(client)
        }

        override func candidates(_ sender: Any) -> [Any]? {
            let client = asClient(sender)
            return receiver.candidates(client)
        }

        override func candidateSelected(_ candidateString: NSAttributedString!) {
            receiver.candidateSelected(candidateString)
        }

        override func candidateSelectionChanged(_ candidateString: NSAttributedString!) {
            receiver.candidateSelectionChanged(candidateString)
        }
    }

    public extension MockInputController { // IMKStateSetting
        //! @brief  마우스 이벤트를 잡을 수 있게 한다.
        override func recognizedEvents(_ sender: Any) -> Int {
            let client = asClient(sender)
            return Int(receiver.recognizedEvents(client).rawValue)
        }

        //! @brief 자판 전환을 감지한다.
        override func setValue(_ value: Any, forTag tag: Int, client sender: Any) {
            let client = asClient(sender)
            receiver.setValue(value, forTag: tag, client: client)
        }
    }
#endif
