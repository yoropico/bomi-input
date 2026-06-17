//
//  RightToggleKeyTests.swift
//  OSXTests
//
//  Unit tests for detecting the right-side 한/영 toggle key directly from a
//  `flagsChanged` event's device-dependent modifier bits, independent of the
//  global IOHIDManager monitor (IOKitty). This is the fail-safe path used when
//  secure input (or any other condition) blocks the global HID monitor while
//  the IME itself still receives events.
//
//  These tests exercise pure functions only — no IMK/AppKit, no live client.
//

@testable import GureumCore
import InputMethodKit
import XCTest

final class RightToggleKeyTests: XCTestCase {
    // Device-dependent modifier bit masks (IOKit IOLLEvent.h NX_DEVICE*_KEYMASK).
    private let rCmd: UInt = 0x0010 // NX_DEVICERCMDKEYMASK
    private let lCmd: UInt = 0x0008 // NX_DEVICELCMDKEYMASK
    private let rAlt: UInt = 0x0040 // NX_DEVICERALTKEYMASK
    private let rShift: UInt = 0x0004 // NX_DEVICERSHIFTKEYMASK
    private let rCtrl: UInt = 0x2000 // NX_DEVICERCTLKEYMASK
    // Device-independent flag set alongside the device bit by AppKit.
    private let indepCmd = UInt(NSEvent.ModifierFlags.command.rawValue)

    // MARK: deviceModifierMask(forKeyboardUsage:)

    func testMaskForRightCommandUsage() {
        XCTAssertEqual(deviceModifierMask(forKeyboardUsage: kHIDUsage_KeyboardRightGUI), rCmd)
    }

    func testMaskForRightAltUsage() {
        XCTAssertEqual(deviceModifierMask(forKeyboardUsage: kHIDUsage_KeyboardRightAlt), rAlt)
    }

    func testMaskForRightShiftUsage() {
        XCTAssertEqual(deviceModifierMask(forKeyboardUsage: kHIDUsage_KeyboardRightShift), rShift)
    }

    func testMaskForRightControlUsage() {
        XCTAssertEqual(deviceModifierMask(forKeyboardUsage: kHIDUsage_KeyboardRightControl), rCtrl)
    }

    func testMaskForUnmappedUsageIsZero() {
        XCTAssertEqual(deviceModifierMask(forKeyboardUsage: 0), 0)
    }

    // MARK: rightToggleKeyDidPress(changed:current:toggleKeyUsage:)

    func testRightCommandPressTogglesWhenConfigured() {
        // Right Command pressed from a clean state: both device + independent bit set.
        let current = indepCmd | rCmd
        let changed = current // previous was 0
        XCTAssertTrue(rightToggleKeyDidPress(changed: changed,
                                             current: current,
                                             toggleKeyUsage: kHIDUsage_KeyboardRightGUI))
    }

    func testRightCommandReleaseDoesNotToggle() {
        // Right Command released: the bit changed, but is no longer set in current.
        let changed = indepCmd | rCmd
        let current: UInt = 0
        XCTAssertFalse(rightToggleKeyDidPress(changed: changed,
                                              current: current,
                                              toggleKeyUsage: kHIDUsage_KeyboardRightGUI))
    }

    func testLeftCommandDoesNotToggleRightToggleKey() {
        // Left Command sets the device-independent command bit + LEFT device bit,
        // never the right device bit, so it must not be mistaken for the toggle.
        let current = indepCmd | lCmd
        let changed = current
        XCTAssertFalse(rightToggleKeyDidPress(changed: changed,
                                              current: current,
                                              toggleKeyUsage: kHIDUsage_KeyboardRightGUI))
    }

    func testUnrelatedModifierDoesNotToggle() {
        // Shift pressed while toggle key is right Command: no right-command bit.
        let current = UInt(NSEvent.ModifierFlags.shift.rawValue) | rShift
        let changed = current
        XCTAssertFalse(rightToggleKeyDidPress(changed: changed,
                                              current: current,
                                              toggleKeyUsage: kHIDUsage_KeyboardRightGUI))
    }

    func testRightAltConfiguredTogglesOnRightAltPress() {
        // Default toggle key is right Alt — pressing it must toggle.
        let current = UInt(NSEvent.ModifierFlags.option.rawValue) | rAlt
        let changed = current
        XCTAssertTrue(rightToggleKeyDidPress(changed: changed,
                                             current: current,
                                             toggleKeyUsage: kHIDUsage_KeyboardRightAlt))
    }

    func testDisabledToggleKeyNeverPresses() {
        // toggleKeyUsage 0 (disabled) → never reports a press, even if cmd held.
        let current = indepCmd | rCmd
        XCTAssertFalse(rightToggleKeyDidPress(changed: current,
                                              current: current,
                                              toggleKeyUsage: 0))
    }

    func testNoChangeMeansNoPressEvenIfHeld() {
        // Key already held (present in current) but not part of this event's change:
        // a different modifier toggled. The right toggle key must NOT re-fire.
        let current = indepCmd | rCmd | UInt(NSEvent.ModifierFlags.shift.rawValue) | rShift
        let changed = UInt(NSEvent.ModifierFlags.shift.rawValue) | rShift // only shift changed
        XCTAssertFalse(rightToggleKeyDidPress(changed: changed,
                                              current: current,
                                              toggleKeyUsage: kHIDUsage_KeyboardRightGUI))
    }
}
