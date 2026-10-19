pub mod evaluator;
pub mod key_combo;
pub mod settings;
pub mod updater;

#[cfg(test)]
mod tests {
    use super::evaluator::{InputEvaluator, KeyEvaluationDecision, LockMode, UnlockReason};
    use super::key_combo::{mods, vk, KeyCombo};
    use super::settings::{OverlayStyle, SettingsStore, ShortcutTarget};
    use super::updater::{GitHubRelease, UpdateChecker};

    #[test]
    fn test_master_key_simultaneous_chord_unlocks_from_full_lock() {
        let mut eval = InputEvaluator::new();
        eval.current_lock_mode = LockMode::KeyboardAndMouse;

        // Pressing Esc (0x1B), Left (0x25), Up (0x26) swallows while 4th key is not yet held
        assert_eq!(
            eval.evaluate_key_event(vk::ESCAPE, true, mods::NONE, false),
            KeyEvaluationDecision::Swallow
        );
        assert_eq!(
            eval.evaluate_key_event(vk::LEFT, true, mods::NONE, false),
            KeyEvaluationDecision::Swallow
        );
        assert_eq!(
            eval.evaluate_key_event(vk::UP, true, mods::NONE, false),
            KeyEvaluationDecision::Swallow
        );

        // Pressing Right (0x27) completes the 4-key Master Key chord and immediately unlocks
        assert_eq!(
            eval.evaluate_key_event(vk::RIGHT, true, mods::NONE, false),
            KeyEvaluationDecision::Unlock(UnlockReason::MasterKey)
        );
        assert_eq!(eval.current_lock_mode, LockMode::Unlocked);
    }

    #[test]
    fn test_separate_lock_all_and_lock_keyboard_only_shortcuts() {
        let mut eval = InputEvaluator::new();
        let default_mods = mods::CTRL | mods::ALT | mods::META;

        // Ctrl+Alt+Win+K triggers KeyboardOnly lock
        assert_eq!(
            eval.evaluate_key_event(vk::KEY_K, true, default_mods, false),
            KeyEvaluationDecision::Lock(LockMode::KeyboardOnly)
        );
        assert_eq!(eval.current_lock_mode, LockMode::KeyboardOnly);

        eval.current_lock_mode = LockMode::Unlocked;

        // Ctrl+Alt+Win+L triggers KeyboardAndMouse full lock
        assert_eq!(
            eval.evaluate_key_event(vk::KEY_L, true, default_mods, false),
            KeyEvaluationDecision::Lock(LockMode::KeyboardAndMouse)
        );
        assert_eq!(eval.current_lock_mode, LockMode::KeyboardAndMouse);
    }

    #[test]
    fn test_auto_repeat_does_not_trigger_lock_or_toggle_loop() {
        let mut eval = InputEvaluator::new();
        let default_mods = mods::CTRL | mods::ALT | mods::META;
        eval.allow_toggle_with_lock_shortcut = true;

        // First press locks
        assert_eq!(
            eval.evaluate_key_event(vk::KEY_L, true, default_mods, false),
            KeyEvaluationDecision::Lock(LockMode::KeyboardAndMouse)
        );
        assert_eq!(eval.current_lock_mode, LockMode::KeyboardAndMouse);

        // Subsequent held auto-repeats must be swallowed and NEVER toggle unlock
        assert_eq!(
            eval.evaluate_key_event(vk::KEY_L, true, default_mods, true),
            KeyEvaluationDecision::Swallow
        );
        assert_eq!(eval.current_lock_mode, LockMode::KeyboardAndMouse);
    }

    #[test]
    fn test_missed_key_release_does_not_break_single_key_shortcut() {
        let mut eval = InputEvaluator::new();
        let default_mods = mods::CTRL | mods::ALT | mods::META;

        // Simulate a phantom key ('A' = 0x41) stuck in pressed_key_codes due to missed key-up
        let _ = eval.evaluate_key_event(0x41, true, mods::NONE, false);

        // Single-key shortcut Ctrl+Alt+Win+L still matches because of subset matching
        assert_eq!(
            eval.evaluate_key_event(vk::KEY_L, true, default_mods, false),
            KeyEvaluationDecision::Lock(LockMode::KeyboardAndMouse)
        );
    }

