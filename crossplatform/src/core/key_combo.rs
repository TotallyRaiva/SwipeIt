use serde::{Deserialize, Serialize};
use std::collections::BTreeSet;

/// Canonical Virtual Key Codes (aligned with Win32 VK_* codes for zero-cost Windows mapping).
pub mod vk {
    pub const BACKSPACE: u16 = 0x08;
    pub const TAB: u16 = 0x09;
    pub const RETURN: u16 = 0x0D;
    pub const ESCAPE: u16 = 0x1B;
    pub const SPACE: u16 = 0x20;
    pub const PAGE_UP: u16 = 0x21;
    pub const PAGE_DOWN: u16 = 0x22;
    pub const END: u16 = 0x23;
    pub const HOME: u16 = 0x24;
    pub const LEFT: u16 = 0x25;
    pub const UP: u16 = 0x26;
    pub const RIGHT: u16 = 0x27;
    pub const DOWN: u16 = 0x28;
    pub const INSERT: u16 = 0x2D;
    pub const DELETE: u16 = 0x2E;

    pub const KEY_K: u16 = 0x4B;
    pub const KEY_L: u16 = 0x4C;
    pub const KEY_U: u16 = 0x55;

    pub const LWIN: u16 = 0x5B;
    pub const RWIN: u16 = 0x5C;
    pub const F1: u16 = 0x70;
    pub const F12: u16 = 0x7B;

    pub const LSHIFT: u16 = 0xA0;
    pub const RSHIFT: u16 = 0xA1;
    pub const LCONTROL: u16 = 0xA2;
    pub const RCONTROL: u16 = 0xA3;
    pub const LMENU: u16 = 0xA4; // Left Alt
    pub const RMENU: u16 = 0xA5; // Right Alt

    /// Returns true if the virtual key code is a pure modifier key.
    pub fn is_modifier_vk(code: u16) -> bool {
        matches!(
            code,
            0x10 | 0x11 | 0x12 | LSHIFT | RSHIFT | LCONTROL | RCONTROL | LMENU | RMENU | LWIN | RWIN
        )
    }
}

/// Canonical modifier bitflags.
pub mod mods {
    pub const NONE: u8 = 0;
    pub const CTRL: u8 = 1 << 0;
    pub const ALT: u8 = 1 << 1;
    pub const SHIFT: u8 = 1 << 2;
    pub const META: u8 = 1 << 3; // Windows / Super / Command key
    pub const RELEVANT_MASK: u8 = CTRL | ALT | SHIFT | META;
}

/// Represents a user-configurable shortcut or multi-key simultaneous chord.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct KeyCombo {
    pub key_codes: BTreeSet<u16>,
    pub modifiers: u8,
}

impl KeyCombo {
    pub fn new<I: IntoIterator<Item = u16>>(key_codes: I, modifiers: u8) -> Self {
        Self {
            key_codes: key_codes.into_iter().collect(),
            modifiers: modifiers & mods::RELEVANT_MASK,
        }
    }

    /// Default shortcut to lock both Keyboard and Trackpad/Mouse: `Ctrl + Alt + Win + L`
    pub fn default_lock_all() -> Self {
        Self::new([vk::KEY_L], mods::CTRL | mods::ALT | mods::META)
    }

    /// Default shortcut to lock Keyboard Only: `Ctrl + Alt + Win + K`
    pub fn default_lock_keyboard_only() -> Self {
        Self::new([vk::KEY_K], mods::CTRL | mods::ALT | mods::META)
    }

    /// Default shortcut to unlock: `Ctrl + Alt + Win + U`
    pub fn default_unlock() -> Self {
        Self::new([vk::KEY_U], mods::CTRL | mods::ALT | mods::META)
    }

    /// Hardcoded Emergency Master Key ("Combowombo"): `Esc + ← + ↑ + →` held simultaneously.
    pub fn master_unlock_key() -> Self {
        Self::new([vk::ESCAPE, vk::LEFT, vk::UP, vk::RIGHT], mods::NONE)
    }

