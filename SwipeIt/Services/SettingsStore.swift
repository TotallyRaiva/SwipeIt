//
//  SettingsStore.swift
//  SwipeIt
//
//  Created by Reiwa on 16.10.2026.
//

import Foundation
import Observation

/// Target action when configuring a custom shortcut.
public enum ShortcutTarget: String, Sendable, CaseIterable {
    case lockAll = "Lock Keyboard & Trackpad"
    case lockKeyboardOnly = "Lock Keyboard Only"
    case unlock = "Unlock"
}

/// Manages and persists user preferences, custom shortcuts, and safety timer settings.
@Observable
public final class SettingsStore: @unchecked Sendable {
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
        static let automaticallyCheckForUpdates = "SwipeIt.automaticallyCheckForUpdates"
        static let lastUpdateCheckTimestamp = "SwipeIt.lastUpdateCheckTimestamp"
    }

    /// Closure invoked whenever any setting property changes.
    public var onSettingsChanged: (() -> Void)?

    private func notifyChanged() {
        onSettingsChanged?()
    }

    /// Custom shortcut to lock Keyboard + Mouse/Trackpad.
    public var lockAllShortcut: KeyCombo {
        didSet {
            saveCodable(lockAllShortcut, forKey: Keys.lockAllShortcut)
            notifyChanged()
        }
    }

    /// Custom shortcut to lock Keyboard Only (leaving Mouse/Trackpad active).
    public var lockKeyboardOnlyShortcut: KeyCombo {
        didSet {
            saveCodable(lockKeyboardOnlyShortcut, forKey: Keys.lockKeyboardOnlyShortcut)
            notifyChanged()
        }
    }

    /// Custom shortcut to unlock the device.
    public var unlockShortcut: KeyCombo {
        didSet {
            saveCodable(unlockShortcut, forKey: Keys.unlockShortcut)
            notifyChanged()
        }
    }

    /// If true, pressing the lock shortcut while locked will also toggle unlock.
    public var allowToggleWithLockShortcut: Bool {
        didSet {
            defaults.set(allowToggleWithLockShortcut, forKey: Keys.allowToggleWithLockShortcut)
            notifyChanged()
        }
    }

    /// Separate setting to show or hide the unlock option/instructions on the screen when locked.
    public var showUnlockHintOnScreen: Bool {
        didSet {
            defaults.set(showUnlockHintOnScreen, forKey: Keys.showUnlockHintOnScreen)
            notifyChanged()
        }
    }

    /// Visual style of the lock screen (Blackout Cleaning Screen, Frosted Shield, or Stealth/Invisible).
    public var overlayStyle: OverlayStyle {
        didSet {
            defaults.set(overlayStyle.rawValue, forKey: Keys.overlayStyle)
            notifyChanged()
        }
    }

    /// Safety fail-safe: automatically unlock after `autoUnlockMinutes` if user forgets all combos.
    public var autoUnlockTimerEnabled: Bool {
        didSet {
            defaults.set(autoUnlockTimerEnabled, forKey: Keys.autoUnlockTimerEnabled)
            notifyChanged()
        }
    }

    /// Duration in minutes before automatic safety unlock triggers (default: 10 minutes).
    public var autoUnlockMinutes: Int {
        didSet {
            let clamped = max(1, min(120, autoUnlockMinutes))
            if autoUnlockMinutes != clamped {
                autoUnlockMinutes = clamped
            }
            defaults.set(autoUnlockMinutes, forKey: Keys.autoUnlockMinutes)
            notifyChanged()
        }
    }

    /// Whether global keyboard shortcuts to trigger lock when unlocked are active.
    public var enableGlobalShortcuts: Bool {
        didSet {
            defaults.set(enableGlobalShortcuts, forKey: Keys.enableGlobalShortcuts)
            notifyChanged()
        }
    }

    /// Whether the app automatically checks GitHub Releases for new updates on startup.
    public var automaticallyCheckForUpdates: Bool {
        didSet {
            defaults.set(automaticallyCheckForUpdates, forKey: Keys.automaticallyCheckForUpdates)
            notifyChanged()
        }
    }

    /// Timestamp of the last update check (epoch seconds).
    public var lastUpdateCheckTimestamp: Double {
        didSet {
            defaults.set(lastUpdateCheckTimestamp, forKey: Keys.lastUpdateCheckTimestamp)
            notifyChanged()
        }
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

        if defaults.object(forKey: Keys.automaticallyCheckForUpdates) != nil {
            self.automaticallyCheckForUpdates = defaults.bool(forKey: Keys.automaticallyCheckForUpdates)
        } else {
            self.automaticallyCheckForUpdates = true
        }

        self.lastUpdateCheckTimestamp = defaults.double(forKey: Keys.lastUpdateCheckTimestamp)
    }

    /// Checks if a proposed shortcut is identical to another configured action or the Master Key.
    public func duplicateCheckMessage(for candidate: KeyCombo, target: ShortcutTarget) -> String? {
        if candidate == KeyCombo.masterUnlockKey {
            return "This combination is reserved by the Emergency Master Key (Esc + ← + ↑ + →)."
        }
        if target != .lockAll && candidate == lockAllShortcut {
            return "This combination is already assigned to 'Lock Keyboard & Trackpad'."
        }
        if target != .lockKeyboardOnly && candidate == lockKeyboardOnlyShortcut {
            return "This combination is already assigned to 'Lock Keyboard Only'."
        }
        if target != .unlock && candidate == unlockShortcut {
            return "This combination is already assigned to 'Unlock'."
        }
        return nil
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
        automaticallyCheckForUpdates = true
        lastUpdateCheckTimestamp = 0
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
