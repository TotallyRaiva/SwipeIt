//
//  ContentView.swift
//  SwipeIt
//
//  Created by Reiwa on 16.10.2026.
//

import SwiftUI
import AppKit

enum SettingsTab: String, CaseIterable, Identifiable {
    case controls = "Controls"
    case shortcuts = "Shortcuts"
    case safety = "Screen & Safety"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .controls: return "bolt.shield"
        case .shortcuts: return "command.square"
        case .safety: return "display"
        }
    }
}

struct ContentView: View {
    @Bindable var lockManager: LockManager
    @Bindable var settings: SettingsStore
    @State private var selectedTab: SettingsTab = .controls

    var body: some View {
        VStack(spacing: 0) {
            headerSection
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 12)

            tabPickerSection
                .padding(.horizontal, 22)
                .padding(.bottom, 16)

            Divider()

            tabContentSection
                .padding(22)
                .frame(maxHeight: .infinity, alignment: .top)

            Divider()

            footerSection
                .padding(.horizontal, 22)
                .padding(.vertical, 10)
        }
        .frame(minWidth: 540, idealWidth: 580, maxWidth: 640, minHeight: 480, idealHeight: 520, maxHeight: 580)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Header with App Icon & Status

    private var headerSection: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(color: Color.black.opacity(0.18), radius: 3, x: 0, y: 1.5)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text("SwipeIt")
                        .font(.system(size: 20, weight: .bold, design: .rounded))

