//
//  InputReceiver.swift
//  OSX
//
//  Created by Jeong YunWon on 21/10/2018.
//  Copyright © 2018 youknowone.org. All rights reserved.
//

import Carbon
import Foundation
import InputMethodKit

let DEBUG_INPUT_RECEIVER = false

/// 토글 대상 입력소스 ref 캐시(id → TISInputSource). 입력소스 목록은 거의 바뀌지 않으므로
/// id별로 캐시해 매 토글의 `TISCreateInputSourceList` 조회를 피한다. 선택 실패(소스
/// 비활성/제거 등으로 ref가 stale) 시 해당 항목을 무효화하고 다시 조회한다.
/// IMK 입력 처리(메인 스레드)에서만 접근하므로 잠금 불필요.
private var fastSelectSourceCache: [String: TISInputSource] = [:]

/// 입력소스를 빠른 경로로 전환한다.
///
/// IMK의 `selectMode`(= ObjC `selectInputMode:`)로 한/영을 전환하면 macOS가 입력소스를
/// 매우 느리게(~1초) 바꾼다. Ctrl-Opt-Space와 동일한 `TISSelectInputSource`로 대상 소스를
/// 직접 선택하면 즉시 전환되고 메뉴바 한/A 아이콘도 정상 갱신된다. 대상 소스가
/// 비활성/미발견이거나 선택이 실패하면 기존 `selectMode` 경로(`fallback`)로 되돌린다.
func selectInputSourceFast(id: String, fallback: () -> Void) {
    // 캐시된 ref로 먼저 시도.
    if let cached = fastSelectSourceCache[id] {
        if TISSelectInputSource(cached) == noErr {
            return
        }
        fastSelectSourceCache[id] = nil // stale → 무효화 후 재조회
    }
    let filter: NSDictionary = [kTISPropertyInputSourceID as String: id]
    if let source = (TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource])?.first,
       TISSelectInputSource(source) == noErr
    {
        fastSelectSourceCache[id] = source
        return
    }
    // 영문(로마자) 소스가 입력소스 목록에 없으면 여기로 떨어진다(느린 selectMode로 폴백).
    dlog(DEBUG_INPUT_RECEIVER, "selectInputSourceFast: '%@' not enabled/selectable → selectMode fallback", id)
    fallback()
}

public class InputReceiver: InputTextDelegate {
    var inputClient: IMKTextInput & IMKUnicodeTextInput
    var composer = GureumComposer()
    weak var controller: InputController!
    var inputting: Bool = false

    init(server: IMKServer, delegate: Any!, client: IMKTextInput & IMKUnicodeTextInput, controller: InputController) {
        dlog(DEBUG_INPUT_RECEIVER, "**** NEW INPUT CONTROLLER INIT **** WITH SERVER: %@ / DELEGATE: %@ / CLIENT: %@", server, (delegate as? NSObject) ?? "(nil)", (client as? NSObject) ?? "(nil)")
        inputClient = client
        self.controller = controller
    }

    // MARK: - IMKServerInputTextData

    func input2(text string: String?, keyCode: KeyCode, modifiers flags: NSEvent.ModifierFlags, client sender: IMKTextInput & IMKUnicodeTextInput) -> InputResult {
        // 특정 애플리케이션에서 커맨드/옵션/컨트롤 키 입력을 선점하지 못하는 문제를 회피한다
        if flags.contains(.command) || flags.contains(.control) {
            dlog(DEBUG_INPUT_RECEIVER, "-- InputReceiver -inputText: Command/Control key input / returned NO")
            return InputResult(processed: false, action: .commit)
        }

        if string == nil, !flags.contains(.option) {
            return InputResult(processed: false, action: .commit)
        }

        let result = composer.input(text: string, key: keyCode, modifiers: flags, client: sender)

        return result
    }

    // MARK: InputTextDelegate 프로토콜 구현

