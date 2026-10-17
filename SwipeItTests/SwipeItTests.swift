//
//  SwipeItTests.swift
//  SwipeItTests
//
//  Created by Reiwa on 16.10.2026.
//

import XCTest
import CoreGraphics
@testable import SwipeIt

@MainActor
final class SwipeItTests: XCTestCase {

    func testMasterKeySimultaneousChordUnlocksFromFullLock() {
        let interceptor = InputInterceptor()
        interceptor.currentLockMode = .keyboardAndMouse

        // Simulate macOS arrow-key extra flags (.maskNumericPad | .maskSecondaryFn)
        let arrowExtraFlags = CGEventFlags.maskNumericPad.rawValue | CGEventFlags.maskSecondaryFn.rawValue

        // Press Esc (53), Left (123), Up (126) -> should still swallow (3 of 4 keys held)
        XCTAssertEqual(interceptor.evaluateKeyEvent(keyCode: 53, isKeyDown: true, rawFlags: 0), .swallow)
        XCTAssertEqual(interceptor.evaluateKeyEvent(keyCode: 123, isKeyDown: true, rawFlags: arrowExtraFlags), .swallow)
        XCTAssertEqual(interceptor.evaluateKeyEvent(keyCode: 126, isKeyDown: true, rawFlags: arrowExtraFlags), .swallow)

        // Press 4th key: Right Arrow (124) while previous 3 are still held -> triggers Master Key unlock!
        let fourthKeyDecision = interceptor.evaluateKeyEvent(keyCode: 124, isKeyDown: true, rawFlags: arrowExtraFlags)
        XCTAssertEqual(fourthKeyDecision, .unlock(.masterKey))
        XCTAssertTrue(interceptor.pressedKeyCodes.isEmpty, "Pressed keys should be cleared after Master Key unlock")
    }

    func testSeparateLockAllAndLockKeyboardOnlyShortcuts() {
        let interceptor = InputInterceptor()
        interceptor.currentLockMode = .unlocked

        let mods = CGEventFlags.maskControl.rawValue |
                   CGEventFlags.maskAlternate.rawValue |
                   CGEventFlags.maskCommand.rawValue

        // Pressing Ctrl+Opt+Cmd+K (40) triggers Keyboard-Only Lock
        let kbOnlyDecision = interceptor.evaluateKeyEvent(keyCode: 40, isKeyDown: true, rawFlags: mods)
        XCTAssertEqual(kbOnlyDecision, .lock(.keyboardOnly))

        // Reset to unlocked
        interceptor.currentLockMode = .unlocked

        // Pressing Ctrl+Opt+Cmd+L (37) triggers Full Lock (Keyboard + Mouse/Trackpad)
        let fullLockDecision = interceptor.evaluateKeyEvent(keyCode: 37, isKeyDown: true, rawFlags: mods)
        XCTAssertEqual(fullLockDecision, .lock(.keyboardAndMouse))
    }

    func testAutoRepeatDoesNotTriggerLockOrToggleLoop() {
        let interceptor = InputInterceptor()
        let mods = CGEventFlags.maskControl.rawValue |
                   CGEventFlags.maskAlternate.rawValue |
                   CGEventFlags.maskCommand.rawValue

        interceptor.currentLockMode = .unlocked
        interceptor.allowToggleWithLockShortcut = true

        // First keyDown triggers lock
        let firstPress = interceptor.evaluateKeyEvent(keyCode: 37, isKeyDown: true, rawFlags: mods, isAutorepeat: false)
        XCTAssertEqual(firstPress, .lock(.keyboardAndMouse))
        XCTAssertEqual(interceptor.currentLockMode, .keyboardAndMouse)

        // Subsequent held auto-repeats should NEVER toggle unlock!
        let autoRepeat1 = interceptor.evaluateKeyEvent(keyCode: 37, isKeyDown: true, rawFlags: mods, isAutorepeat: true)
        XCTAssertEqual(autoRepeat1, .swallow)
        XCTAssertEqual(interceptor.currentLockMode, .keyboardAndMouse)

        let autoRepeat2 = interceptor.evaluateKeyEvent(keyCode: 37, isKeyDown: true, rawFlags: mods, isAutorepeat: true)
        XCTAssertEqual(autoRepeat2, .swallow)
        XCTAssertEqual(interceptor.currentLockMode, .keyboardAndMouse)
    }