    /// Validates whether a shortcut is safe for everyday use without accidental triggers during typing.
    /// - Rejects empty combinations.
    /// - Rejects bare `Shift + key` (uppercase typing) or `Alt + key` alone unless paired with `Ctrl`, `Win/Super`, or `Alt + Shift`.
    /// - Rejects 1-key or 2-key plain chords without modifiers (e.g. `J + K` during fast typing); requires 3+ keys for modifier-less chords.
    pub fn is_valid_user_shortcut(&self) -> bool {
        if self.key_codes.is_empty() {
            return false;
        }

        let m = self.modifiers & mods::RELEVANT_MASK;
        if m != mods::NONE {
            let has_ctrl_or_meta = (m & (mods::CTRL | mods::META)) != 0;
            let has_alt_and_shift = (m & mods::ALT) != 0 && (m & mods::SHIFT) != 0;
            has_ctrl_or_meta || has_alt_and_shift
        } else {
            self.key_codes.len() >= 3
        }
    }

    /// Evaluates whether the currently held keys and modifiers satisfy this combination.
    /// Uses subset matching so a missed key-release on an unrelated key cannot permanently break shortcuts.
    pub fn matches(&self, pressed_keys: &BTreeSet<u16>, active_modifiers: u8) -> bool {
        if self.key_codes.is_empty() {
            return false;
        }

        let normalized_active = active_modifiers & mods::RELEVANT_MASK;
        let normalized_target = self.modifiers & mods::RELEVANT_MASK;

        if normalized_target != mods::NONE && normalized_active != normalized_target {
            return false;
        }

        self.key_codes.is_subset(pressed_keys)
    }

    /// Returns individual keycap token strings in display order (e.g. `["Ctrl", "Alt", "Win", "L"]`).
    pub fn key_tokens(&self) -> Vec<String> {
        let mut tokens = Vec::new();
        let m = self.modifiers & mods::RELEVANT_MASK;

        if (m & mods::CTRL) != 0 {
            tokens.push("Ctrl".to_string());
        }
        if (m & mods::ALT) != 0 {
            tokens.push("Alt".to_string());
        }
        if (m & mods::SHIFT) != 0 {
            tokens.push("Shift".to_string());
        }
        if (m & mods::META) != 0 {
            tokens.push(Self::meta_key_label().to_string());
        }

        for &code in &self.key_codes {
            tokens.push(Self::key_name(code));
        }

        tokens
    }

    /// Human-readable string representation (e.g. `"Ctrl + Alt + Win + L"`).
    pub fn display_string(&self) -> String {
        let tokens = self.key_tokens();
        if tokens.is_empty() {
            "None".to_string()
        } else {
            tokens.join(" + ")
        }
    }

    pub fn meta_key_label() -> &'static str {
        if cfg!(target_os = "linux") {
            "Super"
        } else {
            "Win"
        }
    }

    /// Converts a canonical virtual key code into a concise keycap label.
    pub fn key_name(code: u16) -> String {
        match code {
            vk::ESCAPE => "Esc".to_string(),
            vk::SPACE => "Space".to_string(),
            vk::RETURN => "Enter".to_string(),
            vk::TAB => "Tab".to_string(),
            vk::BACKSPACE => "Backspace".to_string(),
            vk::DELETE => "Del".to_string(),
            vk::INSERT => "Ins".to_string(),
            vk::HOME => "Home".to_string(),
            vk::END => "End".to_string(),
            vk::PAGE_UP => "PgUp".to_string(),
            vk::PAGE_DOWN => "PgDn".to_string(),
            vk::LEFT => "←".to_string(),
            vk::UP => "↑".to_string(),
            vk::RIGHT => "→".to_string(),
            vk::DOWN => "↓".to_string(),
            0x30..=0x39 => char::from_u32(code as u32).unwrap_or('?').to_string(),
            0x41..=0x5A => char::from_u32(code as u32).unwrap_or('?').to_string(),
            0x70..=0x87 => format!("F{}", (code - 0x70) + 1),
            _ => format!("Key(0x{:02X})", code),
        }
    }
}
