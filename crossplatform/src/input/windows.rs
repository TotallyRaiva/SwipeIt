use crate::core::evaluator::{InputEvaluator, KeyEvaluationDecision, LockMode};
use crate::core::key_combo::{mods, vk};
use crate::core::settings::SettingsStore;
use crate::input::{BackendEvent, PlatformInputBackend};
use std::sync::mpsc::{self, Receiver, Sender};
use std::sync::{Arc, Mutex, OnceLock};
use std::thread;
use windows_sys::Win32::Foundation::{LPARAM, LRESULT, WPARAM};
use windows_sys::Win32::System::Threading::{
    GetCurrentThread, GetCurrentThreadId, SetThreadPriority, THREAD_PRIORITY_HIGHEST,
};
use windows_sys::Win32::UI::WindowsAndMessaging::{
    CallNextHookEx, DispatchMessageW, GetMessageW, PostThreadMessageW, SetWindowsHookExW,
    TranslateMessage, UnhookWindowsHookEx, HHOOK, KBDLLHOOKSTRUCT, MSG, WH_KEYBOARD_LL,
    WH_MOUSE_LL, WM_KEYDOWN, WM_KEYUP, WM_QUIT, WM_SYSKEYDOWN, WM_SYSKEYUP, WM_USER,
};

const WM_SYNC_HOOK_STATE: u32 = WM_USER + 101;

struct SharedWinHookState {
    evaluator: InputEvaluator,
    event_tx: Sender<BackendEvent>,
    held_modifiers: u8,
    hook_thread_id: u32,
    is_healthy: bool,
}

static GLOBAL_HOOK_STATE: OnceLock<Arc<Mutex<SharedWinHookState>>> = OnceLock::new();

unsafe extern "system" fn low_level_keyboard_proc(
    code: i32,
    wparam: WPARAM,
    lparam: LPARAM,
) -> LRESULT {
    if code >= 0 && lparam != 0 {
        let kb = &*(lparam as *const KBDLLHOOKSTRUCT);
        let vk_code = kb.vkCode as u16;
        let msg = wparam as u32;
        let is_key_down = msg == WM_KEYDOWN || msg == WM_SYSKEYDOWN;
        let is_key_up = msg == WM_KEYUP || msg == WM_SYSKEYUP;

        if is_key_down || is_key_up {
            if let Some(state_arc) = GLOBAL_HOOK_STATE.get() {
                if let Ok(mut state) = state_arc.lock() {
                    // 1. Track physical modifier state directly inside the hook so swallowed
                    // modifier keys (like VK_LWIN / Alt while locked) still register for unlock combos.
                    let mod_bit = match vk_code {
                        0x11 | vk::LCONTROL | vk::RCONTROL => mods::CTRL,
                        0x12 | vk::LMENU | vk::RMENU => mods::ALT,
                        0x10 | vk::LSHIFT | vk::RSHIFT => mods::SHIFT,
                        vk::LWIN | vk::RWIN => mods::META,
                        _ => mods::NONE,
                    };

                    if mod_bit != mods::NONE {
                        if is_key_down {
                            state.held_modifiers |= mod_bit;
                        } else {
                            state.held_modifiers &= !mod_bit;
                        }
                    }

                    // 2. Detect key auto-repeat when key is already recorded as held
                    let is_autorepeat =
                        is_key_down && state.evaluator.pressed_keys().contains(&vk_code);
                    let active_mods = state.held_modifiers;

                    let decision = state.evaluator.evaluate_key_event(
                        vk_code,
                        is_key_down,
                        active_mods,
                        is_autorepeat,
                    );

                    match decision {
                        KeyEvaluationDecision::PassThrough => {
                            return CallNextHookEx(std::ptr::null_mut(), code, wparam, lparam);
                        }
                        KeyEvaluationDecision::Swallow => {
                            return 1;
                        }
                        KeyEvaluationDecision::Lock(mode) => {
                            let _ = state.event_tx.send(BackendEvent::Locked(mode));
                            if state.hook_thread_id != 0 {
                                let _ = PostThreadMessageW(
                                    state.hook_thread_id,
                                    WM_SYNC_HOOK_STATE,
                                    0,
                                    0,
                                );
                            }
                            return 1;
                        }
                        KeyEvaluationDecision::Unlock(reason) => {
                            state.held_modifiers = mods::NONE;
                            let _ = state.event_tx.send(BackendEvent::Unlocked(reason));
                            if state.hook_thread_id != 0 {
                                let _ = PostThreadMessageW(
                                    state.hook_thread_id,
                                    WM_SYNC_HOOK_STATE,
                                    0,
                                    0,
                                );
                            }
                            return 1;
                        }
                    }
                }
            }
        }
    }

    CallNextHookEx(std::ptr::null_mut(), code, wparam, lparam)
}

unsafe extern "system" fn low_level_mouse_proc(
    code: i32,
    wparam: WPARAM,
    lparam: LPARAM,
) -> LRESULT {
    if code >= 0 {
        if let Some(state_arc) = GLOBAL_HOOK_STATE.get() {
            if let Ok(state) = state_arc.lock() {
                if state.evaluator.current_lock_mode == LockMode::KeyboardAndMouse {
                    // Swallow all mouse movement, clicks, and scroll wheel events in Full Lock
                    return 1;
                }
            }
        }
    }
    CallNextHookEx(std::ptr::null_mut(), code, wparam, lparam)
}