    // IMKServerInput 프로토콜에 대한 공용 핸들러
    func input(text string: String?,
               key keyCode: KeyCode,
               modifiers flags: NSEvent.ModifierFlags,
               client sender: IMKTextInput & IMKUnicodeTextInput) -> InputResult
    {
        // NOTE: 이전에는 매 키 입력마다 sender.selectedRange() + sender.markedRange()
        // (각각 포커스된 앱으로의 동기 IPC 왕복)를 호출했으나, 그 값을 쓰던 블록이
        // 전부 주석 처리돼 결과가 버려지고 있었다. per-keystroke 지연만 유발하므로 제거.
        // (커밋/조합 경로는 아래에서 필요한 시점에만 selectionRange를 질의한다.)

        // 입력기용 특수 커맨드 처리
        if let command = composer.filterCommand(keyCode: keyCode, modifiers: flags, client: sender) {
            let result = input(event: command, client: sender)
            if result.processed {
                return result
            }
        }

        dlog(DEBUG_LOGGING, "LOGGING::KEY::(%@)(%ld)(%lu)", string?.replacingOccurrences(of: "\n", with: "\\n") ?? "(nil)", keyCode.rawValue, flags.rawValue)

        let hadComposedString = !_internalComposedString.isEmpty
        let result = input2(text: string, keyCode: keyCode, modifiers: flags, client: sender)

        // 합성 후보가 있다면 보여준다
        InputMethodServer.shared.showOrHideCandidates(controller: controller)

        inputting = true

        if result.action != .none {
            if Configuration.shared.inlineCompositionEnabled, !controller.useMarkedText {
                // 인라인: composer만 flush하고 directRange는 보존한다. 여기서
                // controller.cancelComposition()을 부르면 directRange가 먼저 비워져,
                // 아래 renderInline이 이미 문서에 삽입된 조합 글자를 제자리 치환하지
                // 못하고 append → 커밋(스페이스/엔터) 시 마지막 음절이 중복된다
                // (예: "안녕" → "안녕녕"). renderInline이 치환 후 directRange를 정리한다.
                cancelCompositionEvent()
            } else {
                cancelComposition()
            }
        }

        if Configuration.shared.inlineCompositionEnabled, !controller.useMarkedText {
            // ② 커서이동 무효화: 순수 조합 연속(action == .none)일 때만 검사한다. 커밋/취소
            // 경로는 ① fail-safe가 처리하므로 건드리지 않는다(그렇지 않으면 lost-range 커밋이
            // stale 추적을 비워 append 중복을 낸다).
            if result.action == .none {
                invalidateDirectRangeIfCursorMoved(sender)
            }
            // 인라인(직접 입력) 분기: 커밋 + 조합 문자를 한 번의 insertText로 문서에 반영한다.
            renderInline(sender)
            if result.action == .commit {
                return result
            }
        } else {
            let commited = commitCompositionEvent(sender) // 조합 된 문자 반영
            if result.action == .commit {
                return result
            }
            let hasComposedString = !_internalComposedString.isEmpty
            // updateComposition 필요 판정. controller.selectionRange()는 포커스 앱으로의
            // 동기 IPC 왕복이라, 비용 없는 로컬 검사(commited/hadComposedString/
            // hasComposedString)를 OR 앞쪽에 두어 먼저 보고, 그래도 판정이 안 날 때만
            // 마지막에 질의해 키 입력당 IPC를 단락(short-circuit)으로 아낀다. (이전에는
            // 여기서 selectionRange를 한 번 더 질의해 hasSelectionRange에 넣었으나, 그
            // 값이 어디서도 읽히지 않아 매 키 버려지던 IPC였으므로 제거했다.)
            if commited || hadComposedString || hasComposedString || controller.selectionRange().length > 0 {
                updateComposition() // 조합 중인 문자 반영
            }
        }

        inputting = false

        dlog(DEBUG_INPUT_RECEIVER, "*** End of Input handling ***")
        return result
    }

    /// ② 커서이동 무효화: 직전 인라인 렌더 이후의 기대 caret(expectedCaret)과 현재
    /// selectedRange가 다르면 사용자가 커서를 옮긴 것 → directRange를 비워 재앵커한다.
    /// 그대로 두면 directRangeIsCurrent가 옛 위치의 텍스트를 그대로 확인해 그 위치를
    /// 제자리 치환하고, 사용자가 옮긴 위치를 무시한다(Word move-then-delete 점프).
    private func invalidateDirectRangeIfCursorMoved(_ sender: IMKTextInput & IMKUnicodeTextInput) {
        guard controller.directRange != nil, let expected = controller.expectedCaret else {
            return
        }
        let sel = sender.selectedRange()
        if sel.location == NSNotFound {
            return
        }
        if sel.location != expected {
            controller.directRange = nil
            controller.directText = ""
            controller.expectedCaret = nil
        }
    }

