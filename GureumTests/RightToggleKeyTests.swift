//
//  RightToggleKeyTests.swift
//  OSXTests
//
//  Unit tests for detecting the right-side 한/영 toggle key from a flagsChanged
//  event's `keyCode` (which side changed) + the device-INDEPENDENT modifier flag
//  transition (press vs release). This rides the IME's own event stream, which —
//  unlike the global IOHIDManager monitor (IOKitty) AND unlike the device-dependent
//  modifier bits — is still delivered to the IME under macOS Secure Event Input
//  (verified on-device: flagsChanged arrives with keyCode=54 for right Command even
//  while secure input is held by another process).
//
//  Pure functions only — no IMK/AppKit event, no live client.
//

@testable import GureumCore
import InputMethodKit
import XCTest

final class RightToggleKeyTests: XCTestCase {
    // device-independent NSEvent modifier raw values
    private let cmd = UInt(NSEvent.ModifierFlags.command.rawValue) // 0x100000
    private let opt = UInt(NSEvent.ModifierFlags.option.rawValue) // 0x80000
    private let shift = UInt(NSEvent.ModifierFlags.shift.rawValue) // 0x20000
    private let ctrl = UInt(NSEvent.ModifierFlags.control.rawValue) // 0x40000

    // virtual keycodes (kVK_*) for the right-side modifiers
    private let vkRightCommand = 0x36 // 54
    private let vkRightOption = 0x3D // 61
    private let vkRightShift = 0x3C // 60
    private let vkRightControl = 0x3E // 62
    private let vkLeftCommand = 0x37 // 55

    // MARK: toggleKeyVirtualKeyCode(forUsage:)

    func testVKForRightCommandUsage() {
        XCTAssertEqual(toggleKeyVirtualKeyCode(forUsage: kHIDUsage_KeyboardRightGUI), vkRightCommand)
    }

    func testVKForRightAltUsage() {
        XCTAssertEqual(toggleKeyVirtualKeyCode(forUsage: kHIDUsage_KeyboardRightAlt), vkRightOption)
    }

    func testVKForRightShiftUsage() {
        XCTAssertEqual(toggleKeyVirtualKeyCode(forUsage: kHIDUsage_KeyboardRightShift), vkRightShift)
    }

    func testVKForRightControlUsage() {
        XCTAssertEqual(toggleKeyVirtualKeyCode(forUsage: kHIDUsage_KeyboardRightControl), vkRightControl)
    }

    func testVKForUnmappedUsageIsNil() {
        XCTAssertNil(toggleKeyVirtualKeyCode(forUsage: 0))
    }

    // MARK: rightToggleKeyPressedByKeyCode(eventKeyCode:changed:current:toggleKeyUsage:)

    func testRightCommandPressToggles() {
        // Press: keyCode 54, command flag newly set (in both `changed` and `current`).
        XCTAssertTrue(rightToggleKeyPressedByKeyCode(eventKeyCode: vkRightCommand, changed: cmd, current: cmd, toggleKeyUsage: kHIDUsage_KeyboardRightGUI))
    }

    func testRightCommandReleaseDoesNotToggle() {
        // Release: the command flag changed but is no longer set in `current`.
        XCTAssertFalse(rightToggleKeyPressedByKeyCode(eventKeyCode: vkRightCommand, changed: cmd, current: 0, toggleKeyUsage: kHIDUsage_KeyboardRightGUI))
    }

    func testLeftCommandKeyCodeDoesNotToggle() {
        // Left Command (keyCode 55) sets the same generic command flag, but is not the
        // configured right-command toggle key → must not toggle.
        XCTAssertFalse(rightToggleKeyPressedByKeyCode(eventKeyCode: vkLeftCommand, changed: cmd, current: cmd, toggleKeyUsage: kHIDUsage_KeyboardRightGUI))
    }

    func testRightAltConfiguredTogglesOnRightAltPress() {
        XCTAssertTrue(rightToggleKeyPressedByKeyCode(eventKeyCode: vkRightOption, changed: opt, current: opt, toggleKeyUsage: kHIDUsage_KeyboardRightAlt))
    }

    func testDisabledUsageNeverToggles() {
        XCTAssertFalse(rightToggleKeyPressedByKeyCode(eventKeyCode: vkRightCommand, changed: cmd, current: cmd, toggleKeyUsage: 0))
    }

    func testKeyCodeMatchesButFlagNotInChangedDoesNotToggle() {
        // Right-command keyCode, but the command flag was already held (a different
        // modifier toggled this event) → not a fresh press of the toggle key.
        XCTAssertFalse(rightToggleKeyPressedByKeyCode(eventKeyCode: vkRightCommand, changed: shift, current: cmd | shift, toggleKeyUsage: kHIDUsage_KeyboardRightGUI))
    }

    func testWrongKeyCodeWithRightFlagDoesNotToggle() {
        // The command flag transitioned, but the event's keyCode is some other key.
        XCTAssertFalse(rightToggleKeyPressedByKeyCode(eventKeyCode: vkRightOption, changed: cmd, current: cmd, toggleKeyUsage: kHIDUsage_KeyboardRightGUI))
    }
}
