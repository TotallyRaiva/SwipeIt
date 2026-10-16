//
//  AccessibilityManager.swift
//  SwipeIt
//
//  Created by Reiwa on 16.10.2026.
//

import Foundation
import AppKit
import ApplicationServices
import Observation

/// Manages macOS Accessibility (AX) permissions required for active Quartz CGEventTap filtering.
@Observable
public final class AccessibilityManager {
    public private(set) var isTrusted: Bool = false
    private var pollTimer: Timer?

    /// Callback invoked when accessibility permission transitions from false -> true.
    public var onPermissionGranted: (() -> Void)?

    public init() {
        checkPermission(prompt: false)
        startPolling()
    }

    /// Checks whether the process currently has macOS Accessibility permission.
    /// - Parameter prompt: If true, triggers the native macOS Accessibility permission dialog.
    @discardableResult
    public func checkPermission(prompt: Bool = false) -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        let wasTrusted = isTrusted
        isTrusted = trusted

        if !wasTrusted && trusted {
            onPermissionGranted?()
        }
        return trusted
    }

    /// Prompts the user for Accessibility permission and opens System Settings if needed.
    public func requestPermission() {
        let trusted = checkPermission(prompt: true)
        if !trusted {
            openAccessibilitySettings()
        }
    }

    /// Opens macOS System Settings -> Privacy & Security -> Accessibility directly.
    public func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkPermission(prompt: false)
            }
        }
    }
}
