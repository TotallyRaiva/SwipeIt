//
//  LockMode.swift
//  SwipeIt
//
//  Created by Reiwa on 16.10.2026.
//

import Foundation

/// Represents the current input locking state of SwipeIt.
public enum LockMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case unlocked = "unlocked"
    case keyboardAndMouse = "keyboardAndMouse"
    case keyboardOnly = "keyboardOnly"

    public var id: String { rawValue }

    public var isLocked: Bool {
        self != .unlocked
    }

    public var locksKeyboard: Bool {
        self == .keyboardAndMouse || self == .keyboardOnly
    }

    public var locksPointer: Bool {
        self == .keyboardAndMouse
    }

    public var title: String {
        switch self {
        case .unlocked:
            return "Unlocked"
        case .keyboardAndMouse:
            return "Keyboard & Trackpad Locked"
        case .keyboardOnly:
            return "Keyboard Only Locked"
        }
    }

    public var shortTitle: String {
        switch self {
        case .unlocked:
            return "Unlocked"
        case .keyboardAndMouse:
            return "Full Lock (Keyboard + Mouse)"
        case .keyboardOnly:
            return "Keyboard Only"
        }
    }

    public var systemImage: String {
        switch self {
        case .unlocked:
            return "lock.open"
        case .keyboardAndMouse:
            return "lock.fill"
        case .keyboardOnly:
            return "keyboard.badge.ellipsis"
        }
    }
}

/// Visual presentation style when the system is locked.
public enum OverlayStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case blackoutCleaning = "blackoutCleaning"
    case frostedHUD = "frostedHUD"
    case invisible = "invisible"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .blackoutCleaning:
            return "Blackout Cleaning Screen"
        case .frostedHUD:
            return "Frosted Translucent Shield"
        case .invisible:
            return "Stealth / No Screen Overlay"
        }
    }

    public var subtitle: String {
        switch self {
        case .blackoutCleaning:
            return "Pitch-black screen across all displays so dust and smudges are easy to see while cleaning."
        case .frostedHUD:
            return "Dims and blurs the screen while keeping a clear visual indicator that input is locked."
        case .invisible:
            return "Keeps your screen completely visible (ideal for watching videos or prevents pet/child presses)."
        }
    }
}
