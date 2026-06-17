//
//  InputMethodServer.swift
//  OSX
//
//  Created by yuaming on 2018. 9. 20..
//  Copyright © 2018 youknowone.org. All rights reserved.
//

import Foundation
import InputMethodKit
import SwiftIOKit

let DEBUG_INPUT_SERVER = false
let DEBUG_IOKIT_EVENT = false

extension IMKServer {
    convenience init?(bundle: Bundle) {
        guard let connectionName = bundle.infoDictionary!["InputMethodConnectionName"] as? String else {
            return nil
        }
        self.init(name: connectionName, bundleIdentifier: bundle.bundleIdentifier)
    }
}

class IOKitty {
    let service: SIOService
    let connect: SIOConnect
    let manager: IOHIDManager
    private var defaultCapsLockState: Bool = false
    var capsLockDate: Date?
    var rollback: (() -> Void)?
    var rightKeyPressed = false

    init?() {
        guard let _service = SIOService(name: kIOHIDSystemClass) else {
            return nil
        }
        service = _service
        guard let _connect = try? service.open(owningTask: mach_task_self_, type: kIOHIDParamConnectType).get() else {
            return nil
        }
        connect = _connect

        defaultCapsLockState = (try? connect.getModifierLock(selector: .capsLock).get()) ?? false

        manager = IOHIDManager.create()
        manager.setDeviceMatching(page: kHIDPage_GenericDesktop, usage: kHIDUsage_GD_Keyboard)
        manager.setInputValueMatching(min: kHIDUsage_KeyboardCapsLock, max: kHIDUsage_KeyboardRightGUI)

        let _self = Unmanaged.passUnretained(self)
        // Set input value callback
        manager.registerInputValueCallback({
            inContext, _, _, value in
            let usage = Int(value.element.usage)
            guard usage == kHIDUsage_KeyboardCapsLock || (usage >= kHIDUsage_KeyboardRightControl && usage <= kHIDUsage_KeyboardRightGUI) else {
                return
            }
            guard Configuration.shared.enableCapslockToToggleInputMode || Configuration.shared.rightToggleKey > 0 else {
                return
            }
            guard let inContext = inContext else {
                dlog(true, "IOKit callback inContext is nil - impossible")
                return
            }

            let pressed = value.integerValue > 0
            switch usage {
            case kHIDUsage_KeyboardCapsLock:
                guard Configuration.shared.enableCapslockToToggleInputMode else {
                    return
                }
                dlog(DEBUG_IOKIT_EVENT, "caps lock pressed: \(pressed)")
                let _self = Unmanaged<IOKitty>.fromOpaque(inContext).takeUnretainedValue()
                if pressed {
                    _self.capsLockDate = Date()
                    dlog(DEBUG_IOKIT_EVENT, "caps lock pressed set in context")
                } else {
                    if _self.defaultCapsLockState || (_self.capsLockDate != nil && !_self.capsLockTriggered) {
                        // long pressed
                        _self.defaultCapsLockState = !_self.defaultCapsLockState
                        _self.rollback?()
                        _self.rollback = nil
                    } else {
                        // short pressed
                        _ = _self.connect.setModifierLock(selector: .capsLock, state: _self.defaultCapsLockState)
                        _self.capsLockDate = nil
                    }
                }
            case Configuration.shared.rightToggleKey:
                dlog(DEBUG_IOKIT_EVENT, "right toggle key pressed: \(pressed)")
                let _self = Unmanaged<IOKitty>.fromOpaque(inContext).takeUnretainedValue()
                if pressed {
                    _self.rightKeyPressed = true
                    dlog(DEBUG_IOKIT_EVENT, "right toggle key pressed set in context")
                }
            default:
                break
            }
            // NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: .capsLock, timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0)!
        }, context: _self.toOpaque())

        manager.schedule(runloop: .current, mode: .default)
        let r = manager.open()
        if r != kIOReturnSuccess {
            dlog(DEBUG_IOKIT_EVENT, "IOHIDManagerOpen failed")
        }
    }

    deinit {
        manager.unschedule(runloop: .current, mode: .default)
        manager.unregisterInputValueCallback()
        let r = manager.close()
        assert(r == 0)
    }

    var capsLockTriggered: Bool {
        dlog(DEBUG_IOKIT_EVENT, "  triggered: date \(String(describing: capsLockDate))")
        guard let capsLockDate = capsLockDate else {
            return false
        }
        let interval = Date().timeIntervalSince(capsLockDate)
        dlog(DEBUG_IOKIT_EVENT, "  triggered: interval \(interval)")
        return interval < 0.5
    }

    func resolveRightKeyPressed() -> Bool {
        if !rightKeyPressed {
            return false
        }
        rightKeyPressed = false
        return true
    }
}

// MARK: - Right toggle key detection from the IME's own flagsChanged stream

