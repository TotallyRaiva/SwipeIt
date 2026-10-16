//
//  SettingsStore.swift
//  SwipeIt
//
//  Created by Reiwa on 16.10.2026.
//

import Foundation
import Observation

/// Manages and persists user preferences, custom shortcuts, and safety timer settings.
@Observable
public final class SettingsStore {
    private let defaults: UserDefaults

    private enum Keys {
        static let lockAllShortcut = "SwipeIt.lockAllShortcut"
        static let lockKeyboardOnlyShortcut = "SwipeIt.lockKeyboardOnlyShortcut"
        static let unlockShortcut = "SwipeIt.unlockShortcut"
        static let allowToggleWithLockShortcut = "SwipeIt.allowToggleWithLockShortcut"
        static let showUnlockHintOnScreen = "SwipeIt.showUnlockHintOnScreen"
        static let overlayStyle = "SwipeIt.overlayStyle"
        static let autoUnlockTimerEnabled = "SwipeIt.autoUnlockTimerEnabled"
        static let autoUnlockMinutes = "SwipeIt.autoUnlockMinutes"
        static let enableGlobalShortcuts = "SwipeIt.enableGlobalShortcuts"
    }

    /// Custom shortcut to lock Keyboard + Mouse/Trackpad.
    public var lockAllShortcut: KeyCombo {
        didSet { saveCodable(lockAllShortcut, forKey: Keys.lockAllShortcut) }
    }

    /// Custom shortcut to lock Keyboard Only (leaving Mouse/Trackpad active).
    public var lockKeyboardOnlyShortcut: KeyCombo {
        didSet { saveCodable(lockKeyboardOnlyShortcut, forKey: Keys.lockKeyboardOnlyShortcut) }
    }

    /// Custom shortcut to unlock the device.
    public var unlockShortcut: KeyCombo {
        didSet { saveCodable(unlockShortcut, forKey: Keys.unlockShortcut) }
    }

    /// If true, pressing the lock shortcut while locked will also toggle unlock.
    public var allowToggleWithLockShortcut: Bool {
        didSet { defaults.set(allowToggleWithLockShortcut, forKey: Keys.allowToggleWithLockShortcut) }
    }

    /// Separate setting to show or hide the unlock option/instructions on the screen when locked.
    public var showUnlockHintOnScreen: Bool {
        didSet { defaults.set(showUnlockHintOnScreen, forKey: Keys.showUnlockHintOnScreen) }
    }

    /// Visual style of the lock screen (Blackout Cleaning Screen, Frosted Shield, or Stealth/Invisible).
    public var overlayStyle: OverlayStyle {
        didSet { defaults.set(overlayStyle.rawValue, forKey: Keys.overlayStyle) }
    }

    /// Safety fail-safe: automatically unlock after `autoUnlockMinutes` if user forgets all combos.
    public var autoUnlockTimerEnabled: Bool {
        didSet { defaults.set(autoUnlockTimerEnabled, forKey: Keys.autoUnlockTimerEnabled) }
    }

    /// Duration in minutes before automatic safety unlock triggers (default: 10 minutes).
    public var autoUnlockMinutes: Int {
        didSet {
            let clamped = max(1, min(120, autoUnlockMinutes))
            if autoUnlockMinutes != clamped {
                autoUnlockMinutes = clamped
            }
            defaults.set(autoUnlockMinutes, forKey: Keys.autoUnlockMinutes)
        }
    }

    /// Whether global keyboard shortcuts to trigger lock when unlocked are active.
    public var enableGlobalShortcuts: Bool {
        didSet { defaults.set(enableGlobalShortcuts, forKey: Keys.enableGlobalShortcuts) }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        self.lockAllShortcut = Self.loadCodable(from: defaults, forKey: Keys.lockAllShortcut) ?? .defaultLockAll
        self.lockKeyboardOnlyShortcut = Self.loadCodable(from: defaults, forKey: Keys.lockKeyboardOnlyShortcut) ?? .defaultLockKeyboardOnly
        self.unlockShortcut = Self.loadCodable(from: defaults, forKey: Keys.unlockShortcut) ?? .defaultUnlock

        if defaults.object(forKey: Keys.allowToggleWithLockShortcut) != nil {
            self.allowToggleWithLockShortcut = defaults.bool(forKey: Keys.allowToggleWithLockShortcut)
        } else {
            self.allowToggleWithLockShortcut = false
        }

        if defaults.object(forKey: Keys.showUnlockHintOnScreen) != nil {
            self.showUnlockHintOnScreen = defaults.bool(forKey: Keys.showUnlockHintOnScreen)
        } else {
            self.showUnlockHintOnScreen = true
        }

        if let rawStyle = defaults.string(forKey: Keys.overlayStyle),
           let style = OverlayStyle(rawValue: rawStyle) {
            self.overlayStyle = style
        } else {
            self.overlayStyle = .blackoutCleaning
        }

        if defaults.object(forKey: Keys.autoUnlockTimerEnabled) != nil {
            self.autoUnlockTimerEnabled = defaults.bool(forKey: Keys.autoUnlockTimerEnabled)
        } else {
            self.autoUnlockTimerEnabled = true
        }

        let storedMinutes = defaults.integer(forKey: Keys.autoUnlockMinutes)
        self.autoUnlockMinutes = storedMinutes > 0 ? max(1, min(120, storedMinutes)) : 10

        if defaults.object(forKey: Keys.enableGlobalShortcuts) != nil {
            self.enableGlobalShortcuts = defaults.bool(forKey: Keys.enableGlobalShortcuts)
        } else {
            self.enableGlobalShortcuts = true
        }
    }

    /// Resets all shortcuts and preferences to their factory defaults.
    public func resetToDefaults() {
        lockAllShortcut = .defaultLockAll
        lockKeyboardOnlyShortcut = .defaultLockKeyboardOnly
        unlockShortcut = .defaultUnlock
        allowToggleWithLockShortcut = false
        showUnlockHintOnScreen = true
        overlayStyle = .blackoutCleaning
        autoUnlockTimerEnabled = true
        autoUnlockMinutes = 10
        enableGlobalShortcuts = true
    }

    private func saveCodable<T: Encodable>(_ value: T, forKey key: String) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }

    private static func loadCodable<T: Decodable>(from defaults: UserDefaults, forKey key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
