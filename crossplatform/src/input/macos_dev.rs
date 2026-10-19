use crate::core::evaluator::{InputEvaluator, KeyEvaluationDecision, LockMode};
use crate::core::settings::SettingsStore;
use crate::input::{BackendEvent, PlatformInputBackend};

/// Local development & UI preview backend for macOS so the cross-platform Rust UI
/// and core evaluator can be tested interactively on a Mac without conflicting with the native Swift app.
pub struct MacPreviewBackend {
    evaluator: InputEvaluator,
    pending_events: Vec<BackendEvent>,
    running: bool,
}

impl Default for MacPreviewBackend {
    fn default() -> Self {
        Self::new()
    }
}

impl MacPreviewBackend {
    pub fn new() -> Self {
        Self {
            evaluator: InputEvaluator::new(),
            pending_events: Vec::new(),
            running: false,
        }
    }

    #[allow(dead_code)]
    pub fn simulate_key(&mut self, key_code: u16, is_down: bool, modifiers: u8, repeat: bool) {
        match self
            .evaluator
            .evaluate_key_event(key_code, is_down, modifiers, repeat)
        {
            KeyEvaluationDecision::Lock(mode) => {
                self.pending_events.push(BackendEvent::Locked(mode));
            }
            KeyEvaluationDecision::Unlock(reason) => {
                self.pending_events.push(BackendEvent::Unlocked(reason));
            }
            KeyEvaluationDecision::PassThrough | KeyEvaluationDecision::Swallow => {}
        }
    }
}

impl PlatformInputBackend for MacPreviewBackend {
    fn start(&mut self) {
        self.running = true;
    }

    fn stop(&mut self) {
        self.running = false;
        self.evaluator.clear_pressed_keys();
    }

    fn sync_config(&mut self, settings: &SettingsStore, lock_mode: LockMode, is_recording: bool) {
        self.evaluator.lock_all_shortcut = settings.lock_all_shortcut.clone();
        self.evaluator.lock_keyboard_only_shortcut = settings.lock_keyboard_only_shortcut.clone();
        self.evaluator.unlock_shortcut = settings.unlock_shortcut.clone();
        self.evaluator.allow_toggle_with_lock_shortcut = settings.allow_toggle_with_lock_shortcut;
        self.evaluator.enable_global_shortcuts = settings.enable_global_shortcuts;
        self.evaluator.current_lock_mode = lock_mode;
        self.evaluator.is_recording_shortcut = is_recording;
    }

    fn poll_events(&mut self) -> Vec<BackendEvent> {
        std::mem::take(&mut self.pending_events)
    }

    fn is_healthy(&self) -> bool {
        self.running
    }

    fn backend_description(&self) -> &'static str {
        "macOS Dev Preview Mode (Windows/Linux Cross-Platform UI)"
    }
}
