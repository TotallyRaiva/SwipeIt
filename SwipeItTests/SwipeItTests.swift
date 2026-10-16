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

        // Pressing Ctrl+Opt+Cmd+L (37) triggers Full Lock (Keyboard + Mouse/Trackpad)
        let fullLockDecision = interceptor.evaluateKeyEvent(keyCode: 37, isKeyDown: true, rawFlags: mods)
        XCTAssertEqual(fullLockDecision, .lock(.keyboardAndMouse))
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
        XCTAssertEqual(interceptor.evaluateKeyEvent(keyCode: 32, isKeyDown: true, rawFlags: mods), .unlock(.customShortcut))
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
        let customUnlock = KeyCombo(keyCodes: [53, 49], modifiers: 0) // Esc + Space chord
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