    /// 직전 인라인 조합 문자열(`expected`)이 자리하던 문서 범위를 도출한다.
    /// `directRange`(`dr`)가 여전히 유효하면 그대로 사용하고, 커서만 이동한
    /// 경우 커서 바로 앞을 backtrack해 보정하며, 어느 쪽도 아니면 NSNotFound.
    /// (DKST `directInputReplacementRange` 포팅, MIT)
    private func inlineReplaceRange(_ expected: String, dr: NSRange, client sender: IMKTextInput & IMKUnicodeTextInput) -> NSRange {
        if controller.directRangeIsCurrent(expected, range: dr, client: sender) {
            return dr
        }
        let sel = sender.selectedRange()
        if sel.location != NSNotFound, sel.length == 0, sel.location >= dr.length {
            let back = NSRange(location: sel.location - dr.length, length: dr.length)
            if controller.directRangeIsCurrent(expected, range: back, client: sender) {
                return back
            }
        }
        return NSRange(location: NSNotFound, length: 0)
    }

    /// 인라인(직접 입력) 렌더링: 커밋 문자열과 조합 중인 문자열을 합쳐 단 한 번의
    /// insertText로 문서에 반영하고, 조합 중인 문자가 차지하는 범위(directRange)를
    /// 갱신한다. PHASE 2: 실제 치환 직후 caret 착지를 검증해 append-only 클라이언트를
    /// marked로 강등·학습한다. (DKST 스타일 포팅, MIT)
    private func renderInline(_ sender: IMKTextInput & IMKUnicodeTextInput) {
        let commitString = composer.dequeueCommitString()
        let composedString = _internalComposedString
        let combined = commitString + composedString

        // 직전 조합 문자열이 자리하던 범위를 찾아 대체 대상으로 삼는다.
        let replaceRange = (controller.directRange != nil)
            ? inlineReplaceRange(controller.directText, dr: controller.directRange!, client: sender)
            : NSRange(location: NSNotFound, length: 0)

        // ① fail-safe (PHASE 1): 추적 중이던 directRange의 위치를 잃었고(replaceRange ==
        // NSNotFound: 검증·backtrack 모두 실패) 새로 조합할 글자가 없으면(composedString
        // empty = 커밋/종료) combined은 이미 인라인으로 들어가 있는 글자(directText)의
        // 마무리일 뿐이다. 위치를 못 찾는 상태에서 append하면 중복되므로(예: "안녕" →
        // "안녕녕") 삽입을 건너뛰고 추적만 비운다.
        if controller.directRange != nil, replaceRange.location == NSNotFound, composedString.isEmpty {
            controller.directRange = nil
            controller.directText = ""
            controller.expectedCaret = nil
            return
        }

        // 검증 실패 시 누수 구간 산정에 필요하므로 직전 directText를 미리 저장한다.
        let priorDirectText = controller.directText

        if !combined.isEmpty || replaceRange.location != NSNotFound {
            sender.insertText(combined, replacementRange: replaceRange)
        }

        // PHASE 2 ③(B층): 실제 치환을 시도한(replaceRange != NSNotFound) 비어 있지 않은
        // 삽입이라면, caret 착지로 제자리 치환이 실제 일어났는지 검증한다. append-only
        // 앱(Word 등)은 replacementRange를 무시하고 append하므로 caret이 기대보다
        // 오른쪽에 남는다. 위반이면 그 클라이언트를 marked로 강등·학습한다.
        if !combined.isEmpty, replaceRange.location != NSNotFound,
           didInlineReplaceFail(combined: combined, replaceRange: replaceRange, client: sender)
        {
            demoteToMarked(priorDirectText: priorDirectText, replaceRange: replaceRange,
                           combined: combined, client: sender)
            return
        }

        if composedString.isEmpty {
            controller.directRange = nil
            controller.directText = ""
            controller.expectedCaret = nil
        } else {
            let baseLoc: Int
            if replaceRange.location != NSNotFound {
                baseLoc = replaceRange.location
            } else {
                let sel = sender.selectedRange()
                // 셀렉션 위치를 알 수 없으면 직접 범위를 산정할 수 없으므로,
                // 손상된 directRange를 저장하지 않고 추적 상태를 비운다.
                if sel.location == NSNotFound {
                    controller.directRange = nil
                    controller.directText = ""
                    controller.expectedCaret = nil
                    return
                }
                baseLoc = sel.location - (combined as NSString).length
            }
            controller.directRange = NSRange(location: baseLoc + (commitString as NSString).length,
                                             length: (composedString as NSString).length)
            controller.directText = composedString
            // ② 기대 caret = 삽입한 combined의 끝 = directRange의 끝.
            controller.expectedCaret = baseLoc + (combined as NSString).length
        }
    }

