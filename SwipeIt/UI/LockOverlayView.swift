//
//  LockOverlayView.swift
//  SwipeIt
//
//  Created by Reiwa on 16.10.2026.
//

import SwiftUI

/// Full-screen overlay displayed on each connected monitor while input is locked.
public struct LockOverlayView: View {
    public let lockManager: LockManager
    public let settings: SettingsStore
    public let isPrimaryScreen: Bool

    public init(lockManager: LockManager, settings: SettingsStore, isPrimaryScreen: Bool = true) {
        self.lockManager = lockManager
        self.settings = settings
        self.isPrimaryScreen = isPrimaryScreen
    }

    public var body: some View {
        ZStack {
            backgroundLayer

            if isPrimaryScreen {
                centerContent
            }
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var backgroundLayer: some View {
        switch settings.overlayStyle {
        case .blackoutCleaning:
            Color.black
        case .frostedHUD:
            ZStack {
                Color.black.opacity(0.68)
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
            }
        case .invisible:
            Color.clear
        }
    }

    @ViewBuilder
    private var centerContent: some View {
        if settings.showUnlockHintOnScreen {
            VStack(spacing: 20) {
                Image(systemName: lockManager.lockMode.systemImage)
                    .font(.system(size: 46, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .symbolEffect(.pulse, options: .repeating)

                VStack(spacing: 6) {
                    Text(lockManager.lockMode.title)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text(lockManager.lockMode == .keyboardAndMouse
                         ? "Safe to wipe keyboard, trackpad, and screen."
                         : "Keyboard is locked. Mouse & trackpad remain active.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.65))
                }

                // Unlock Shortcut Pill
                VStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Text("Press")
                            .foregroundStyle(.white.opacity(0.75))
                        Text(settings.unlockShortcut.displayString)
                            .font(.system(.body, design: .monospaced, weight: .bold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 8))
                            .foregroundStyle(.white)
                        Text("to Unlock")
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    .font(.callout)

                    if settings.allowToggleWithLockShortcut {
                        let toggleCombo = lockManager.lockMode == .keyboardAndMouse
                            ? settings.lockAllShortcut.displayString
                            : settings.lockKeyboardOnlyShortcut.displayString
                        Text("Or press \(toggleCombo) again to toggle unlock")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                .padding(.top, 4)

                // Auto-Unlock Countdown Timer Badge
                if settings.autoUnlockTimerEnabled, let remaining = lockManager.formattedRemainingTime {
                    HStack(spacing: 6) {
                        Image(systemName: "timer")
                        Text("Auto-unlocks in \(remaining)")
                            .monospacedDigit()
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange.opacity(0.9))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.orange.opacity(0.14), in: Capsule())
                }

                // If only the keyboard is locked, the pointer is free, so provide a clickable Unlock button when hints are enabled
                if lockManager.lockMode == .keyboardOnly {
                    Button {
                        lockManager.unlock(reason: .manualUI)
                    } label: {
                        Label("Click to Unlock Keyboard", systemImage: "lock.open.fill")
                            .font(.callout.weight(.semibold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .padding(.top, 6)
                }
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.black.opacity(settings.overlayStyle == .invisible ? 0.82 : 0.45))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.45), radius: 24, y: 8)
        } else {
            // Unlock hint is hidden by user setting (Safety / Child / Away mode)
            if settings.overlayStyle != .invisible {
                VStack(spacing: 12) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundStyle(.white.opacity(0.22))
                }
            }
        }
    }
}
