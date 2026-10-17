//
//  LockManager.swift
//  SwipeIt
//
//  Created by Reiwa on 16.10.2026.
//

import Foundation
import AppKit
import Observation

/// Central state machine coordinating input interception, lock modes, overlays, and the safety countdown timer.
@Observable
@MainActor
public final class LockManager {
    public let settings: SettingsStore
    public let accessibility: AccessibilityManager
    public let interceptor: InputInterceptor
    private let overlayManager: OverlayWindowManager

    public private(set) var lockMode: LockMode = .unlocked
    public private(set) var remainingSeconds: Int?
    public private(set) var lastUnlockReason: UnlockReason?
    public private(set) var statusBannerMessage: String?

    private var countdownTimer: Timer?
    private var screenObserver: NSObjectProtocol?

    public var isRecordingShortcut: Bool = false {
        didSet {
            interceptor.isRecordingShortcut = isRecordingShortcut
        }
    }

    public var formattedRemainingTime: String? {
        guard let seconds = remainingSeconds, seconds >= 0 else { return nil }
        let mins = seconds / 60
        let secs = seconds % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    public init(
        settings: SettingsStore,
        accessibility: AccessibilityManager = AccessibilityManager(),
        interceptor: InputInterceptor = InputInterceptor()
    ) {
        self.settings = settings
        self.accessibility = accessibility
        self.interceptor = interceptor
        self.overlayManager = OverlayWindowManager()

        setupCallbacks()
        syncInterceptorConfiguration()
        startEventTapIfPermitted()
    }

    public convenience init() {
        self.init(settings: SettingsStore())
    }

    // MARK: - Lock / Unlock Actions

    /// Activates the requested lock mode (Full Lock or Keyboard-Only Lock).
    public func lock(mode: LockMode) {
        guard mode != .unlocked else {
            unlock(reason: .manualUI)
            return
        }

        syncInterceptorConfiguration()

        // Ensure Accessibility permission and active CGEventTap before locking
        if !accessibility.checkPermission(prompt: false) {
            statusBannerMessage = "Accessibility permission is required to lock input."
            accessibility.requestPermission()
            return
        }

        if !interceptor.start() {
            statusBannerMessage = "Could not start input event tap. Check Accessibility permissions."
            return
        }

        lockMode = mode
        interceptor.currentLockMode = mode
        statusBannerMessage = nil

        startSafetyTimerIfNeeded()
        overlayManager.showOverlays(lockManager: self, settings: settings)
    }

    /// Unlocks all blocked inputs and dismisses any lock overlay windows.
    public func unlock(reason: UnlockReason = .manualUI) {
        stopSafetyTimer()
        lockMode = .unlocked
        interceptor.currentLockMode = .unlocked
        interceptor.resetPressedKeys()
        overlayManager.hideOverlays()
        lastUnlockReason = reason
        statusBannerMessage = "Unlocked via \(reason.rawValue)"
    }

    /// Synchronizes current SettingsStore values to the low-level InputInterceptor.
    public func syncInterceptorConfiguration() {
        interceptor.lockAllShortcut = settings.lockAllShortcut
        interceptor.lockKeyboardOnlyShortcut = settings.lockKeyboardOnlyShortcut
        interceptor.unlockShortcut = settings.unlockShortcut
        interceptor.allowToggleWithLockShortcut = settings.allowToggleWithLockShortcut
        interceptor.enableGlobalShortcuts = settings.enableGlobalShortcuts
    }

    /// Re-evaluates timer and interceptor settings when configuration changes dynamically.
    public func handleSettingsChanged() {
        syncInterceptorConfiguration()
        if lockMode != .unlocked {
            if !settings.autoUnlockTimerEnabled {
                stopSafetyTimer()
            } else if let currentRemaining = remainingSeconds {
                let maxSeconds = max(1, settings.autoUnlockMinutes) * 60
                if currentRemaining > maxSeconds {
                    remainingSeconds = maxSeconds
                }
            } else {
                startSafetyTimerIfNeeded()
            }
        }
    }

    @discardableResult
    public func startEventTapIfPermitted() -> Bool {
        syncInterceptorConfiguration()
        guard accessibility.checkPermission(prompt: false) else {
            return false
        }
        return interceptor.start()
    }

    // MARK: - Auto-Unlock Safety Timer

    private func startSafetyTimerIfNeeded() {
        stopSafetyTimer()
        guard settings.autoUnlockTimerEnabled else {
            remainingSeconds = nil
            return
        }

        let totalSeconds = max(1, settings.autoUnlockMinutes) * 60
        remainingSeconds = totalSeconds

        // Schedule on .commonModes so timer ticks continuously even when menus or popups are tracking events
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tickSafetyTimer()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        countdownTimer = timer
    }

    private func tickSafetyTimer() {
        guard let current = remainingSeconds else { return }
        if current <= 1 {
            unlock(reason: .autoUnlockTimer)
        } else {
            remainingSeconds = current - 1
        }
    }

    private func stopSafetyTimer() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        remainingSeconds = nil
    }

    // MARK: - Internal Wiring

    private func setupCallbacks() {
        accessibility.onPermissionGranted = { [weak self] in
            Task { @MainActor in
                self?.startEventTapIfPermitted()
                self?.statusBannerMessage = "Accessibility permission granted! Global shortcuts are now active."
            }
        }

        settings.onSettingsChanged = { [weak self] in
            Task { @MainActor in
                self?.handleSettingsChanged()
            }
        }

        interceptor.onAction = { [weak self] action in
            Task { @MainActor in
                guard let self else { return }
                switch action {
                case .lock(let mode):
                    self.lock(mode: mode)
                case .unlock(let reason):
                    self.unlock(reason: reason)
                case .passThrough, .swallow:
                    break
                }
            }
        }

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.lockMode.isLocked else { return }
                self.overlayManager.showOverlays(lockManager: self, settings: self.settings)
            }
        }
    }
}