    func testCustomUnlockAndToggleUnlockBehavior() {
        let interceptor = InputInterceptor()
        let mods = CGEventFlags.maskControl.rawValue |
                   CGEventFlags.maskAlternate.rawValue |
                   CGEventFlags.maskCommand.rawValue

        interceptor.currentLockMode = .keyboardOnly
        interceptor.allowToggleWithLockShortcut = false

        // Random key 'A' (0) while locked is swallowed
        XCTAssertEqual(interceptor.evaluateKeyEvent(keyCode: 0, isKeyDown: true, rawFlags: 0), .swallow)
        XCTAssertEqual(interceptor.evaluateKeyEvent(keyCode: 0, isKeyDown: false, rawFlags: 0), .swallow)

        // Pressing Lock Keyboard-Only shortcut again when toggle is disabled -> swallowed
        XCTAssertEqual(interceptor.evaluateKeyEvent(keyCode: 40, isKeyDown: true, rawFlags: mods), .swallow)
        _ = interceptor.evaluateKeyEvent(keyCode: 40, isKeyDown: false, rawFlags: mods)

        // Enable toggle mode -> pressing Lock Keyboard-Only shortcut now unlocks!
        interceptor.allowToggleWithLockShortcut = true
        XCTAssertEqual(interceptor.evaluateKeyEvent(keyCode: 40, isKeyDown: true, rawFlags: mods), .unlock(.toggleShortcut))

        // Custom Unlock shortcut (Ctrl+Opt+Cmd+U = 32) always unlocks
        interceptor.allowToggleWithLockShortcut = false
        interceptor.currentLockMode = .keyboardOnly
        XCTAssertEqual(interceptor.evaluateKeyEvent(keyCode: 32, isKeyDown: true, rawFlags: mods), .unlock(.customShortcut))
    }

    func testShortcutSafetyValidation() {
        // Safe: Cmd+L, Ctrl+L, Ctrl+Opt+Cmd+L
        let cmdL = KeyCombo(keyCodes: [37], modifiers: CGEventFlags.maskCommand.rawValue)
        XCTAssertTrue(cmdL.isValidUserShortcut)

        let ctrlOptCmdL = KeyCombo.defaultLockAll
        XCTAssertTrue(ctrlOptCmdL.isValidUserShortcut)

        // Safe: 3+ key chords without modifiers (e.g. Master Key)
        let master = KeyCombo.masterUnlockKey
        XCTAssertTrue(master.isValidUserShortcut)

        // Unsafe: Shift + letter alone (e.g. Shift + A) -> typing capital letters
        let shiftA = KeyCombo(keyCodes: [0], modifiers: CGEventFlags.maskShift.rawValue)
        XCTAssertFalse(shiftA.isValidUserShortcut)

        // Unsafe: Two plain letters without modifiers (e.g. J + K)
        let jkChord = KeyCombo(keyCodes: [38, 40], modifiers: 0)
        XCTAssertFalse(jkChord.isValidUserShortcut)

        // Unsafe: Empty
        let empty = KeyCombo(keyCodes: [], modifiers: 0)
        XCTAssertFalse(empty.isValidUserShortcut)
    }

    func testDuplicateShortcutDetection() {
        let store = SettingsStore(defaults: UserDefaults(suiteName: "DuplicateTest.\(UUID().uuidString)")!)

        // Master Key cannot be overridden
        let masterDup = store.duplicateCheckMessage(for: KeyCombo.masterUnlockKey, target: .lockAll)
        XCTAssertNotNil(masterDup)

        // Duplicate with lockAll
        let lockAllDup = store.duplicateCheckMessage(for: store.lockAllShortcut, target: .unlock)
        XCTAssertNotNil(lockAllDup)

        // Self is not duplicate
        let selfMatch = store.duplicateCheckMessage(for: store.lockAllShortcut, target: .lockAll)
        XCTAssertNil(selfMatch)
    }

    func testDynamicEventMaskOmissionWhileUnlocked() {
        let interceptor = InputInterceptor()

        let unlockedMask = interceptor.targetEventMask(for: .unlocked)
        let kbOnlyMask = interceptor.targetEventMask(for: .keyboardOnly)
        let fullLockMask = interceptor.targetEventMask(for: .keyboardAndMouse)

        let mouseMovedBit = UInt64(1 << CGEventType.mouseMoved.rawValue)

        // While unlocked or keyboard-only, mouseMoved is completely omitted
        XCTAssertEqual(unlockedMask & mouseMovedBit, 0)
        XCTAssertEqual(kbOnlyMask & mouseMovedBit, 0)

        // Only in full lock mode is mouseMoved included
        XCTAssertNotEqual(fullLockMask & mouseMovedBit, 0)
    }

    func testSettingsStorePersistenceAndDefaults() {
        let suiteName = "SwipeItTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults)
        XCTAssertTrue(store.showUnlockHintOnScreen)
        XCTAssertTrue(store.autoUnlockTimerEnabled)
        XCTAssertEqual(store.autoUnlockMinutes, 10)
        XCTAssertEqual(store.overlayStyle, .blackoutCleaning)

        // Customize settings
        store.showUnlockHintOnScreen = false
        store.autoUnlockMinutes = 25
        store.overlayStyle = .invisible
        let customUnlock = KeyCombo(keyCodes: [53, 49, 36], modifiers: 0) // 3-key chord
        store.unlockShortcut = customUnlock

        // Reload from same UserDefaults suite
        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertFalse(reloaded.showUnlockHintOnScreen)
        XCTAssertEqual(reloaded.autoUnlockMinutes, 25)
        XCTAssertEqual(reloaded.overlayStyle, .invisible)
        XCTAssertEqual(reloaded.unlockShortcut, customUnlock)

        // Reset to defaults
        reloaded.resetToDefaults()
        XCTAssertTrue(reloaded.showUnlockHintOnScreen)
        XCTAssertEqual(reloaded.autoUnlockMinutes, 10)
        XCTAssertEqual(reloaded.unlockShortcut, .defaultUnlock)
    }
}
