//
//  KeyCombo.swift
//  SwipeIt
//
//  Created by Reiwa on 16.10.2026.
//

import Foundation
import CoreGraphics

/// Represents a customizable keyboard shortcut or multi-key chord (such as the Master Key).
public struct KeyCombo: Codable, Equatable, Hashable, Sendable {
    /// Set of macOS virtual key codes (kVK_*) that must be held simultaneously.
    public var keyCodes: Set<Int64>
    /// Normalized modifier flags (Command, Option, Control, Shift).
    public var modifiers: UInt64

    /// Mask for the 4 standard user modifiers (Command, Option, Control, Shift),
    /// stripping out system flags like numericPad or secondaryFn that macOS attaches to arrow keys.
    nonisolated public static let relevantModifierMask: UInt64 =
        CGEventFlags.maskCommand.rawValue |
        CGEventFlags.maskAlternate.rawValue |
        CGEventFlags.maskControl.rawValue |
        CGEventFlags.maskShift.rawValue

    nonisolated public init(keyCodes: Set<Int64>, modifiers: UInt64 = 0) {
        self.keyCodes = keyCodes
        self.modifiers = modifiers & Self.relevantModifierMask
    }

    nonisolated public init(keyCode: Int64, modifiers: UInt64) {
        self.keyCodes = [keyCode]
        self.modifiers = modifiers & Self.relevantModifierMask
    }

    // MARK: - Default & Master Shortcuts

    /// Emergency Master Key ("Combowombo"): Esc (53) + Left Arrow (123) + Up Arrow (126) + Right Arrow (124) simultaneously.
    nonisolated public static let masterUnlockKey = KeyCombo(
        keyCodes: [53, 123, 126, 124],
        modifiers: 0
    )

    /// Default Full Lock shortcut: Ctrl + Option + Command + L (keyCode 37)
    nonisolated public static let defaultLockAll = KeyCombo(
        keyCode: 37,
        modifiers: CGEventFlags.maskControl.rawValue | CGEventFlags.maskAlternate.rawValue | CGEventFlags.maskCommand.rawValue
    )

    /// Default Keyboard-Only Lock shortcut: Ctrl + Option + Command + K (keyCode 40)
    nonisolated public static let defaultLockKeyboardOnly = KeyCombo(
        keyCode: 40,
        modifiers: CGEventFlags.maskControl.rawValue | CGEventFlags.maskAlternate.rawValue | CGEventFlags.maskCommand.rawValue
    )

    /// Default Custom Unlock shortcut: Ctrl + Option + Command + U (keyCode 32)
    nonisolated public static let defaultUnlock = KeyCombo(
        keyCode: 32,
        modifiers: CGEventFlags.maskControl.rawValue | CGEventFlags.maskAlternate.rawValue | CGEventFlags.maskCommand.rawValue
    )

    // MARK: - Matching Logic

    /// Evaluates whether the currently pressed key codes and modifier flags trigger this combo.
    nonisolated public func matches(pressedKeyCodes: Set<Int64>, rawFlags: UInt64) -> Bool {
        guard !keyCodes.isEmpty else { return false }
        let normalizedFlags = rawFlags & Self.relevantModifierMask

        if keyCodes.count > 1 {
            // Multi-key chord (e.g., Master Key: Esc + Left + Up + Right)
            let allChordKeysPressed = keyCodes.isSubset(of: pressedKeyCodes)
            let requiredModifiersPresent = (normalizedFlags & modifiers) == modifiers
            return allChordKeysPressed && requiredModifiersPresent
        } else {
            // Standard modifier + key combo: target key is pressed and modifiers match
            return keyCodes.isSubset(of: pressedKeyCodes) && normalizedFlags == modifiers
        }
    }

    /// Validates whether a user-recorded shortcut is safe for global use.
    /// Rejects plain typing sequences (like Shift+letter or 2 plain keys like J+K) that could accidentally lock the Mac during regular typing.
    nonisolated public var isValidUserShortcut: Bool {
        guard !keyCodes.isEmpty else { return false }

        let hasCmd = (modifiers & CGEventFlags.maskCommand.rawValue) != 0
        let hasCtrl = (modifiers & CGEventFlags.maskControl.rawValue) != 0
        let hasOpt = (modifiers & CGEventFlags.maskAlternate.rawValue) != 0
        let hasShift = (modifiers & CGEventFlags.maskShift.rawValue) != 0

        if modifiers != 0 {
            // Shift alone is rejected (normal typing produces capital letters)
            if hasShift && !hasCmd && !hasCtrl && !hasOpt {
                return false
            }
            // Command or Control alone or combined is safe
            if hasCmd || hasCtrl {
                return true
            }
            // Option + Shift combined is safe
            if hasOpt && hasShift {
                return true
            }
            // Option alone is allowed only for non-typing keys (Function keys, Escape, Arrows, Space)
            if hasOpt && keyCodes.count == 1, let code = keyCodes.first {
                let isFKey = (code >= 96 && code <= 101) || (code >= 109 && code <= 111) || (code >= 103 && code <= 107) || code == 113 || code == 120 || code == 122
                let isSpecialKey = code == 53 || code == 49 || (code >= 123 && code <= 126) // Esc, Space, Arrow keys
                return isFKey || isSpecialKey
            }
            return false
        }

        // Chords without modifiers must have at least 3 simultaneous keys (e.g., Master Key: Esc + ← + ↑ + →)
        // 2 plain letters (e.g. J+K) are strictly disallowed to prevent accidental typing lockouts
        return keyCodes.count >= 3
    }

