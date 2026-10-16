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
        settings: SettingsStore = SettingsStore(),
        accessibility: AccessibilityManager = AccessibilityManager(),
        interceptor: InputInterceptor = InputInterceptor(),
        overlayManager: OverlayWindowManager = OverlayWindowManager()
    ) {
        self.settings = settings
        self.accessibility = accessibility
        self.interceptor = interceptor
        self.overlayManager = overlayManager

        setupCallbacks()
        syncInterceptorConfiguration()
        startEventTapIfPermitted()
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

        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tickSafetyTimer()
            }
        }
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
            self?.startEventTapIfPermitted()
            self?.statusBannerMessage = "Accessibility permission granted! Global shortcuts are now active."
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