    #[test]
    fn test_shortcut_safety_validation() {
        // Safe: Ctrl+L, Win+L, Ctrl+Alt+Win+L
        let ctrl_l = KeyCombo::new([vk::KEY_L], mods::CTRL);
        assert!(ctrl_l.is_valid_user_shortcut());

        let alt_shift_l = KeyCombo::new([vk::KEY_L], mods::ALT | mods::SHIFT);
        assert!(alt_shift_l.is_valid_user_shortcut());

        // Safe: 3+ key chords without modifiers (like Master Key)
        assert!(KeyCombo::master_unlock_key().is_valid_user_shortcut());

        // Unsafe: Bare Shift + A (typing capital letters)
        let shift_a = KeyCombo::new([0x41], mods::SHIFT);
        assert!(!shift_a.is_valid_user_shortcut());

        // Unsafe: Two plain letters (J + K) without modifiers
        let jk_chord = KeyCombo::new([0x4A, 0x4B], mods::NONE);
        assert!(!jk_chord.is_valid_user_shortcut());

        // Unsafe: Empty
        let empty = KeyCombo::new([], mods::NONE);
        assert!(!empty.is_valid_user_shortcut());
    }

    #[test]
    fn test_duplicate_shortcut_detection() {
        let store = SettingsStore::default();

        // Master Key is always reserved
        assert!(store
            .duplicate_check_message(&KeyCombo::master_unlock_key(), ShortcutTarget::LockAll)
            .is_some());

        // Conflict with LockAll when assigning Unlock
        assert!(store
            .duplicate_check_message(&store.lock_all_shortcut, ShortcutTarget::Unlock)
            .is_some());

        // Assigning same shortcut to its own target is allowed
        assert!(store
            .duplicate_check_message(&store.lock_all_shortcut, ShortcutTarget::LockAll)
            .is_none());
    }

    #[test]
    fn test_settings_serialization_and_reset() {
        let mut store = SettingsStore::default();
        store.overlay_style = OverlayStyle::Invisible;
        store.set_auto_unlock_minutes(45);
        store.show_unlock_hint_on_screen = false;

        let json = serde_json::to_string(&store).unwrap();
        let decoded: SettingsStore = serde_json::from_str(&json).unwrap();
        assert_eq!(decoded.overlay_style, OverlayStyle::Invisible);
        assert_eq!(decoded.auto_unlock_minutes, 45);
        assert!(!decoded.show_unlock_hint_on_screen);

        let mut reset_store = decoded;
        reset_store.reset_to_defaults();
        assert_eq!(reset_store.overlay_style, OverlayStyle::BlackoutCleaning);
        assert_eq!(reset_store.auto_unlock_minutes, 10);
        assert!(reset_store.show_unlock_hint_on_screen);
    }

    #[test]
    fn test_version_comparison_logic() {
        assert!(UpdateChecker::is_version_newer("1.0.2", "1.0.1"));
        assert!(UpdateChecker::is_version_newer("v1.0.2", "1.0.1"));
        assert!(UpdateChecker::is_version_newer("v1.1.0", "1.0.9"));
        assert!(UpdateChecker::is_version_newer("2.0.0", "1.9.9"));
        assert!(UpdateChecker::is_version_newer("1.0.1", "1.0"));

        assert!(!UpdateChecker::is_version_newer("1.0.1", "1.0.1"));
        assert!(!UpdateChecker::is_version_newer("v1.0.1", "1.0.1"));
        assert!(!UpdateChecker::is_version_newer("1.0.0", "1.0.1"));
        assert!(!UpdateChecker::is_version_newer("1.0", "1.0.1"));
    }

    #[test]
    fn test_release_json_parsing() {
        let raw = r#"{
            "tag_name": "v1.1.0",
            "name": "SwipeIt 1.1.0",
            "body": "Windows and Linux release",
            "html_url": "https://github.com/TotallyRaiva/SwipeIt/releases/tag/v1.1.0",
            "assets": [
                {
                    "name": "SwipeIt-Windows-x64.exe",
                    "browser_download_url": "https://github.com/TotallyRaiva/SwipeIt/releases/download/v1.1.0/SwipeIt-Windows-x64.exe",
                    "size": 4200000
                }
            ]
        }"#;
        let parsed: GitHubRelease = serde_json::from_str(raw).unwrap();
        assert_eq!(parsed.tag_name, "v1.1.0");
        assert_eq!(parsed.assets.len(), 1);
        assert_eq!(parsed.assets[0].name, "SwipeIt-Windows-x64.exe");
    }
}
