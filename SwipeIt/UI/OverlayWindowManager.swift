//
//  OverlayWindowManager.swift
//  SwipeIt
//
//  Created by Reiwa on 16.10.2026.
//

import AppKit
import SwiftUI

/// Manages multi-monitor borderless overlay panels while SwipeIt is in a locked state.
@MainActor
public final class OverlayWindowManager {
    private var overlayWindows: [NSWindow] = []
    private var isCursorHidden: Bool = false

    public init() {}

    /// Displays the lock overlay across all connected screens according to the user's preferences.
    public func showOverlays(lockManager: LockManager, settings: SettingsStore) {
        hideOverlays()

        if lockManager.lockMode.locksPointer && !isCursorHidden {
            CGDisplayHideCursor(CGMainDisplayID())
            isCursorHidden = true
        }

        // In stealth/invisible mode with screen hints disabled, no window needs to be rendered at all.
        if settings.overlayStyle == .invisible && !settings.showUnlockHintOnScreen {
            return
        }

        let screens = NSScreen.screens
        let mainScreen = NSScreen.main ?? screens.first

        for screen in screens {
            let isPrimary = (screen == mainScreen)
            let panel = NSPanel(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )

            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            panel.isOpaque = (settings.overlayStyle == .blackoutCleaning)
            panel.backgroundColor = (settings.overlayStyle == .blackoutCleaning) ? .black : .clear
            panel.hasShadow = false
            panel.ignoresMouseEvents = (lockManager.lockMode == .keyboardOnly)

            let hostingView = NSHostingView(
                rootView: LockOverlayView(
                    lockManager: lockManager,
                    settings: settings,
                    isPrimaryScreen: isPrimary
                )
            )
            hostingView.frame = NSRect(origin: .zero, size: screen.frame.size)
            panel.contentView = hostingView
            panel.setFrame(screen.frame, display: true)
            panel.orderFrontRegardless()

            overlayWindows.append(panel)
        }
    }

    /// Removes all lock overlay panels and restores the cursor if hidden.
    public func hideOverlays() {
        for window in overlayWindows {
            window.orderOut(nil)
            window.close()
        }
        overlayWindows.removeAll()

        if isCursorHidden {
            CGDisplayShowCursor(CGMainDisplayID())
            isCursorHidden = false
        }
    }
}
