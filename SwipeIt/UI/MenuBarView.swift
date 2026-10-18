//
//  MenuBarView.swift
//  SwipeIt
//
//  Created by Reiwa on 16.10.2026.
//

import SwiftUI
import AppKit

/// Menu bar popover/dropdown view providing instant lock controls and quick settings toggles.
public struct MenuBarView: View {
    @Bindable public var lockManager: LockManager
    @Bindable public var settings: SettingsStore
    @Bindable public var updateChecker: UpdateChecker
    @Environment(\.openWindow) private var openWindow

    public init(lockManager: LockManager, settings: SettingsStore, updateChecker: UpdateChecker) {
        self.lockManager = lockManager
        self.settings = settings
        self.updateChecker = updateChecker
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header & Status
            HStack(spacing: 8) {
                Image(systemName: lockManager.lockMode.systemImage)
                    .foregroundStyle(lockManager.lockMode.isLocked ? .orange : .green)
                VStack(alignment: .leading, spacing: 1) {
                    Text("SwipeIt — \(lockManager.lockMode.shortTitle)")
                        .font(.headline)
                    if let remaining = lockManager.formattedRemainingTime, lockManager.lockMode.isLocked {
                        Text("Auto-unlocks in \(remaining)")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    } else if !lockManager.accessibility.isTrusted {
                        Text("Accessibility Permission Needed")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    } else {
                        Text("Ready • Unlock: \(settings.unlockShortcut.displayString)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.bottom, 2)

            Divider()

            if updateChecker.updateAvailable {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("v\(updateChecker.latestVersion ?? "") Available")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("Click to download update")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Download") {
                        updateChecker.openDownload()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                }
                .padding(6)
                .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))

                Divider()
            }

            if !lockManager.accessibility.isTrusted {
                Button {
                    lockManager.accessibility.requestPermission()
                } label: {
                    Label("Grant Accessibility Permission…", systemImage: "hand.raised.fill")
                }
                Divider()
            }

            // Primary Lock / Unlock Actions
            if lockManager.lockMode.isLocked {
                Button {
                    lockManager.unlock(reason: .manualUI)
                } label: {
                    Label("Unlock Input Now (\(settings.unlockShortcut.displayString))", systemImage: "lock.open.fill")
                }
            } else {
                Button {
                    lockManager.lock(mode: .keyboardAndMouse)
                } label: {
                    Label(
                        "Lock Keyboard & Trackpad (\(settings.lockAllShortcut.displayString))",
                        systemImage: "lock.fill"
                    )
                }

                Button {
                    lockManager.lock(mode: .keyboardOnly)
                } label: {
                    Label(
                        "Lock Keyboard Only (\(settings.lockKeyboardOnlyShortcut.displayString))",
                        systemImage: "keyboard.badge.ellipsis"
                    )
                }
            }

            Divider()

            // Quick Preferences
            Picker("Screen Mode", selection: $settings.overlayStyle) {
                ForEach(OverlayStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            }

            Toggle("Show Unlock Combo on Screen", isOn: $settings.showUnlockHintOnScreen)

            Toggle(
                "Auto-Unlock Timer (\(settings.autoUnlockMinutes) min)",
                isOn: $settings.autoUnlockTimerEnabled
            )

            Divider()

            // Master Key Reference
            Text("Master Key: \(KeyCombo.masterUnlockKey.displayString)")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Button {
                openWindow(id: "main-dashboard")
                NSApplication.shared.activate(ignoringOtherApps: true)
            } label: {
                Label("Settings & Shortcuts…", systemImage: "gearshape")
            }
            Button {
                Task {
                    await updateChecker.checkForUpdates(manual: true, settings: settings)
                }
            } label: {
                HStack {
                    Label("Check for Updates…", systemImage: "arrow.triangle.2.circlepath")
                    if updateChecker.isChecking {
                        Spacer()
                        ProgressView()
                            .controlSize(.mini)
                    }
                }
            }

            Button(role: .destructive) {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit SwipeIt", systemImage: "power")
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(8)
    }
}
