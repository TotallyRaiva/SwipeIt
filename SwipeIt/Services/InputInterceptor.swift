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
public final class InputInterceptor: @unchecked Sendable {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var activeMask: CGEventMask = 0

    /// Currently held physical key codes (kVK_*) for simultaneous chord detection.
    public private(set) var pressedKeyCodes: Set<Int64> = []

    /// Current lock mode snapshot read by the event tap callback.
    public var currentLockMode: LockMode = .unlocked {
        didSet {
            if currentLockMode != oldValue {
                pressedKeyCodes.removeAll()
                if isTapActive && targetEventMask(for: currentLockMode) != activeMask {
                    start()
                }
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

    /// Callback invoked when a lock or unlock shortcut is matched.
    public var onAction: ((InterceptorAction) -> Void)?

    public private(set) var isTapActive: Bool = false

    public init() {}

    deinit {
        stop()
    }

    // MARK: - Event Mask Determination

    /// Returns the minimal required event mask for the specified lock mode.
    /// When unlocked or in keyboard-only mode, pointer/mouse events are completely omitted to prevent main-thread overhead.
    public func targetEventMask(for mode: LockMode) -> CGEventMask {
        var mask: CGEventMask = 0
        mask |= (1 << CGEventType.keyDown.rawValue)
        mask |= (1 << CGEventType.keyUp.rawValue)
        mask |= (1 << CGEventType.flagsChanged.rawValue)
        mask |= (1 << 14) // NSSystemDefined (media, volume, brightness keys)

        if mode == .keyboardAndMouse {
            mask |= (1 << CGEventType.leftMouseDown.rawValue)
            mask |= (1 << CGEventType.leftMouseUp.rawValue)
            mask |= (1 << CGEventType.rightMouseDown.rawValue)
            mask |= (1 << CGEventType.rightMouseUp.rawValue)
            mask |= (1 << CGEventType.otherMouseDown.rawValue)
            mask |= (1 << CGEventType.otherMouseUp.rawValue)
            mask |= (1 << CGEventType.mouseMoved.rawValue)
            mask |= (1 << CGEventType.leftMouseDragged.rawValue)
            mask |= (1 << CGEventType.rightMouseDragged.rawValue)
            mask |= (1 << CGEventType.otherMouseDragged.rawValue)
            mask |= (1 << CGEventType.scrollWheel.rawValue)
            mask |= (1 << CGEventType.tabletPointer.rawValue)
            mask |= (1 << CGEventType.tabletProximity.rawValue)
            mask |= (1 << 18) // kCGEventRotate
            mask |= (1 << 29) // kCGEventGesture
            mask |= (1 << 30) // kCGEventMagnify (smart zoom)
            mask |= (1 << 31) // kCGEventSwipe
            mask |= (1 << 32) // kCGEventQuickLook / Force-click / Pressure
        }

        return mask
    }

    // MARK: - Event Tap Lifecycle

    /// Starts or updates the global Quartz CGEventTap on the main run loop.
    /// Returns true if the tap was successfully created and active.
    @discardableResult
    public func start() -> Bool {
        let desiredMask = targetEventMask(for: currentLockMode)

        if let tap = eventTap {
            if CFMachPortIsValid(tap) && activeMask == desiredMask {
                CGEvent.tapEnable(tap: tap, enable: true)
                isTapActive = true
                return true
            }
            // Invalid port or mask change needed: clean up before recreating
            stop()
        }

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
            eventsOfInterest: desiredMask,
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
        self.activeMask = desiredMask
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
        activeMask = 0
        isTapActive = false
        pressedKeyCodes.removeAll()
    }

    public func resetPressedKeys() {
        pressedKeyCodes.removeAll()
    }

    // MARK: - Core Event Evaluation

    /// Evaluates a keyboard event against the current lock state, custom shortcuts, and Master Key.
    public func evaluateKeyEvent(
        keyCode: Int64,
        isKeyDown: Bool,
        rawFlags: UInt64,
        isAutorepeat: Bool = false
    ) -> InterceptorAction {
        if isKeyDown {
            if !isAutorepeat {
                pressedKeyCodes.insert(keyCode)
            }
        } else {
            pressedKeyCodes.remove(keyCode)
        }

        // Resync: Prune any pressed key that is not physically pressed down (only when tap is actively running in real OS session)
        if isTapActive && !pressedKeyCodes.isEmpty {
            pressedKeyCodes = pressedKeyCodes.filter { code in
                CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(code))
            }
        }

        // Never trigger shortcuts on key auto-repeat (fixes rapid lock/unlock toggle loops)
        if isAutorepeat {
            return currentLockMode == .unlocked ? .passThrough : .swallow
        }

        switch currentLockMode {
        case .unlocked:
            guard isKeyDown, enableGlobalShortcuts, !isRecordingShortcut else {
                return .passThrough
            }

            if lockAllShortcut.matches(pressedKeyCodes: pressedKeyCodes, rawFlags: rawFlags) {
                pressedKeyCodes.removeAll()
                currentLockMode = .keyboardAndMouse
                return .lock(.keyboardAndMouse)
            }

            if lockKeyboardOnlyShortcut.matches(pressedKeyCodes: pressedKeyCodes, rawFlags: rawFlags) {
                pressedKeyCodes.removeAll()
                currentLockMode = .keyboardOnly
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
                currentLockMode = .unlocked
                return .unlock(.masterKey)
            }

            // 2. Check User's Custom Unlock Shortcut
            if unlockShortcut.matches(pressedKeyCodes: pressedKeyCodes, rawFlags: rawFlags) {
                pressedKeyCodes.removeAll()
                currentLockMode = .unlocked
                return .unlock(.customShortcut)
            }

            // 3. Check optional Toggle with Lock Shortcut
            if allowToggleWithLockShortcut {
                if currentLockMode == .keyboardAndMouse &&
                    lockAllShortcut.matches(pressedKeyCodes: pressedKeyCodes, rawFlags: rawFlags) {
                    pressedKeyCodes.removeAll()
                    currentLockMode = .unlocked
                    return .unlock(.toggleShortcut)
                }
                if currentLockMode == .keyboardOnly &&
                    lockKeyboardOnlyShortcut.matches(pressedKeyCodes: pressedKeyCodes, rawFlags: rawFlags) {
                    pressedKeyCodes.removeAll()
                    currentLockMode = .unlocked
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
            if let tap = eventTap, CFMachPortIsValid(tap) {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return nil
        }

        let rawType = type.rawValue

        // Keyboard events (.keyDown, .keyUp)
        if type == .keyDown || type == .keyUp {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let rawFlags = event.flags.rawValue
            let isAutorepeat = (type == .keyDown) && (event.getIntegerValueField(.keyboardEventAutorepeat) != 0)

            let decision = evaluateKeyEvent(
                keyCode: keyCode,
                isKeyDown: type == .keyDown,
                rawFlags: rawFlags,
                isAutorepeat: isAutorepeat
            )

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