                    HStack(spacing: 5) {
                        Circle()
                            .fill(lockManager.lockMode.isLocked ? Color.orange : Color.green)
                            .frame(width: 7, height: 7)
                        Text(lockManager.lockMode.shortTitle)
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(lockManager.lockMode.isLocked ? Color.orange.opacity(0.15) : Color.green.opacity(0.12))
                    )
                    .foregroundStyle(lockManager.lockMode.isLocked ? .orange : .green)
                }

                Text("Lightweight keyboard & trackpad locker for cleaning and safety.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let remaining = lockManager.formattedRemainingTime, lockManager.lockMode.isLocked {
                HStack(spacing: 5) {
                    Image(systemName: "timer")
                    Text(remaining)
                        .monospacedDigit()
                }
                .font(.system(.caption, design: .monospaced, weight: .semibold))
                .foregroundStyle(.orange)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color.orange.opacity(0.12), in: Capsule())
            }
        }
    }

    // MARK: - Tab Segmented Picker

    private var tabPickerSection: some View {
        Picker("Category", selection: $selectedTab) {
            ForEach(SettingsTab.allCases) { tab in
                Label(tab.rawValue, systemImage: tab.icon).tag(tab)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Tab Content Switcher

    @ViewBuilder
    private var tabContentSection: some View {
        switch selectedTab {
        case .controls:
            controlsTabView
        case .shortcuts:
            shortcutsTabView
        case .safety:
            safetyTabView
        }
    }

    // MARK: - 1. Controls Tab

    private var controlsTabView: some View {
        VStack(spacing: 16) {
            if !lockManager.accessibility.isTrusted {
                accessibilityAlertCard
            }

            if lockManager.lockMode.isLocked {
                VStack(spacing: 12) {
                    Text("Input is currently locked.")
                        .font(.headline)
                        .foregroundStyle(.orange)

                    Button {
                        lockManager.unlock(reason: .manualUI)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "lock.open.fill")
                            Text("Unlock Input Now")
                        }
                        .font(.body.weight(.semibold))
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                }
                .padding(20)
                .frame(maxWidth: .infinity)
                .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            } else {
                HStack(spacing: 14) {
                    quickActionCard(
                        title: "Full Lock",
                        subtitle: "Keyboard + Trackpad",
                        icon: "lock.fill",
                        tintColor: .blue,
                        shortcutTokens: settings.lockAllShortcut.keyTokens
                    ) {
                        lockManager.lock(mode: .keyboardAndMouse)
                    }

                    quickActionCard(
                        title: "Keyboard Only",
                        subtitle: "Mouse stays active",
                        icon: "keyboard.badge.ellipsis",
                        tintColor: .indigo,
                        shortcutTokens: settings.lockKeyboardOnlyShortcut.keyTokens
                    ) {
                        lockManager.lock(mode: .keyboardOnly)
                    }
                }
            }

            // Quick Status & Rescue Reminder Pill
            HStack(spacing: 10) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                Text("Unlock with")
                    .foregroundStyle(.secondary)
                KeycapBadgeView(tokens: settings.unlockShortcut.keyTokens)
                Text("or emergency Master Key")
                    .foregroundStyle(.secondary)
                KeycapBadgeView(tokens: KeyCombo.masterUnlockKey.keyTokens)
            }
            .font(.caption)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        }
    }

    private func quickActionCard(
        title: String,
        subtitle: String,
        icon: String,
        tintColor: Color,
        shortcutTokens: [String],
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(tintColor.opacity(0.16))
                        .frame(width: 38, height: 38)
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(tintColor)
                }

                Spacer()

                KeycapBadgeView(tokens: shortcutTokens)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.bold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button(action: action) {
                Text("Lock Now")
                    .font(.callout.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
            }
            .buttonStyle(.borderedProminent)
            .tint(tintColor)
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var accessibilityAlertCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.title3)
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 1) {
                Text("Accessibility Access Needed")
                    .font(.subheadline.weight(.semibold))
                Text("Required by macOS to block keyboard and mouse events.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Grant Access") {
                lockManager.accessibility.requestPermission()
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .controlSize(.small)
        }
        .padding(12)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.orange.opacity(0.3), lineWidth: 1))
    }

    // MARK: - 2. Shortcuts Tab

    private var shortcutsTabView: some View {
        VStack(spacing: 14) {
            VStack(spacing: 12) {
                ShortcutRecorderRow(
                    title: "Full Lock (Keyboard + Trackpad)",
                    subtitle: "Blocks all keys, clicks, and gestures",
                    combo: $settings.lockAllShortcut,
                    duplicateCheck: { settings.duplicateCheckMessage(for: $0, target: .lockAll) },
                    onCommit: { lockManager.syncInterceptorConfiguration() },
                    onRecordingStateChange: { lockManager.isRecordingShortcut = $0 }
                )

                Divider()

                ShortcutRecorderRow(
                    title: "Keyboard Only Lock",
                    subtitle: "Blocks keyboard while mouse stays free",
                    combo: $settings.lockKeyboardOnlyShortcut,
                    duplicateCheck: { settings.duplicateCheckMessage(for: $0, target: .lockKeyboardOnly) },
                    onCommit: { lockManager.syncInterceptorConfiguration() },
                    onRecordingStateChange: { lockManager.isRecordingShortcut = $0 }
                )

                Divider()

                ShortcutRecorderRow(
                    title: "Custom Unlock Combination",
                    subtitle: "Unlocks your Mac from any lock mode",
                    combo: $settings.unlockShortcut,
                    duplicateCheck: { settings.duplicateCheckMessage(for: $0, target: .unlock) },
                    onCommit: { lockManager.syncInterceptorConfiguration() },
                    onRecordingStateChange: { lockManager.isRecordingShortcut = $0 }
                )
            }
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))

            VStack(spacing: 12) {
                Toggle(isOn: $settings.allowToggleWithLockShortcut) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Allow Lock Shortcut to Toggle Unlock")
                            .font(.body.weight(.medium))
                        Text("Pressing the active lock shortcut again will immediately unlock.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .onChange(of: settings.allowToggleWithLockShortcut) { _, _ in
                    lockManager.syncInterceptorConfiguration()
                }

                Divider()

                Toggle(isOn: $settings.enableGlobalShortcuts) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Enable Global Shortcuts")
                            .font(.body.weight(.medium))
                        Text("Listen for hotkeys anywhere in macOS while SwipeIt is running.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .onChange(of: settings.enableGlobalShortcuts) { _, _ in
                    lockManager.syncInterceptorConfiguration()
                }
            }
            .padding(14)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        }
    }

    // MARK: - 3. Screen & Safety Tab

    private var safetyTabView: some View {
        VStack(spacing: 14) {
            // Screen Overlay Style
            VStack(alignment: .leading, spacing: 8) {
                Text("Locked Screen Appearance")
                    .font(.subheadline.weight(.semibold))

                Picker("Appearance", selection: $settings.overlayStyle) {
                    ForEach(OverlayStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.segmented)

                Text(settings.overlayStyle.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
            .padding(14)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))

            // Screen Privacy & Auto-Unlock Timer
            VStack(spacing: 12) {
                Toggle(isOn: $settings.showUnlockHintOnScreen) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Show Unlock Instructions on Screen")
                            .font(.body.weight(.medium))
                        Text("Turn OFF for privacy so nobody watching can see how to unlock.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)

                Divider()

                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Automatic Safety Timer")
                            .font(.body.weight(.medium))
                        Text("Auto-unlocks if all combinations are forgotten.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Toggle("", isOn: $settings.autoUnlockTimerEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }

                if settings.autoUnlockTimerEnabled {
                    HStack(spacing: 10) {
                        Stepper(value: $settings.autoUnlockMinutes, in: 1...120) {
                            Text("\(settings.autoUnlockMinutes) minutes")
                                .font(.system(.body, design: .monospaced, weight: .semibold))
                        }

                        Spacer()

                        HStack(spacing: 5) {
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
            .padding(14)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))

            // Master Key Rescue Card
            HStack(spacing: 12) {
                Image(systemName: "key.horizontal.fill")
                    .font(.title3)
                    .foregroundStyle(.yellow)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Emergency Master Key (\"Combowombo\")")
                        .font(.subheadline.weight(.semibold))
                    Text("Press all 4 keys simultaneously at any time:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                KeycapBadgeView(tokens: KeyCombo.masterUnlockKey.keyTokens)
            }
            .padding(12)
            .background(Color.yellow.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.yellow.opacity(0.3), lineWidth: 1))
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack {
            Text("Free & Open Source (MIT) • Zero Ads")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Spacer()

            Button("Restore Defaults") {
                settings.resetToDefaults()
                lockManager.syncInterceptorConfiguration()
            }
            .buttonStyle(.link)
            .font(.caption2)
        }
    }
}