    /// 인라인 제자리 치환이 실패했는지(=클라이언트가 replacementRange를 무시하고
    /// append했는지) caret 착지로 판정한다. 기대 caret = replaceRange.location +
    /// combined 길이. selectedRange가 이와 다르면 실패로 본다. selectedRange를 알 수
    /// 없으면(NSNotFound) 함부로 강등하지 않는다(false).
    private func didInlineReplaceFail(combined: String, replaceRange: NSRange,
                                      client sender: IMKTextInput & IMKUnicodeTextInput) -> Bool
    {
        let sel = sender.selectedRange()
        if sel.location == NSNotFound {
            return false
        }
        let expected = replaceRange.location + (combined as NSString).length
        return sel.location != expected
    }

    /// append-only로 판명된 클라이언트를 marked로 강등·학습한다. 누수 구간은 best-effort로
    /// 제거를 시도하고(append-only 앱은 이 삭제도 무시할 수 있어 1회성 잔상이 남을 수
    /// 있음 — 깨끗함은 A층 시드 목록이 보장), 진행 중 조합을 marked로 즉시 재렌더한다.
    private func demoteToMarked(priorDirectText: String, replaceRange: NSRange, combined: String,
                               client sender: IMKTextInput & IMKUnicodeTextInput)
    {
        // 1) 학습 + 세션 강등.
        if let bundleID = sender.bundleIdentifier(), !bundleID.isEmpty {
            InputController.recordLearnedAppendOnly(bundleID: bundleID)
        }
        controller.useMarkedText = true

        // 2) best-effort 누수 제거: [replaceRange.location, priorDirectText + combined].
        let leakedLength = (priorDirectText as NSString).length + (combined as NSString).length
        let leakedRange = NSRange(location: replaceRange.location, length: leakedLength)
        sender.insertText("", replacementRange: leakedRange)

        // 3) 인라인 추적 비우고 진행 중 조합을 marked로 재렌더(useMarkedText=true이므로
        //    updateComposition이 marked 경로를 탄다).
        controller.directRange = nil
        controller.directText = ""
        controller.expectedCaret = nil
        updateComposition()
    }

    func input(event: InputEvent, client sender: IMKTextInput & IMKUnicodeTextInput) -> InputResult {
        switch event {
        case let .changeLayout(layout, processed):
            let innerLayout = layout == .toggleByCapsLock || layout == .toggleByRightKey ? .toggle : layout
            let result = composer.changeLayout(innerLayout, client: sender)
            // 합성 후보가 있다면 보여준다
            InputMethodServer.shared.showOrHideCandidates(controller: controller)

            inputting = true

            if result.action != .none {
                cancelComposition()
                if result.action != .cancel {
                    commitCompositionEvent(sender)
                    if case let .layout(mode) = result.action, layout != .toggleByCapsLock {
                        // 한/영 토글: IMK selectMode(=selectInputMode:)는 ~1초 느린 경로라
                        // TISSelectInputSource(Ctrl-Opt-Space와 같은 빠른 경로)로 직접 전환한다.
                        selectInputSourceFast(id: mode) { (sender as IMKTextInput).selectMode(mode) }
                    }
                } else {
                    updateComposition() // 조합 중인 문자 반영
                }
            }

            inputting = false

            return processed ? .processed : .notProcessed
        }
    }
}

