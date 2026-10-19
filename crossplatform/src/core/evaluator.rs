use crate::core::key_combo::{vk, KeyCombo};
use serde::{Deserialize, Serialize};
use std::collections::BTreeSet;

/// Operating lock mode for SwipeIt.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum LockMode {
    Unlocked,
    KeyboardOnly,
    KeyboardAndMouse,
}

impl LockMode {
    pub fn is_locked(self) -> bool {
        self != LockMode::Unlocked
    }

    pub fn blocks_mouse(self) -> bool {
        self == LockMode::KeyboardAndMouse
    }

    pub fn title(self) -> &'static str {
        match self {
            LockMode::Unlocked => "Unlocked & Ready",
            LockMode::KeyboardOnly => "Keyboard Locked (Mouse Active)",
            LockMode::KeyboardAndMouse => "Full Lock (Keyboard + Trackpad/Mouse)",
        }
    }

    pub fn short_title(self) -> &'static str {
        match self {
            LockMode::Unlocked => "Ready",
            LockMode::KeyboardOnly => "Keyboard Locked",
            LockMode::KeyboardAndMouse => "Full Lock",
        }
    }
}

/// Reason why the device was unlocked.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum UnlockReason {
    CustomShortcut,
    ToggleLockShortcut,
    MasterKey,
    SafetyTimer,
    ManualUI,
}

/// Decision returned by the input evaluation engine for each incoming key event.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum KeyEvaluationDecision {
    /// Let the OS process the event normally.
    PassThrough,
    /// Swallow/block the event without changing lock state.
    Swallow,
    /// Swallow the event and transition immediately into the specified lock mode.
    Lock(LockMode),
    /// Swallow the event and immediately unlock the system.
    Unlock(UnlockReason),
}

/// Stateful, deterministic input evaluator shared across Windows, Linux, and macOS.
/// Enforces auto-repeat filtering, synchronous lock transitions, and Master Key override.
#[derive(Debug, Clone)]
pub struct InputEvaluator {
    pub current_lock_mode: LockMode,
    pub lock_all_shortcut: KeyCombo,
    pub lock_keyboard_only_shortcut: KeyCombo,
    pub unlock_shortcut: KeyCombo,
    pub allow_toggle_with_lock_shortcut: bool,
    pub enable_global_shortcuts: bool,
    pub is_recording_shortcut: bool,
    pressed_key_codes: BTreeSet<u16>,
}

impl Default for InputEvaluator {
    fn default() -> Self {
        Self::new()
    }
}

impl InputEvaluator {
    pub fn new() -> Self {
        Self {
            current_lock_mode: LockMode::Unlocked,
            lock_all_shortcut: KeyCombo::default_lock_all(),
            lock_keyboard_only_shortcut: KeyCombo::default_lock_keyboard_only(),
            unlock_shortcut: KeyCombo::default_unlock(),
            allow_toggle_with_lock_shortcut: false,
            enable_global_shortcuts: true,
            is_recording_shortcut: false,
            pressed_key_codes: BTreeSet::new(),
        }
    }

    pub fn clear_pressed_keys(&mut self) {
        self.pressed_key_codes.clear();
    }

    pub fn pressed_keys(&self) -> &BTreeSet<u16> {
        &self.pressed_key_codes
    }

    /// Evaluates a hardware key event and updates internal lock state synchronously
    /// to prevent race conditions where trailing keystrokes escape after locking.
    pub fn evaluate_key_event(
        &mut self,
        key_code: u16,
        is_key_down: bool,
        active_modifiers: u8,
        is_autorepeat: bool,
    ) -> KeyEvaluationDecision {
        // Ignore pure modifier key presses in the non-modifier key set
        if !vk::is_modifier_vk(key_code) {
            if is_key_down {
                self.pressed_key_codes.insert(key_code);
            } else {
                self.pressed_key_codes.remove(&key_code);
                return if self.current_lock_mode.is_locked() {
                    KeyEvaluationDecision::Swallow
                } else {
                    KeyEvaluationDecision::PassThrough
                };
            }
        } else if !is_key_down {
            return if self.current_lock_mode.is_locked() {
                KeyEvaluationDecision::Swallow
            } else {
                KeyEvaluationDecision::PassThrough
            };
        }

        // Bug #1 Fix: Filter key auto-repeat so holding a toggle shortcut never loops lock/unlock
        if is_autorepeat {
            return if self.current_lock_mode.is_locked() {
                KeyEvaluationDecision::Swallow
            } else {
                KeyEvaluationDecision::PassThrough
            };
        }

        if self.current_lock_mode.is_locked() {
            // 1. Always check Emergency Master Key ("Combowombo": Esc + ← + ↑ + →) first
            if KeyCombo::master_unlock_key().matches(&self.pressed_key_codes, active_modifiers) {
                self.pressed_key_codes.clear();
                self.current_lock_mode = LockMode::Unlocked;
                return KeyEvaluationDecision::Unlock(UnlockReason::MasterKey);
            }

            // 2. Check user's custom Unlock shortcut
            if self
                .unlock_shortcut
                .matches(&self.pressed_key_codes, active_modifiers)
            {
                self.pressed_key_codes.clear();
                self.current_lock_mode = LockMode::Unlocked;
                return KeyEvaluationDecision::Unlock(UnlockReason::CustomShortcut);
            }

            // 3. Optional toggle unlock using the active lock shortcut
            if self.allow_toggle_with_lock_shortcut
                && (self
                    .lock_all_shortcut
                    .matches(&self.pressed_key_codes, active_modifiers)
                    || self
                        .lock_keyboard_only_shortcut
                        .matches(&self.pressed_key_codes, active_modifiers))
            {
                self.pressed_key_codes.clear();
                self.current_lock_mode = LockMode::Unlocked;
                return KeyEvaluationDecision::Unlock(UnlockReason::ToggleLockShortcut);
            }

            // Swallow all other keys while locked
            KeyEvaluationDecision::Swallow
        } else {
            // While unlocked: do not trigger global shortcuts if disabled or currently recording
            if !self.enable_global_shortcuts || self.is_recording_shortcut {
                return KeyEvaluationDecision::PassThrough;
            }

            if self
                .lock_all_shortcut
                .matches(&self.pressed_key_codes, active_modifiers)
            {
                self.pressed_key_codes.clear();
                self.current_lock_mode = LockMode::KeyboardAndMouse;
                return KeyEvaluationDecision::Lock(LockMode::KeyboardAndMouse);
            }

            if self
                .lock_keyboard_only_shortcut
                .matches(&self.pressed_key_codes, active_modifiers)
            {
                self.pressed_key_codes.clear();
                self.current_lock_mode = LockMode::KeyboardOnly;
                return KeyEvaluationDecision::Lock(LockMode::KeyboardOnly);
            }

            KeyEvaluationDecision::PassThrough
        }
    }
}
