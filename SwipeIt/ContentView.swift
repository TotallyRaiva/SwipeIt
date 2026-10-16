//
//  ContentView.swift
//  SwipeIt
//
//  Created by Reiwa on 16.10.2026.
//

import SwiftUI

struct ContentView: View {
    @Bindable var lockManager: LockManager
    @Bindable var settings: SettingsStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                accessibilityBanner
                quickActionsSection
                shortcutsSection
                displayAndPrivacySection
                safetyAndMasterKeySection
                footerSection
            }
            .padding(24)
        }
        .frame(minWidth: 600, idealWidth: 640, minHeight: 680, idealHeight: 740)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - 1. Header

    private var headerSection: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.blue, .indigo],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 52, height: 52)

                Image(systemName: lockManager.lockMode.systemImage)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text("SwipeIt")
                        .font(.system(size: 22, weight: .bold, design: .rounded))

                    Text(lockManager.lockMode.shortTitle)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(lockManager.lockMode.isLocked ? Color.orange.opacity(0.2) : Color.green.opacity(0.18))
                        )
                        .foregroundStyle(lockManager.lockMode.isLocked ? .orange : .green)
                }

                Text("Lightweight keyboard & trackpad locker for cleaning and safety.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let remaining = lockManager.formattedRemainingTime, lockManager.lockMode.isLocked {
                Label(remaining, systemImage: "timer")
                    .font(.system(.callout, design: .monospaced, weight: .semibold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.orange.opacity(0.12), in: Capsule())
            }
        }
    }

    // MARK: - 2. Accessibility Status Banner

    @ViewBuilder
    private var accessibilityBanner: some View {
        if !lockManager.accessibility.isTrusted {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Accessibility Permission Required")
                        .font(.subheadline.weight(.semibold))
                    Text("macOS requires Accessibility access so SwipeIt can intercept and block keyboard and trackpad events.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Grant Access") {
                    lockManager.accessibility.requestPermission()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.orange.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.orange.opacity(0.35), lineWidth: 1)
            )
        } else if let statusMessage = lockManager.statusBannerMessage {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - 3. Quick Lock Actions

    private var quickActionsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Button {
                        lockManager.lock(mode: .keyboardAndMouse)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "lock.fill")
                                .font(.title3)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Lock Keyboard & Trackpad")
                                    .font(.callout.weight(.semibold))
                                Text("Shortcut: \(settings.lockAllShortcut.displayString)")
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.8))
                            }
                            Spacer()
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)

                    Button {
                        lockManager.lock(mode: .keyboardOnly)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "keyboard.badge.ellipsis")
                                .font(.title3)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Lock Keyboard Only")
                                    .font(.callout.weight(.semibold))
                                Text("Shortcut: \(settings.lockKeyboardOnlyShortcut.displayString)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                if lockManager.lockMode.isLocked {
                    Button {
                        lockManager.unlock(reason: .manualUI)
                    } label: {
                        Label("Unlock Now (\(settings.unlockShortcut.displayString))", systemImage: "lock.open.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                }
            }
            .padding(6)
        } label: {
            Label("Quick Lock Controls", systemImage: "bolt.shield")
                .font(.headline)
        }
    }

    // MARK: - 4. Custom Key Combinations

    private var shortcutsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                ShortcutRecorderRow(
                    title: "Lock Keyboard + Trackpad/Mouse",
                    subtitle: "Blocks all keys, media buttons, cursor movement, clicks, and trackpad gestures.",
                    combo: $settings.lockAllShortcut,
                    onCommit: { lockManager.syncInterceptorConfiguration() },
                    onRecordingStateChange: { lockManager.isRecordingShortcut = $0 }
                )

                Divider()

                ShortcutRecorderRow(
                    title: "Lock Keyboard Only",
                    subtitle: "Blocks all keyboard and media keys while keeping mouse & trackpad active.",
                    combo: $settings.lockKeyboardOnlyShortcut,
                    onCommit: { lockManager.syncInterceptorConfiguration() },
                    onRecordingStateChange: { lockManager.isRecordingShortcut = $0 }
                )

                Divider()

                ShortcutRecorderRow(
                    title: "Custom Unlock Combination",
                    subtitle: "Unlocks your Mac from either lock mode. Click the badge to record your own combo.",
                    combo: $settings.unlockShortcut,
                    onCommit: { lockManager.syncInterceptorConfiguration() },
                    onRecordingStateChange: { lockManager.isRecordingShortcut = $0 }
                )

                Divider()

                Toggle(isOn: $settings.allowToggleWithLockShortcut) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Allow Lock Shortcut to Toggle Unlock")
                            .font(.body)
                        Text("When enabled, pressing the active Lock shortcut a second time will also unlock.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: settings.allowToggleWithLockShortcut) { _, _ in
                    lockManager.syncInterceptorConfiguration()
                }

                Toggle(isOn: $settings.enableGlobalShortcuts) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable Global Lock Hotkeys")
                            .font(.body)
                        Text("Listen for Lock shortcuts anywhere in macOS while SwipeIt is running.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: settings.enableGlobalShortcuts) { _, _ in
                    lockManager.syncInterceptorConfiguration()
                }
            }
            .padding(6)
        } label: {
            Label("Custom Key Combinations", systemImage: "command.square")
                .font(.headline)
        }
    }

    // MARK: - 5. Screen & Unlock Hint Visibility

    private var displayAndPrivacySection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Locked Screen Appearance", selection: $settings.overlayStyle) {
                    ForEach(OverlayStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.segmented)

                Text(settings.overlayStyle.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()

                Toggle(isOn: $settings.showUnlockHintOnScreen) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show Unlock Option & Shortcut on Screen")
                            .font(.body.weight(.medium))
                        Text("Turn OFF for child/pet/away safety so nobody looking at your screen can see the unlock combo.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(6)
        } label: {
            Label("Screen Overlay & Privacy", systemImage: "display")
                .font(.headline)
        }
    }

    // MARK: - 6. Master Key & Auto-Unlock Safety Timer

    private var safetyAndMasterKeySection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                // Master Key Info Row
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "key.horizontal.fill")
                        .font(.title2)
                        .foregroundStyle(.yellow)
                        .frame(width: 32)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Emergency Master Key (\"Combowombo\")")
                            .font(.body.weight(.semibold))
                        Text("Forgot your custom combo? Press these 4 keys simultaneously at any time to unlock:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(KeyCombo.masterUnlockKey.displayString)
                        .font(.system(.callout, design: .monospaced, weight: .bold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.yellow.opacity(0.45), lineWidth: 1)
                        )
                }

                Divider()

                // Auto-Unlock Timer Controls
                Toggle(isOn: $settings.autoUnlockTimerEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Automatic Safety Unlock Timer")
                            .font(.body.weight(.medium))
                        Text("Automatically unlocks your Mac after the timer expires in case all combinations are forgotten.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if settings.autoUnlockTimerEnabled {
                    HStack(spacing: 12) {
                        Text("Auto-unlock duration:")
                            .font(.callout)

                        Stepper(
                            value: $settings.autoUnlockMinutes,
                            in: 1...120,
                            step: 1
                        ) {
                            Text("\(settings.autoUnlockMinutes) min")
                                .font(.system(.callout, design: .monospaced, weight: .semibold))
                        }

                        Spacer()

                        HStack(spacing: 6) {
                            ForEach([5, 10, 15, 30, 60], id: \.self) { preset in
                                Button("\(preset)m") {
                                    settings.autoUnlockMinutes = preset
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .tint(settings.autoUnlockMinutes == preset ? .blue : .secondary)
                            }
                        }
                    }
                    .padding(.top, 2)
                }
            }
            .padding(6)
        } label: {
            Label("Fail-Safe Recovery & Master Key", systemImage: "lifepreserver")
                .font(.headline)
        }
    }

    // MARK: - 7. Footer

    private var footerSection: some View {
        HStack {
            Text("Free & Open Source (MIT) • Zero Ads • Zero Telemetry")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button("Restore Default Shortcuts & Settings") {
                settings.resetToDefaults()
                lockManager.syncInterceptorConfiguration()
            }
            .buttonStyle(.link)
            .font(.caption)
        }
        .padding(.top, 4)
    }
}

#Preview {
    let settings = SettingsStore()
    let manager = LockManager(settings: settings)
    ContentView(lockManager: manager, settings: settings)
}