extension InputReceiver { // IMKServerInput
    // Committing a Composition
    // 조합을 중단하고 현재까지 조합된 글자를 커밋한다.
    func commitComposition(_ sender: IMKTextInput & IMKUnicodeTextInput) {
        dlog(DEBUG_LOGGING, "LOGGING::EVENT::COMMIT-INTERNAL")
        commitCompositionEvent(sender)
    }

    func updateComposition() {
        dlog(DEBUG_LOGGING, "LOGGING::EVENT::UPDATE-INTERNAL")
        controller.updateComposition()
    }

    func cancelComposition() {
        dlog(DEBUG_LOGGING, "LOGGING::EVENT::CANCEL-INTERNAL")
        controller.cancelComposition()
    }

    // Committing a Composition
    // 조합을 중단하고 현재까지 조합된 글자를 커밋한다.
    @discardableResult
    func commitCompositionEvent(_ sender: IMKTextInput & IMKUnicodeTextInput) -> Bool {
        dlog(DEBUG_LOGGING, "LOGGING::EVENT::COMMIT")
        if !inputting {
            // 입력기 외부에서 들어오는 커밋 요청에 대해서는 편집 중인 글자도 커밋한다.
            dlog(DEBUG_INPUTCONTROLLER, "-- CANCEL composition because of external commit request from %@", sender as! NSObject)
            dlog(DEBUG_LOGGING, "LOGGING::EVENT::CANCEL-INTERNAL")
            cancelCompositionEvent()
        }
        // 왠지는 모르겠지만 프로그램마다 동작이 달라서 조합을 반드시 마쳐주어야 한다
        // 터미널과 같이 조합중에 리턴키 먹는 프로그램은 조합 중인 문자가 없고 보통은 있다
        let commitString = composer.dequeueCommitString()

        // 인라인(직접 입력) 분기: 조합 중인 글자는 이미 directRange 위치에 실제
        // 텍스트로 문서에 존재한다. 셀렉션에 다시 insert하면 그 글자가 중복되므로
        // (예: 인라인으로 "안" 조합 → 모드 전환 → "안안"), 셀렉션 insert 대신
        // 해당 범위를 최종 commitString으로 제자리 치환하고 추적 상태를 비운다.
        if Configuration.shared.inlineCompositionEnabled, !controller.useMarkedText, let dr = controller.directRange {
            if !commitString.isEmpty {
                let replaceRange = inlineReplaceRange(controller.directText, dr: dr, client: sender)
                sender.insertText(commitString, replacementRange: replaceRange)
            }
            controller.directRange = nil
            controller.directText = ""
            InputMethodServer.shared.showOrHideCandidates(controller: controller)
            return !commitString.isEmpty
        }

        // 커밋할 문자가 없으면 중단
        if commitString.isEmpty {
            return false
        }

        dlog(DEBUG_INPUT_RECEIVER, "** InputController -commitComposition: with sender: %@ / strings: %@", sender as! NSObject, commitString)
        var range = controller.selectionRange()
        dlog(DEBUG_LOGGING, "LOGGING::COMMIT::%lu:%lu:%@", range.location, range.length, commitString)
        // NSLog("range1 \(range)")글
        if range.length == 0 {
            range = NSRange(location: NSNotFound, length: 0)
        }
        // NSLog("commit \(commitString) to \(range)")
        controller.client().insertText(commitString, replacementRange: range)

        InputMethodServer.shared.showOrHideCandidates(controller: controller)

        return true
    }

    func updateCompositionEvent() {
        dlog(DEBUG_LOGGING, "LOGGING::EVENT::UPDATE")
        dlog(DEBUG_INPUTCONTROLLER, "** InputController -updateComposition")
    }

    func cancelCompositionEvent() {
        dlog(DEBUG_LOGGING, "LOGGING::EVENT::CANCEL")
        composer.cancelComposition()
    }

    var _internalComposedString: String {
        return composer.composedString
    }

