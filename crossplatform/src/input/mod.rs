use crate::core::evaluator::{LockMode, UnlockReason};
use crate::core::settings::SettingsStore;

#[cfg(target_os = "macos")]
pub mod macos_dev;

#[cfg(target_os = "windows")]
pub mod windows;

#[cfg(target_os = "linux")]
pub mod linux;

/// Events emitted by the low-level OS input hook thread back to the UI thread.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BackendEvent {
    Locked(LockMode),
    Unlocked(UnlockReason),
}

/// Unified interface implemented by Windows (`WH_KEYBOARD_LL` / `WH_MOUSE_LL`),
/// Linux (`evdev` `EVIOCGRAB` / X11), and macOS local dev preview.
pub trait PlatformInputBackend {
    fn start(&mut self);
    fn stop(&mut self);
    fn sync_config(&mut self, settings: &SettingsStore, lock_mode: LockMode, is_recording: bool);
    fn poll_events(&mut self) -> Vec<BackendEvent>;
    fn is_healthy(&self) -> bool;
    fn backend_description(&self) -> &'static str;
}

pub fn create_backend() -> Box<dyn PlatformInputBackend> {
    #[cfg(target_os = "windows")]
    {
        Box::new(windows::WindowsInputBackend::new())
    }
    #[cfg(target_os = "linux")]
    {
        Box::new(linux::LinuxInputBackend::new())
    }
    #[cfg(target_os = "macos")]
    {
        Box::new(macos_dev::MacPreviewBackend::new())
    }
}