/// 우측 토글 모디파이어 키의 HID usage를 그에 대응하는 가상 키코드(`NSEvent.keyCode`,
/// 즉 `kVK_*`)로 매핑한다. 매핑 없는 usage(0=비활성 등)는 nil.
///
/// 왜 keyCode인가: 좌/우 모디파이어를 구분할 다른 신호가 IME에 닿지 않는다.
///   - 전역 IOHIDManager 모니터(`IOKitty`)는 다른 프로세스가 켠 Secure Event Input에
///     시스템 전역으로 차단된다.
///   - `flagsChanged`의 device-dependent 모디파이어 비트(`NX_DEVICER*KEYMASK`)는 IME가
///     받는 NSEvent에 **아예 실리지 않는다**(on-device 확인: 우측 Command를 눌러도
///     `modifierFlags`는 device-independent Command 비트 `0x100000`만, 좌/우 구분 0).
/// 반면 `flagsChanged` 이벤트의 `keyCode`는 어느 모디파이어 키가 바뀌었는지 알려주고,
/// **Secure Event Input 하에서도 IME에 그대로 전달된다**(on-device 확인: secure=true,
/// 터미널/비-터미널 모두에서 우측 Command가 `keyCode=54`로 도착). 그래서 이걸 쓴다.
func toggleKeyVirtualKeyCode(forUsage usage: Int) -> Int? {
    switch usage {
    case kHIDUsage_KeyboardRightControl: return 0x3E // kVK_RightControl = 62
    case kHIDUsage_KeyboardRightShift: return 0x3C // kVK_RightShift = 60
    case kHIDUsage_KeyboardRightAlt: return 0x3D // kVK_RightOption = 61
    case kHIDUsage_KeyboardRightGUI: return 0x36 // kVK_RightCommand = 54
    default: return nil
    }
}

/// 우측 토글 키가 세팅하는 device-independent 모디파이어 플래그의 rawValue(press/release 판정용).
private func toggleKeyModifierFlagRawValue(forUsage usage: Int) -> UInt {
    switch usage {
    case kHIDUsage_KeyboardRightControl: return 0x4_0000 // NSEvent.ModifierFlags.control
    case kHIDUsage_KeyboardRightShift: return 0x2_0000 // .shift
    case kHIDUsage_KeyboardRightAlt: return 0x8_0000 // .option
    case kHIDUsage_KeyboardRightGUI: return 0x10_0000 // .command
    default: return 0
    }
}

/// 이번 `flagsChanged`에서 설정된 우측 토글 키가 "눌림"(press)으로 전이됐는지 판정(순수).
///
/// `eventKeyCode`로 **어느 쪽** 모디파이어인지(좌/우)를 가리고, 그 키가 세팅하는
/// device-independent 플래그가 이번 이벤트에서 새로 켜졌는지(`changed`에 있고 `current`에도
/// 있음 = 0→1 전이)로 press를 판정한다. 떼임(release)은 `current`에 플래그가 없어 제외된다.
///
/// - Parameters:
///   - eventKeyCode: `flagsChanged` 이벤트의 `keyCode`(어느 모디파이어 키가 바뀌었나).
///   - changed: 직전 플래그와 현재 플래그의 차이(`symmetricDifference`)의 rawValue.
///   - current: 현재 이벤트 `modifierFlags`의 rawValue.
///   - toggleKeyUsage: 설정된 우측 토글 키의 HID usage.
func rightToggleKeyPressedByKeyCode(eventKeyCode: Int, changed: UInt, current: UInt, toggleKeyUsage: Int) -> Bool {
    guard let vk = toggleKeyVirtualKeyCode(forUsage: toggleKeyUsage), eventKeyCode == vk else { return false }
    let flag = toggleKeyModifierFlagRawValue(forUsage: toggleKeyUsage)
    guard flag != 0 else { return false }
    return (changed & flag) != 0 && (current & flag) != 0
}

/*!
 @brief  공통적인 OSX의 입력기 구조를 다룬다.

 InputManager는 @ref InputController 또는 테스트코드에 해당하는 외부에서 입력을 받아 입력기에서 처리 후 결과 값을 보관한다. 처리 후 그 결과를 확인하는 것은 사용자의 몫이다.

 IMKServer나 클라이언트와 무관하게 입력 값에 대해 출력 값을 생성해 내는 입력기. 입력 뿐만 아니라 여러 키보드 간 전환이나 입력기에 관한 단축키 등 입력기에 관한 모든 기능을 다룬다.

 @coclass    IMKServer DelegatedComposer
 */
// TODO: InputTextDelegate를 제거하고 서버만 관리하도록 한다
public class InputMethodServer {
    public static let shared = InputMethodServer()
    //! @brief  현재 입력중인 서버
    let server: IMKServer
    //! @property
    let candidates: IMKCandidates
    //! @brief  입력기가 inputText: 문맥에 있는지 여부를 저장. IOHID(입력 모니터링) 권한이 없으면
    //! nil이 된다 — 기본 입력은 IOHID 없이도 동작해야 하므로 force-unwrap 하지 않는다.
    let io: IOKitty?

    convenience init() {
        let bundle = Bundle.main
        var name = bundle.infoDictionary!["InputMethodConnectionName"] as! String
        #if DEBUG
            if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
                name += "_Test" + String(describing: Int.random(in: 0 ..< 0x10000))
            } else {
                name += "_Debug"
            }
        #endif

        self.init(name: name)
    }

    init(name: String) {
        dlog(DEBUG_INPUT_SERVER, "** InputMethodServer Init")

        server = IMKServer(name: name, bundleIdentifier: Bundle.main.bundleIdentifier)
        candidates = IMKCandidates(server: server, panelType: kIMKSingleColumnScrollingCandidatePanel)
        // candidates.setSelectionKeysKeylayout(TISInputSource.currentKeyboardLayout())

        io = IOKitty()
        dlog(DEBUG_INPUT_SERVER, "\t%@", description)
    }

    var description: String {
        return """
        <InputMethodServer server: "\(String(describing: server))" candidates: "\(String(describing: candidates))">
        """
    }

    func showOrHideCandidates(controller: InputController) {
        showOrHideCandidates(composer: controller.receiver.composer)
    }

    func showOrHideCandidates(composer: Composer) {
        if composer.hasCandidates {
            candidates.update()
            candidates.show(kIMKLocateCandidatesLeftHint)
        } else if candidates.isVisible() {
            candidates.hide()
        }
    }
}