    // Getting Input Strings and Candidates
    // 현재 입력 중인 글자를 반환한다. -updateComposition: 이 사용
    func composedString(_: IMKTextInput & IMKUnicodeTextInput) -> String {
        let string = _internalComposedString
        dlog(DEBUG_LOGGING, "LOGGING::CHECK::COMPOSEDSTRING::(%@)", string)
        dlog(DEBUG_INPUTCONTROLLER, "** InputController -composedString: with return: '%@'", string)
        return string
    }

    func originalString(_: IMKTextInput & IMKUnicodeTextInput) -> NSAttributedString {
        dlog(DEBUG_INPUTCONTROLLER, "** InputController -originalString:")
        let s = NSAttributedString(string: composer.originalString)
        dlog(DEBUG_LOGGING, "LOGGING::CHECK::ORIGINALSTRING::%@", s.string)
        return s
    }

    func candidates(_: IMKTextInput & IMKUnicodeTextInput) -> [Any]! {
        dlog(DEBUG_LOGGING, "LOGGING::CHECK::CANDIDATES")
        return composer.candidates
    }

    func candidateSelected(_ candidateString: NSAttributedString) {
        dlog(DEBUG_LOGGING, "LOGGING::CHECK::CANDIDATESELECTED::%@", candidateString)
        inputting = true
        composer.candidateSelected(candidateString)
        commitCompositionEvent(inputClient)
        inputting = false
    }

    func candidateSelectionChanged(_ candidateString: NSAttributedString) {
        dlog(DEBUG_LOGGING, "LOGGING::CHECK::CANDIDATESELECTIONCHANGED::%@", candidateString)
        composer.candidateSelectionChanged(candidateString)
        updateComposition()
    }
}

extension InputReceiver { // IMKStateSetting
    //! @brief  마우스 이벤트를 잡을 수 있게 한다.
    func recognizedEvents(_: IMKTextInput & IMKUnicodeTextInput) -> NSEvent.EventTypeMask {
        dlog(DEBUG_LOGGING, "LOGGING::CHECK::RECOGNIZEDEVENTS")
        // NSFlagsChangeMask는 -handleEvent: 에서만 동작
        return NSEvent.EventTypeMask(arrayLiteral: .keyDown, .flagsChanged, .leftMouseUp, .rightMouseUp, .leftMouseDown, .rightMouseDown, .leftMouseDragged, .rightMouseDragged, .appKitDefined, .applicationDefined, .systemDefined)
    }

    //! @brief 자판 전환을 감지한다.
    func setValue(_ value: Any, forTag tag: Int, client sender: IMKTextInput & IMKUnicodeTextInput) {
        InputMethodServer.shared.io?.capsLockDate = nil
        dlog(DEBUG_LOGGING, "LOGGING::EVENT::CHANGE-%lu-%@", tag, value as? String ?? "(nonstring)")
        dlog(DEBUG_INPUTCONTROLLER, "** InputController -setValue:forTag:client: with value: %@ / tag: %lx / client: %@", value as? String ?? "(nonstring)", tag, String(describing: controller.client as AnyObject))
        sender.overrideKeyboard(withKeyboardNamed: Configuration.shared.overridingKeyboardName)
        switch tag {
        case kTextServiceInputModePropertyTag:
            guard let value = value as? String else {
                NSLog("Failed to change keyboard layout")
                assertionFailure()
                break
            }
            if value != composer.inputMode {
                commitComposition(sender)
                composer.inputMode = value
                // 이전 인라인 조합은 위의 commitComposition(sender)로 이미 커밋되었으므로
                // 추적 상태를 비워 새 모드가 깨끗하게 시작하도록 한다.
                controller.directRange = nil
                controller.directText = ""
                controller.expectedCaret = nil
                // 입력 모드가 실제로 바뀐 뒤 합성 표시 방식을 다시 계산해 캐시한다.
                // (클라이언트 단위 캐시 — 키 입력마다 비공개 API를 질의하지 않는다.)
                controller.useMarkedText = classifyComposition(LiveClientCapabilities(controller: controller, client: sender)) == .marked
            }
        default:
            dlog(true, "**** UNKNOWN TAG %ld !!! ****", tag)
        }
    }
}
