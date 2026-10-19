use crate::core::evaluator::{InputEvaluator, KeyEvaluationDecision, LockMode};
use crate::core::key_combo::{mods, vk};
use crate::core::settings::SettingsStore;
use crate::input::{BackendEvent, PlatformInputBackend};
use std::fs::{self, OpenOptions};
use std::os::unix::io::AsRawFd;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::{self, Receiver, Sender};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;

// Linux evdev ioctl request for EVIOCGRAB: _IOW('E', 0x90, int) = 0x40044590
const EVIOCGRAB: libc::c_ulong = 0x4004_4590;
const EV_KEY: u16 = 0x01;

#[repr(C)]
struct LinuxInputEvent {
    tv_sec: libc::time_t,
    tv_usec: libc::suseconds_t,
    type_: u16,
    code: u16,
    value: i32,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum EvdevClass {
    Keyboard,
    Pointer,
}

struct GrabbedDevice {
    file: fs::File,
    class: EvdevClass,
    is_grabbed: bool,
}

impl GrabbedDevice {
    fn set_grab(&mut self, should_grab: bool) {
        if self.is_grabbed == should_grab {
            return;
        }
        let arg: libc::c_int = if should_grab { 1 } else { 0 };
        let res = unsafe { libc::ioctl(self.file.as_raw_fd(), EVIOCGRAB, arg) };
        if res == 0 {
            self.is_grabbed = should_grab;
        }
    }
}

impl Drop for GrabbedDevice {
    fn drop(&mut self) {
        self.set_grab(false);
    }
}

struct SharedLinuxState {
    evaluator: InputEvaluator,
    event_tx: Sender<BackendEvent>,
    held_modifiers: u8,
    has_device_access: bool,
}

/// Linux Input Backend using kernel `evdev` (`EVIOCGRAB`) for universal Wayland & X11 support.
/// Dynamically grabs only keyboard devices in `KeyboardOnly` mode, and both keyboard + pointer
/// devices in `KeyboardAndMouse` (Full Lock) mode.
pub struct LinuxInputBackend {
    state: Arc<Mutex<SharedLinuxState>>,
    event_rx: Receiver<BackendEvent>,
    stop_flag: Arc<AtomicBool>,
    started: bool,
}

impl LinuxInputBackend {
    pub fn new() -> Self {
        let (tx, rx) = mpsc::channel();
        Self {
            state: Arc::new(Mutex::new(SharedLinuxState {
                evaluator: InputEvaluator::new(),
                event_tx: tx,
                held_modifiers: mods::NONE,
                has_device_access: false,
            })),
            event_rx: rx,
            stop_flag: Arc::new(AtomicBool::new(false)),
            started: false,
        }
    }

    fn discover_evdev_devices() -> Vec<GrabbedDevice> {
        let mut devices = Vec::new();
        let Ok(entries) = fs::read_dir("/dev/input") else {
            return devices;
        };

        for entry in entries.flatten() {
            let path = entry.path();
            let Some(name) = path.file_name().and_then(|n| n.to_str()) else {
                continue;
            };
            if !name.starts_with("event") {
                continue;
            }

            if let Ok(file) = OpenOptions::new().read(true).open(&path) {
                unsafe {
                    let fd = file.as_raw_fd();
                    let flags = libc::fcntl(fd, libc::F_GETFL, 0);
                    let _ = libc::fcntl(fd, libc::F_SETFL, flags | libc::O_NONBLOCK);
                }

                // Read sysfs capabilities to classify keyboard vs mouse/touchpad
                let sys_caps_path = format!("/sys/class/input/{}/device/capabilities/key", name);
                let sys_rel_path = format!("/sys/class/input/{}/device/capabilities/rel", name);
                let sys_abs_path = format!("/sys/class/input/{}/device/capabilities/abs", name);

                let key_caps = fs::read_to_string(sys_caps_path).unwrap_or_default();
                let rel_caps = fs::read_to_string(sys_rel_path).unwrap_or_default();
                let abs_caps = fs::read_to_string(sys_abs_path).unwrap_or_default();

                let is_pointer =
                    rel_caps.trim() != "0" && !rel_caps.trim().is_empty() || abs_caps.trim() != "0";
                let is_keyboard = key_caps.trim().len() > 8;

                if is_keyboard {
                    devices.push(GrabbedDevice {
                        file,
                        class: EvdevClass::Keyboard,
                        is_grabbed: false,
                    });
                } else if is_pointer {
                    devices.push(GrabbedDevice {
                        file,
                        class: EvdevClass::Pointer,
                        is_grabbed: false,
                    });
                }
            }
        }
        devices
    }
}

impl PlatformInputBackend for LinuxInputBackend {
    fn start(&mut self) {
        if self.started {
            return;
        }
        self.started = true;
        self.stop_flag.store(false, Ordering::SeqCst);

        let state_arc = Arc::clone(&self.state);
        let stop_arc = Arc::clone(&self.stop_flag);

        thread::spawn(move || {
            let mut devices = Self::discover_evdev_devices();
            if let Ok(mut guard) = state_arc.lock() {
                guard.has_device_access = !devices.is_empty();
            }

            let event_size = std::mem::size_of::<LinuxInputEvent>();

            while !stop_arc.load(Ordering::Relaxed) {
                let current_mode = state_arc
                    .lock()
                    .map(|g| g.evaluator.current_lock_mode)
                    .unwrap_or(LockMode::Unlocked);

                // Synchronize EVIOCGRAB state across all discovered devices
                for dev in &mut devices {
                    let want_grab = match current_mode {
                        LockMode::Unlocked => false,
                        LockMode::KeyboardOnly => dev.class == EvdevClass::Keyboard,
                        LockMode::KeyboardAndMouse => true,
                    };
                    dev.set_grab(want_grab);
                }

                // Poll keyboard devices for key events
                let mut raw_ev = LinuxInputEvent {
                    tv_sec: 0,
                    tv_usec: 0,
                    type_: 0,
                    code: 0,
                    value: 0,
                };

                for dev in &mut devices {
                    loop {
                        let bytes_read = unsafe {
                            libc::read(
                                dev.file.as_raw_fd(),
                                &mut raw_ev as *mut _ as *mut libc::c_void,
                                event_size,
                            )
                        };
                        if bytes_read != event_size as isize {
                            break;
                        }

                        if dev.class == EvdevClass::Keyboard && raw_ev.type_ == EV_KEY {
                            // Linux evdev values: 0 = release, 1 = press, 2 = autorepeat
                            let is_down = raw_ev.value == 1 || raw_ev.value == 2;
                            let is_repeat = raw_ev.value == 2;

                            if let Some(vk_code) = linux_keycode_to_vk(raw_ev.code) {
                                if let Ok(mut state) = state_arc.lock() {
                                    let mod_bit = match vk_code {
                                        vk::LCONTROL | vk::RCONTROL => mods::CTRL,
                                        vk::LMENU | vk::RMENU => mods::ALT,
                                        vk::LSHIFT | vk::RSHIFT => mods::SHIFT,
                                        vk::LWIN | vk::RWIN => mods::META,
                                        _ => mods::NONE,
                                    };

                                    if mod_bit != mods::NONE {
                                        if is_down {
                                            state.held_modifiers |= mod_bit;
                                        } else {
                                            state.held_modifiers &= !mod_bit;
                                        }
                                    }

                                    let active_mods = state.held_modifiers;
                                    match state.evaluator.evaluate_key_event(
                                        vk_code,
                                        is_down,
                                        active_mods,
                                        is_repeat,
                                    ) {
                                        KeyEvaluationDecision::Lock(mode) => {
                                            let _ = state.event_tx.send(BackendEvent::Locked(mode));
                                        }
                                        KeyEvaluationDecision::Unlock(reason) => {
                                            state.held_modifiers = mods::NONE;
                                            let _ =
                                                state.event_tx.send(BackendEvent::Unlocked(reason));
                                        }
                                        KeyEvaluationDecision::PassThrough
                                        | KeyEvaluationDecision::Swallow => {}
                                    }
                                }
                            }
                        }
                    }
                }

                thread::sleep(Duration::from_millis(8));
            }

            for dev in &mut devices {
                dev.set_grab(false);
            }
        });
    }

