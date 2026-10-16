//
//  InputInterceptor.swift
//  SwipeIt
//
//  Created by Reiwa on 16.10.2026.
//

import Foundation
import CoreGraphics

/// Reason why an unlock was triggered.
public enum UnlockReason: String, Sendable, Equatable {
    case customShortcut = "Custom Unlock Shortcut"
    case toggleShortcut = "Lock Shortcut Toggle"
    case masterKey = "Emergency Master Key (Esc + ← + ↑ + →)"
    case autoUnlockTimer = "Auto-Unlock Safety Timer"
    case manualUI = "Menu Bar / UI"
}

/// High-level action decided by the input evaluation engine.
public enum InterceptorAction: Sendable, Equatable {
    case passThrough
    case swallow
    case lock(LockMode)
    case unlock(UnlockReason)
}

/// Low-level Quartz CGEventTap manager and key-chord state machine.
public final class InputInterceptor {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// Currently held physical key codes (kVK_*) for simultaneous chord detection.
    public private(set) var pressedKeyCodes: Set<Int64> = []

    /// Current lock mode snapshot read by the event tap callback.
    public var currentLockMode: LockMode = .unlocked {
        didSet {
            if currentLockMode != oldValue {
                pressedKeyCodes.removeAll()
            }
        }
    }

    /// Snapshot of shortcut settings used by the event tap.
    public var lockAllShortcut: KeyCombo = .defaultLockAll
    public var lockKeyboardOnlyShortcut: KeyCombo = .defaultLockKeyboardOnly
    public var unlockShortcut: KeyCombo = .defaultUnlock
    public var allowToggleWithLockShortcut: Bool = false
    public var enableGlobalShortcuts: Bool = true
    public var isRecordingShortcut: Bool = false

    /// Callback invoked on the main thread when a lock or unlock shortcut is matched.
    public var onAction: ((InterceptorAction) -> Void)?

    public private(set) var isTapActive: Bool = false

    public init() {}

    deinit {
        stop()
    }

    // MARK: - Event Tap Lifecycle

    /// Starts the global Quartz CGEventTap on the main run loop.
    /// Returns true if the tap was successfully created (requires Accessibility permission and App Sandbox disabled).
    @discardableResult
    public func start() -> Bool {
        if isTapActive, let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
            return true
        }

        let keyboardEvents: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << 14) // NSSystemDefined (media, volume, brightness keys)

        let pointerEvents: CGEventMask =
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.leftMouseUp.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.rightMouseUp.rawValue) |
            (1 << CGEventType.otherMouseDown.rawValue) |
            (1 << CGEventType.otherMouseUp.rawValue) |
            (1 << CGEventType.mouseMoved.rawValue) |
            (1 << CGEventType.leftMouseDragged.rawValue) |
            (1 << CGEventType.rightMouseDragged.rawValue) |
            (1 << CGEventType.otherMouseDragged.rawValue) |
            (1 << CGEventType.scrollWheel.rawValue) |
            (1 << 29) | (1 << 30) | (1 << 31) // Trackpad gesture events

        let eventMask = keyboardEvents | pointerEvents
        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon else {
                return Unmanaged.passUnretained(event)
            }
            let interceptor = Unmanaged<InputInterceptor>.fromOpaque(refcon).takeUnretainedValue()
            return interceptor.handleCGEvent(proxy: proxy, type: type, event: event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: userInfo
        ) else {
            isTapActive = false
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.eventTap = tap
        self.runLoopSource = source
        self.isTapActive = true
        return true
    }

    /// Stops and removes the Quartz CGEventTap.
    public func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        isTapActive = false
        pressedKeyCodes.removeAll()
    }

    public func resetPressedKeys() {
        pressedKeyCodes.removeAll()
    }

    // MARK: - Core Event Evaluation

    /// Evaluates a keyboard event against the current lock state, custom shortcuts, and Master Key.
    public func evaluateKeyEvent(keyCode: Int64, isKeyDown: Bool, rawFlags: UInt64) -> InterceptorAction {
        if isKeyDown {
            pressedKeyCodes.insert(keyCode)
        } else {
            pressedKeyCodes.remove(keyCode)
        }

        switch currentLockMode {
        case .unlocked:
            guard isKeyDown, enableGlobalShortcuts, !isRecordingShortcut else {
                return .passThrough
            }

            if lockAllShortcut.matches(pressedKeyCodes: pressedKeyCodes, rawFlags: rawFlags) {
                pressedKeyCodes.removeAll()
                return .lock(.keyboardAndMouse)
            }

            if lockKeyboardOnlyShortcut.matches(pressedKeyCodes: pressedKeyCodes, rawFlags: rawFlags) {
                pressedKeyCodes.removeAll()
                return .lock(.keyboardOnly)
            }

            return .passThrough

        case .keyboardAndMouse, .keyboardOnly:
            guard isKeyDown else {
                return .swallow
            }

            // 1. Check Emergency Master Key ("Combowombo": Esc + Left + Up + Right simultaneously)
            if KeyCombo.masterUnlockKey.matches(pressedKeyCodes: pressedKeyCodes, rawFlags: rawFlags) {
                pressedKeyCodes.removeAll()
                return .unlock(.masterKey)
            }

            // 2. Check User's Custom Unlock Shortcut
            if unlockShortcut.matches(pressedKeyCodes: pressedKeyCodes, rawFlags: rawFlags) {
                pressedKeyCodes.removeAll()
                return .unlock(.customShortcut)
            }

            // 3. Check optional Toggle with Lock Shortcut
            if allowToggleWithLockShortcut {
                if currentLockMode == .keyboardAndMouse &&
                    lockAllShortcut.matches(pressedKeyCodes: pressedKeyCodes, rawFlags: rawFlags) {
                    pressedKeyCodes.removeAll()
                    return .unlock(.toggleShortcut)
                }
                if currentLockMode == .keyboardOnly &&
                    lockKeyboardOnlyShortcut.matches(pressedKeyCodes: pressedKeyCodes, rawFlags: rawFlags) {
                    pressedKeyCodes.removeAll()
                    return .unlock(.toggleShortcut)
                }
            }

            return .swallow
        }
    }

    // MARK: - CGEvent Callback Handler

    private func handleCGEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Re-enable tap immediately if macOS disables it due to timeout or user input
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            pressedKeyCodes.removeAll()
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return nil
        }

        let rawType = type.rawValue

        // Keyboard events (.keyDown, .keyUp)
        if type == .keyDown || type == .keyUp {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let rawFlags = event.flags.rawValue
            let decision = evaluateKeyEvent(keyCode: keyCode, isKeyDown: type == .keyDown, rawFlags: rawFlags)

            switch decision {
            case .passThrough:
                return Unmanaged.passUnretained(event)
            case .swallow:
                return nil
            case .lock, .unlock:
                onAction?(decision)
                return nil
            }
        }

        // Modifier flag changes (.flagsChanged) and Media/System keys (NSSystemDefined == 14)
        if type == .flagsChanged || rawType == 14 {
            if currentLockMode.locksKeyboard {
                return nil
            }
            return Unmanaged.passUnretained(event)
        }

        // Pointer / Mouse / Trackpad / Scroll / Gesture events
        if currentLockMode.locksPointer {
            return nil
        }

        return Unmanaged.passUnretained(event)
    }
}