/// Native Win32 Low-Level Hook Backend (`WH_KEYBOARD_LL` & `WH_MOUSE_LL`).
/// Runs on a dedicated high-priority message pump thread and dynamically attaches `WH_MOUSE_LL`
/// only during Full Lock so unlocked and Keyboard-Only modes have zero mouse hook overhead.
pub struct WindowsInputBackend {
    state: Arc<Mutex<SharedWinHookState>>,
    event_rx: Receiver<BackendEvent>,
    started: bool,
}

impl WindowsInputBackend {
    pub fn new() -> Self {
        let (tx, rx) = mpsc::channel();
        let state = GLOBAL_HOOK_STATE
            .get_or_init(|| {
                Arc::new(Mutex::new(SharedWinHookState {
                    evaluator: InputEvaluator::new(),
                    event_tx: tx,
                    held_modifiers: mods::NONE,
                    hook_thread_id: 0,
                    is_healthy: false,
                }))
            })
            .clone();

        Self {
            state,
            event_rx: rx,
            started: false,
        }
    }

    fn notify_hook_thread(&self) {
        if let Ok(guard) = self.state.lock() {
            if guard.hook_thread_id != 0 {
                unsafe {
                    let _ =
                        PostThreadMessageW(guard.hook_thread_id, WM_SYNC_HOOK_STATE, 0, 0);
                }
            }
        }
    }
}

impl PlatformInputBackend for WindowsInputBackend {
    fn start(&mut self) {
        if self.started {
            self.notify_hook_thread();
            return;
        }
        self.started = true;
        let state_arc = Arc::clone(&self.state);

        thread::spawn(move || unsafe {
            let _ = SetThreadPriority(GetCurrentThread(), THREAD_PRIORITY_HIGHEST);
            let tid = GetCurrentThreadId();

            let kb_hook: HHOOK = SetWindowsHookExW(
                WH_KEYBOARD_LL,
                Some(low_level_keyboard_proc),
                std::ptr::null_mut(),
                0,
            );
            let mut mouse_hook: HHOOK = std::ptr::null_mut();

            if let Ok(mut guard) = state_arc.lock() {
                guard.hook_thread_id = tid;
                guard.is_healthy = !kb_hook.is_null();
            }

            let mut msg: MSG = std::mem::zeroed();
            while GetMessageW(&mut msg, std::ptr::null_mut(), 0, 0) > 0 {
                if msg.message == WM_SYNC_HOOK_STATE {
                    let needs_mouse_hook = state_arc
                        .lock()
                        .map(|g| g.evaluator.current_lock_mode == LockMode::KeyboardAndMouse)
                        .unwrap_or(false);

                    if needs_mouse_hook && mouse_hook.is_null() {
                        mouse_hook = SetWindowsHookExW(
                            WH_MOUSE_LL,
                            Some(low_level_mouse_proc),
                            std::ptr::null_mut(),
                            0,
                        );
                    } else if !needs_mouse_hook && !mouse_hook.is_null() {
                        let _ = UnhookWindowsHookEx(mouse_hook);
                        mouse_hook = std::ptr::null_mut();
                    }
                } else {
                    TranslateMessage(&msg);
                    DispatchMessageW(&msg);
                }
            }

            if !mouse_hook.is_null() {
                let _ = UnhookWindowsHookEx(mouse_hook);
            }
            if !kb_hook.is_null() {
                let _ = UnhookWindowsHookEx(kb_hook);
            }
        });
    }

    fn stop(&mut self) {
        if let Ok(mut guard) = self.state.lock() {
            guard.evaluator.current_lock_mode = LockMode::Unlocked;
            guard.evaluator.clear_pressed_keys();
            guard.held_modifiers = mods::NONE;
            if guard.hook_thread_id != 0 {
                unsafe {
                    let _ = PostThreadMessageW(guard.hook_thread_id, WM_QUIT, 0, 0);
                }
                guard.hook_thread_id = 0;
            }
            guard.is_healthy = false;
        }
        self.started = false;
    }

    fn sync_config(&mut self, settings: &SettingsStore, lock_mode: LockMode, is_recording: bool) {
        if let Ok(mut guard) = self.state.lock() {
            guard.evaluator.lock_all_shortcut = settings.lock_all_shortcut.clone();
            guard.evaluator.lock_keyboard_only_shortcut =
                settings.lock_keyboard_only_shortcut.clone();
            guard.evaluator.unlock_shortcut = settings.unlock_shortcut.clone();
            guard.evaluator.allow_toggle_with_lock_shortcut =
                settings.allow_toggle_with_lock_shortcut;
            guard.evaluator.enable_global_shortcuts = settings.enable_global_shortcuts;
            guard.evaluator.current_lock_mode = lock_mode;
            guard.evaluator.is_recording_shortcut = is_recording;
            if !lock_mode.is_locked() {
                guard.evaluator.clear_pressed_keys();
                guard.held_modifiers = mods::NONE;
            }
        }
        self.notify_hook_thread();
    }

    fn poll_events(&mut self) -> Vec<BackendEvent> {
        let mut events = Vec::new();
        while let Ok(ev) = self.event_rx.try_recv() {
            events.push(ev);
        }
        events
    }

    fn is_healthy(&self) -> bool {
        self.state.lock().map(|g| g.is_healthy).unwrap_or(false)
    }

    fn backend_description(&self) -> &'static str {
        "Win32 Low-Level Input Engine (WH_KEYBOARD_LL + Dynamic WH_MOUSE_LL)"
    }
}