    fn stop(&mut self) {
        self.stop_flag.store(true, Ordering::SeqCst);
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
    }

    fn poll_events(&mut self) -> Vec<BackendEvent> {
        let mut out = Vec::new();
        while let Ok(ev) = self.event_rx.try_recv() {
            out.push(ev);
        }
        out
    }

    fn is_healthy(&self) -> bool {
        self.state
            .lock()
            .map(|g| g.has_device_access)
            .unwrap_or(false)
    }

    fn backend_description(&self) -> &'static str {
        if self.is_healthy() {
            "Linux Kernel evdev Input Engine (Wayland & X11 EVIOCGRAB Ready)"
        } else {
            "Linux Input Engine (Add user to 'input' group for Wayland EVIOCGRAB)"
        }
    }
}

fn linux_keycode_to_vk(code: u16) -> Option<u16> {
    match code {
        1 => Some(vk::ESCAPE),
        2..=10 => Some(0x31 + (code - 2)), // 1..9
        11 => Some(0x30),                  // 0
        14 => Some(vk::BACKSPACE),
        15 => Some(vk::TAB),
        16 => Some(0x51), // Q
        17 => Some(0x57), // W
        18 => Some(0x45), // E
        19 => Some(0x52), // R
        20 => Some(0x54), // T
        21 => Some(0x59), // Y
        22 => Some(0x55), // U
        23 => Some(0x49), // I
        24 => Some(0x4F), // O
        25 => Some(0x50), // P
        28 => Some(vk::RETURN),
        29 | 97 => Some(vk::LCONTROL),
        30 => Some(0x41), // A
        31 => Some(0x53), // S
        32 => Some(0x44), // D
        33 => Some(0x46), // F
        34 => Some(0x47), // G
        35 => Some(0x48), // H
        36 => Some(0x4A), // J
        37 => Some(0x4B), // K
        38 => Some(0x4C), // L
        42 | 54 => Some(vk::LSHIFT),
        44 => Some(0x5A), // Z
        45 => Some(0x58), // X
        46 => Some(0x43), // C
        47 => Some(0x56), // V
        48 => Some(0x42), // B
        49 => Some(0x4E), // N
        50 => Some(0x4D), // M
        56 | 100 => Some(vk::LMENU),
        57 => Some(vk::SPACE),
        59..=68 => Some(vk::F1 + (code - 59)),
        87 => Some(0x7A), // F11
        88 => Some(vk::F12),
        102 => Some(vk::HOME),
        103 => Some(vk::UP),
        104 => Some(vk::PAGE_UP),
        105 => Some(vk::LEFT),
        106 => Some(vk::RIGHT),
        107 => Some(vk::END),
        108 => Some(vk::DOWN),
        109 => Some(vk::PAGE_DOWN),
        110 => Some(vk::INSERT),
        111 => Some(vk::DELETE),
        125 | 126 => Some(vk::LWIN),
        _ => None,
    }
}
