use crate::core::key_combo::KeyCombo;
use directories::ProjectDirs;
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::PathBuf;

/// Visual style of the fullscreen lock overlay.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum OverlayStyle {
    BlackoutCleaning,
    FrostedShield,
    Invisible,
}

impl OverlayStyle {
    pub const ALL: [OverlayStyle; 3] = [
        OverlayStyle::BlackoutCleaning,
        OverlayStyle::FrostedShield,
        OverlayStyle::Invisible,
    ];

    pub fn title(self) -> &'static str {
        match self {
            OverlayStyle::BlackoutCleaning => "Blackout Cleaning Screen",
            OverlayStyle::FrostedShield => "Dimmed Shield Overlay",
            OverlayStyle::Invisible => "Stealth / Invisible",
        }
    }

    pub fn subtitle(self) -> &'static str {
        match self {
            OverlayStyle::BlackoutCleaning => {
                "Turns displays pitch-black to reveal dust, smudges, and fingerprints while wiping."
            }
            OverlayStyle::FrostedShield => {
                "Dims the screen with a dark translucent shield and status card."
            }
            OverlayStyle::Invisible => {
                "Keeps your screen 100% visible while blocking input (ideal for movies or kids/pets)."
            }
        }
    }
}

/// Target action when recording a shortcut.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ShortcutTarget {
    LockAll,
    LockKeyboardOnly,
    Unlock,
}

/// Persistent user preferences and custom shortcuts.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SettingsStore {
    pub lock_all_shortcut: KeyCombo,
    pub lock_keyboard_only_shortcut: KeyCombo,
    pub unlock_shortcut: KeyCombo,
    pub allow_toggle_with_lock_shortcut: bool,
    pub show_unlock_hint_on_screen: bool,
    pub overlay_style: OverlayStyle,
    pub auto_unlock_timer_enabled: bool,
    pub auto_unlock_minutes: u32,
    pub enable_global_shortcuts: bool,
    pub automatically_check_for_updates: bool,
    pub last_update_check_timestamp: u64,
}

impl Default for SettingsStore {
    fn default() -> Self {
        Self {
            lock_all_shortcut: KeyCombo::default_lock_all(),
            lock_keyboard_only_shortcut: KeyCombo::default_lock_keyboard_only(),
            unlock_shortcut: KeyCombo::default_unlock(),
            allow_toggle_with_lock_shortcut: false,
            show_unlock_hint_on_screen: true,
            overlay_style: OverlayStyle::BlackoutCleaning,
            auto_unlock_timer_enabled: true,
            auto_unlock_minutes: 10,
            enable_global_shortcuts: true,
            automatically_check_for_updates: true,
            last_update_check_timestamp: 0,
        }
    }
}

impl SettingsStore {
    pub fn config_file_path() -> Option<PathBuf> {
        ProjectDirs::from("com", "Reiwa", "SwipeIt")
            .map(|dirs| dirs.config_dir().join("settings.json"))
    }

    pub fn load() -> Self {
        if let Some(path) = Self::config_file_path() {
            if let Ok(contents) = fs::read_to_string(path) {
                if let Ok(mut parsed) = serde_json::from_str::<SettingsStore>(&contents) {
                    parsed.auto_unlock_minutes = parsed.auto_unlock_minutes.clamp(1, 120);
                    return parsed;
                }
            }
        }
        Self::default()
    }

    pub fn save(&self) {
        if let Some(path) = Self::config_file_path() {
            if let Some(parent) = path.parent() {
                let _ = fs::create_dir_all(parent);
            }
            if let Ok(serialized) = serde_json::to_string_pretty(self) {
                let _ = fs::write(path, serialized);
            }
        }
    }

    pub fn set_auto_unlock_minutes(&mut self, minutes: u32) {
        self.auto_unlock_minutes = minutes.clamp(1, 120);
        self.save();
    }

    pub fn reset_to_defaults(&mut self) {
        *self = Self::default();
        self.save();
    }

    /// Checks whether a candidate shortcut conflicts with the Emergency Master Key or another action.
    pub fn duplicate_check_message(
        &self,
        candidate: &KeyCombo,
        target: ShortcutTarget,
    ) -> Option<String> {
        if *candidate == KeyCombo::master_unlock_key() {
            return Some(
                "This combination is reserved by the Emergency Master Key (Esc + ← + ↑ + →)."
                    .to_string(),
            );
        }
        if target != ShortcutTarget::LockAll && *candidate == self.lock_all_shortcut {
            return Some(
                "This combination is already assigned to 'Lock Keyboard & Trackpad'.".to_string(),
            );
        }
        if target != ShortcutTarget::LockKeyboardOnly
            && *candidate == self.lock_keyboard_only_shortcut
        {
            return Some(
                "This combination is already assigned to 'Lock Keyboard Only'.".to_string(),
            );
        }
        if target != ShortcutTarget::Unlock && *candidate == self.unlock_shortcut {
            return Some("This combination is already assigned to 'Unlock'.".to_string());
        }
        None
    }
}