    // MARK: - Display Formatting

    /// Standard Apple modifier symbols in canonical order.
    nonisolated public var modifierTokens: [String] {
        var tokens: [String] = []
        if (modifiers & CGEventFlags.maskControl.rawValue) != 0 { tokens.append("⌃") }
        if (modifiers & CGEventFlags.maskAlternate.rawValue) != 0 { tokens.append("⌥") }
        if (modifiers & CGEventFlags.maskShift.rawValue) != 0 { tokens.append("⇧") }
        if (modifiers & CGEventFlags.maskCommand.rawValue) != 0 { tokens.append("⌘") }
        return tokens
    }

    /// Compact symbol representation (e.g., "⌃⌥⌘L" or "Esc + ← + ↑ + →").
    nonisolated public var displayString: String {
        let modString = modifierTokens.joined()
        let sortedKeys = keyCodes.sorted()
        let keyLabels = sortedKeys.map { Self.keyName(for: $0) }

        if keyCodes.count > 1 {
            let chordString = keyLabels.joined(separator: " + ")
            return modString.isEmpty ? chordString : "\(modString) + \(chordString)"
        } else if let singleKey = keyLabels.first {
            return modString + singleKey
        }

        return "None"
    }

    /// Individual token symbols for rendering tactile keycaps (e.g. ["⌃", "⌥", "⌘", "L"] or ["Esc", "←", "↑", "→"]).
    nonisolated public var keyTokens: [String] {
        var tokens = modifierTokens
        for code in keyCodes.sorted() {
            tokens.append(Self.keyName(for: code))
        }
        return tokens
    }

    /// Verbose human-readable representation (e.g., "Ctrl + Option + Cmd + L" or "Esc + ← + ↑ + →").
    nonisolated public var readableDescription: String {
        var tokens: [String] = []
        if (modifiers & CGEventFlags.maskControl.rawValue) != 0 { tokens.append("Ctrl") }
        if (modifiers & CGEventFlags.maskAlternate.rawValue) != 0 { tokens.append("Option") }
        if (modifiers & CGEventFlags.maskShift.rawValue) != 0 { tokens.append("Shift") }
        if (modifiers & CGEventFlags.maskCommand.rawValue) != 0 { tokens.append("Cmd") }

        for code in keyCodes.sorted() {
            tokens.append(Self.keyName(for: code))
        }
        return tokens.joined(separator: " + ")
    }

    /// Maps macOS virtual key codes (HIToolbox kVK_*) to readable labels.
    nonisolated public static func keyName(for keyCode: Int64) -> String {
        switch keyCode {
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 22: return "6"
        case 23: return "5"
        case 24: return "="
        case 25: return "9"
        case 26: return "7"
        case 27: return "-"
        case 28: return "8"
        case 29: return "0"
        case 30: return "]"
        case 31: return "O"
        case 32: return "U"
        case 33: return "["
        case 34: return "I"
        case 35: return "P"
        case 36: return "Return"
        case 37: return "L"
        case 38: return "J"
        case 39: return "'"
        case 40: return "K"
        case 41: return ";"
        case 42: return "\\"
        case 43: return ","
        case 44: return "/"
        case 45: return "N"
        case 46: return "M"
        case 47: return "."
        case 48: return "Tab"
        case 49: return "Space"
        case 50: return "`"
        case 51: return "Delete"
        case 53: return "Esc"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 99: return "F3"
        case 100: return "F8"
        case 101: return "F9"
        case 103: return "F11"
        case 109: return "F10"
        case 111: return "F12"
        case 115: return "Home"
        case 116: return "PgUp"
        case 117: return "FwdDel"
        case 118: return "F4"
        case 119: return "End"
        case 120: return "F2"
        case 121: return "PgDn"
        case 122: return "F1"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default: return "Key(\(keyCode))"
        }
    }
}
