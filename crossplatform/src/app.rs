use crate::core::evaluator::{LockMode, UnlockReason};
use crate::core::key_combo::{mods, vk, KeyCombo};
use crate::core::settings::{OverlayStyle, SettingsStore, ShortcutTarget};
use crate::core::updater::{UpdateChecker, CURRENT_APP_VERSION};
use crate::input::{create_backend, BackendEvent, PlatformInputBackend};
use eframe::egui::{
    self, Align, Color32, FontFamily, FontId, Frame, Id, Key, Layout, Margin, RichText, Rounding,
    Sense, Stroke, Vec2, ViewportBuilder, ViewportCommand, ViewportId,
};
use std::collections::BTreeSet;
use std::time::{Duration, Instant};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum SettingsTab {
    Controls,
    Shortcuts,
    Safety,
}

pub struct SwipeItCrossApp {
    settings: SettingsStore,
    backend: Box<dyn PlatformInputBackend>,
    update_checker: UpdateChecker,
    lock_mode: LockMode,
    last_unlock_reason: Option<UnlockReason>,
    lock_started_at: Option<Instant>,
    selected_tab: SettingsTab,

    // Shortcut recorder state
    recording_target: Option<ShortcutTarget>,
    recording_held_keys: BTreeSet<u16>,
    recording_peak_keys: BTreeSet<u16>,
    recording_peak_mods: u8,
    recorder_error: Option<(ShortcutTarget, String)>,
    theme_initialized: bool,
}

impl SwipeItCrossApp {
    pub fn new(_cc: &eframe::CreationContext<'_>) -> Self {
        let mut settings = SettingsStore::load();
        let mut backend = create_backend();
        backend.sync_config(&settings, LockMode::Unlocked, false);
        backend.start();

        let update_checker = UpdateChecker::default();
        if settings.automatically_check_for_updates {
            if let Some(ts) =
                update_checker.check_for_updates(false, settings.last_update_check_timestamp)
            {
                settings.last_update_check_timestamp = ts;
                settings.save();
            }
        }

        Self {
            settings,
            backend,
            update_checker,
            lock_mode: LockMode::Unlocked,
            last_unlock_reason: None,
            lock_started_at: None,
            selected_tab: SettingsTab::Controls,
            recording_target: None,
            recording_held_keys: BTreeSet::new(),
            recording_peak_keys: BTreeSet::new(),
            recording_peak_mods: mods::NONE,
            recorder_error: None,
            theme_initialized: false,
        }
    }

    fn apply_custom_dark_theme(&mut self, ctx: &egui::Context) {
        if self.theme_initialized {
            return;
        }
        let mut visuals = egui::Visuals::dark();
        visuals.panel_fill = Color32::from_rgb(11, 13, 18); // #0B0D12
        visuals.window_fill = Color32::from_rgb(16, 19, 27);
        visuals.extreme_bg_color = Color32::from_rgb(8, 10, 14);
        visuals.faint_bg_color = Color32::from_rgb(20, 24, 33);
        visuals.widgets.noninteractive.bg_fill = Color32::from_rgb(20, 24, 33);
        visuals.widgets.inactive.bg_fill = Color32::from_rgb(28, 34, 48);
        visuals.widgets.hovered.bg_fill = Color32::from_rgb(38, 46, 66);
        visuals.widgets.active.bg_fill = Color32::from_rgb(59, 130, 246);
        visuals.selection.bg_fill = Color32::from_rgb(59, 130, 246);
        ctx.set_visuals(visuals);
        self.theme_initialized = true;
    }

    fn sync_backend(&mut self) {
        self.backend.sync_config(
            &self.settings,
            self.lock_mode,
            self.recording_target.is_some(),
        );
    }

    pub fn engage_lock(&mut self, mode: LockMode) {
        if mode == LockMode::Unlocked {
            self.unlock(UnlockReason::ManualUI);
            return;
        }
        self.cancel_recording();
        self.lock_mode = mode;
        self.lock_started_at = Some(Instant::now());
        self.sync_backend();
    }

    pub fn unlock(&mut self, reason: UnlockReason) {
        self.lock_mode = LockMode::Unlocked;
        self.last_unlock_reason = Some(reason);
        self.lock_started_at = None;
        self.sync_backend();
    }

    fn remaining_lock_seconds(&self) -> Option<u64> {
        if !self.lock_mode.is_locked() || !self.settings.auto_unlock_timer_enabled {
            return None;
        }
        let started = self.lock_started_at?;
        let total = Duration::from_secs((self.settings.auto_unlock_minutes as u64) * 60);
        let elapsed = started.elapsed();
        if elapsed >= total {
            Some(0)
        } else {
            Some((total - elapsed).as_secs())
        }
    }

    fn formatted_remaining_time(&self) -> Option<String> {
        let secs = self.remaining_lock_seconds()?;
        let mins = secs / 60;
        let rem = secs % 60;
        Some(format!("{:02}:{:02}", mins, rem))
    }

    fn start_recording(&mut self, target: ShortcutTarget) {
        self.recorder_error = None;
        self.recording_target = Some(target);
        self.recording_held_keys.clear();
        self.recording_peak_keys.clear();
        self.recording_peak_mods = mods::NONE;
        self.sync_backend();
    }

    fn cancel_recording(&mut self) {
        if self.recording_target.is_some() {
            self.recording_target = None;
            self.recording_held_keys.clear();
            self.recording_peak_keys.clear();
            self.recording_peak_mods = mods::NONE;
            self.sync_backend();
        }
    }

    fn handle_shortcut_recording_input(&mut self, ctx: &egui::Context) {
        let target = match self.recording_target {
            Some(t) => t,
            None => return,
        };

        // Bug #5 Fix: Cancel recording cleanly if window loses focus
        let focused = ctx.input(|i| i.focused);
        if !focused {
            self.cancel_recording();
            return;
        }

        let mut commit_candidate: Option<KeyCombo> = None;
        let mut cancel_pressed = false;

        ctx.input(|input| {
            let mut active_mods = mods::NONE;
            if input.modifiers.ctrl {
                active_mods |= mods::CTRL;
            }
            if input.modifiers.alt {
                active_mods |= mods::ALT;
            }
            if input.modifiers.shift {
                active_mods |= mods::SHIFT;
            }
            if input.modifiers.mac_cmd || input.modifiers.command {
                active_mods |= mods::META;
            }

            for event in &input.events {
                if let egui::Event::Key {
                    key,
                    pressed,
                    repeat,
                    ..
                } = event
                {
                    if *repeat {
                        continue;
                    }
                    if let Some(vk_code) = egui_key_to_vk(*key) {
                        if *pressed {
                            self.recording_held_keys.insert(vk_code);
                            self.recording_peak_keys.insert(vk_code);
                            if active_mods != mods::NONE {
                                self.recording_peak_mods = active_mods;
                            }

                            // Snappy commit when modifier(s) + single key are pressed
                            if self.recording_peak_mods != mods::NONE
                                && self.recording_peak_keys.len() == 1
                            {
                                commit_candidate = Some(KeyCombo::new(
                                    self.recording_peak_keys.clone(),
                                    self.recording_peak_mods,
                                ));
                            }
                        } else {
                            self.recording_held_keys.remove(&vk_code);
                            if self.recording_held_keys.is_empty() && commit_candidate.is_none() {
                                if self.recording_peak_keys.len() == 1
                                    && self.recording_peak_keys.contains(&vk::ESCAPE)
                                    && self.recording_peak_mods == mods::NONE
                                {
                                    cancel_pressed = true;
                                } else if !self.recording_peak_keys.is_empty() {
                                    commit_candidate = Some(KeyCombo::new(
                                        self.recording_peak_keys.clone(),
                                        self.recording_peak_mods,
                                    ));
                                }
                            }
                        }
                    }
                }
            }
        });

        if cancel_pressed {
            self.cancel_recording();
            return;
        }

        if let Some(candidate) = commit_candidate {
            if !candidate.is_valid_user_shortcut() {
                self.recorder_error = Some((
                    target,
                    format!(
                        "Shortcut too simple. Use Ctrl, {}, or Alt+Shift with a key (or 3+ keys for chords).",
                        KeyCombo::meta_key_label()
                    ),
                ));
                self.cancel_recording();
                return;
            }

            if let Some(dup_msg) = self.settings.duplicate_check_message(&candidate, target) {
                self.recorder_error = Some((target, dup_msg));
                self.cancel_recording();
                return;
            }

            match target {
                ShortcutTarget::LockAll => self.settings.lock_all_shortcut = candidate,
                ShortcutTarget::LockKeyboardOnly => {
                    self.settings.lock_keyboard_only_shortcut = candidate
                }
                ShortcutTarget::Unlock => self.settings.unlock_shortcut = candidate,
            }
            self.settings.save();
            self.cancel_recording();
        }
    }

    /// Checks whether the user pressed the unlock combo or Emergency Master Key inside a focused SwipeIt window.
    fn check_in_window_unlock_keys(&mut self, ctx: &egui::Context) {
        if !self.lock_mode.is_locked() {
            return;
        }

        let mut should_unlock: Option<UnlockReason> = None;
        ctx.input(|input| {
            let mut active_mods = mods::NONE;
            if input.modifiers.ctrl {
                active_mods |= mods::CTRL;
            }
            if input.modifiers.alt {
                active_mods |= mods::ALT;
            }
            if input.modifiers.shift {
                active_mods |= mods::SHIFT;
            }
            if input.modifiers.mac_cmd || input.modifiers.command {
                active_mods |= mods::META;
            }

            let mut held_vks = BTreeSet::new();
            for key in &input.keys_down {
                if let Some(vk_code) = egui_key_to_vk(*key) {
                    held_vks.insert(vk_code);
                }
            }

            if KeyCombo::master_unlock_key().matches(&held_vks, active_mods) {
                should_unlock = Some(UnlockReason::MasterKey);
            } else if self.settings.unlock_shortcut.matches(&held_vks, active_mods) {
                should_unlock = Some(UnlockReason::CustomShortcut);
            }
        });

        if let Some(reason) = should_unlock {
            self.unlock(reason);
        }
    }

    // MARK: - UI Sections

    fn render_header(&mut self, ui: &mut egui::Ui) {
        ui.horizontal(|ui| {
            // App Badge Icon
            let (rect, _) = ui.allocate_exact_size(Vec2::splat(42.0), Sense::hover());
            let badge_color = if self.lock_mode.is_locked() {
                Color32::from_rgb(249, 115, 22)
            } else {
                Color32::from_rgb(59, 130, 246)
            };
            ui.painter()
                .rect_filled(rect, Rounding::same(10.0), badge_color);
            ui.painter().text(
                rect.center(),
                egui::Align2::CENTER_CENTER,
                if self.lock_mode.is_locked() {
                    "🔒"
                } else {
                    "⌨"
                },
                FontId::new(20.0, FontFamily::Proportional),
                Color32::WHITE,
            );

            ui.add_space(6.0);

            ui.vertical(|ui| {
                ui.horizontal(|ui| {
                    ui.label(
                        RichText::new("SwipeIt")
                            .size(19.0)
                            .strong()
                            .color(Color32::WHITE),
                    );

                    // Status dot + text
                    let (status_color, status_text) = if self.lock_mode.is_locked() {
                        (
                            Color32::from_rgb(249, 115, 22),
                            self.lock_mode.short_title(),
                        )
                    } else {
                        (Color32::from_rgb(34, 197, 94), "Ready")
                    };

                    Frame::none()
                        .fill(status_color.gamma_multiply(0.16))
                        .stroke(Stroke::new(1.0_f32, status_color.gamma_multiply(0.45)))
                        .rounding(Rounding::same(10.0))
                        .inner_margin(Margin::symmetric(8.0, 2.0))
                        .show(ui, |ui| {
                            ui.label(
                                RichText::new(format!("● {}", status_text))
                                    .size(11.5)
                                    .strong()
                                    .color(status_color),
                            );
                        });
                });

                ui.label(
                    RichText::new(self.backend.backend_description())
                        .size(11.5)
                        .color(Color32::from_rgb(148, 163, 184)),
                );
            });

            ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
                if let Some(remaining) = self.formatted_remaining_time() {
                    Frame::none()
                        .fill(Color32::from_rgb(249, 115, 22).gamma_multiply(0.15))
                        .stroke(Stroke::new(
                            1.0_f32,
                            Color32::from_rgb(249, 115, 22).gamma_multiply(0.4),
                        ))
                        .rounding(Rounding::same(12.0))
                        .inner_margin(Margin::symmetric(10.0, 5.0))
                        .show(ui, |ui| {
                            ui.label(
                                RichText::new(format!("⏱ {}", remaining))
                                    .monospace()
                                    .strong()
                                    .color(Color32::from_rgb(251, 146, 60)),
                            );
                        });
                }
            });
        });
    }

    fn render_update_banner(&mut self, ui: &mut egui::Ui) {
        let snap = self.update_checker.snapshot();
        if !snap.update_available {
            return;
        }

        ui.add_space(8.0);
        Frame::none()
            .fill(Color32::from_rgb(59, 130, 246).gamma_multiply(0.14))
            .stroke(Stroke::new(
                1.0_f32,
                Color32::from_rgb(59, 130, 246).gamma_multiply(0.45),
            ))
            .rounding(Rounding::same(10.0))
            .inner_margin(Margin::same(12.0))
            .show(ui, |ui| {
                ui.horizontal(|ui| {
                    ui.label(
                        RichText::new(format!(
                            "⬇ SwipeIt v{} is Available",
                            snap.latest_version.as_deref().unwrap_or("")
                        ))
                        .strong()
                        .color(Color32::from_rgb(96, 165, 250)),
                    );

                    ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
                        if ui.small_button("✕").clicked() {
                            self.update_checker.dismiss();
                        }
                        if let Some(page) = &snap.release_page_url {
                            if ui.small_button("Release Notes").clicked() {
                                UpdateChecker::open_url(page);
                            }
                        }
                        if let Some(dl) = &snap.download_url {
                            if ui
                                .add(
                                    egui::Button::new(
                                        RichText::new("Download Update")
                                            .strong()
                                            .color(Color32::WHITE),
                                    )
                                    .fill(Color32::from_rgb(59, 130, 246)),
                                )
                                .clicked()
                            {
                                UpdateChecker::open_url(dl);
                            }
                        }
                    });
                });
            });
    }

    fn render_tab_bar(&mut self, ui: &mut egui::Ui) {
        ui.columns(3, |cols| {
            let tabs = [
                (SettingsTab::Controls, "⚡ Controls"),
                (SettingsTab::Shortcuts, "⌘ Shortcuts"),
                (SettingsTab::Safety, "🖥 Display & Safety"),
            ];
            for (idx, (tab, title)) in tabs.iter().enumerate() {
                let selected = self.selected_tab == *tab;
                let fill = if selected {
                    Color32::from_rgb(59, 130, 246)
                } else {
                    Color32::from_rgb(24, 29, 40)
                };
                let text_color = if selected {
                    Color32::WHITE
                } else {
                    Color32::from_rgb(160, 174, 192)
                };
                if cols[idx]
                    .add_sized(
                        [cols[idx].available_width(), 30.0],
                        egui::Button::new(RichText::new(*title).strong().color(text_color))
                            .fill(fill)
                            .rounding(Rounding::same(8.0)),
                    )
                    .clicked()
                {
                    self.selected_tab = *tab;
                }
            }
        });
    }

    fn render_controls_tab(&mut self, ui: &mut egui::Ui) {
        if self.lock_mode.is_locked() {
            card_frame().show(ui, |ui| {
                ui.vertical_centered(|ui| {
                    ui.label(
                        RichText::new(self.lock_mode.title())
                            .size(16.0)
                            .strong()
                            .color(Color32::from_rgb(251, 146, 60)),
                    );
                    ui.add_space(4.0);
                    ui.label(
                        RichText::new("Press your Unlock shortcut or click below to restore input:")
                            .size(12.0)
                            .color(Color32::from_rgb(148, 163, 184)),
                    );
                    ui.add_space(6.0);
                    draw_keycap_badges(ui, &self.settings.unlock_shortcut.key_tokens());
                    ui.add_space(10.0);
                    if ui
                        .add_sized(
                            [240.0, 34.0],
                            egui::Button::new(
                                RichText::new("🔓 Unlock Input Now")
                                    .size(14.0)
                                    .strong()
                                    .color(Color32::WHITE),
                            )
                            .fill(Color32::from_rgb(249, 115, 22))
                            .rounding(Rounding::same(8.0)),
                        )
                        .clicked()
                    {
                        self.unlock(UnlockReason::ManualUI);
                    }
                });
            });
            ui.add_space(10.0);
        } else {
            ui.columns(2, |cols| {
                // Card 1: Full Lock
                card_frame().show(&mut cols[0], |ui| {
                    ui.label(
                        RichText::new("🔒 Full Device Lock")
                            .size(15.0)
                            .strong()
                            .color(Color32::WHITE),
                    );
                    ui.label(
                        RichText::new("Blocks keyboard, mouse clicks, cursor & trackpad gestures.")
                            .size(11.5)
                            .color(Color32::from_rgb(148, 163, 184)),
                    );
                    ui.add_space(8.0);
                    draw_keycap_badges(ui, &self.settings.lock_all_shortcut.key_tokens());
                    ui.add_space(10.0);
                    if ui
                        .add_sized(
                            [ui.available_width(), 32.0],
                            egui::Button::new(
                                RichText::new("Lock All Input")
                                    .strong()
                                    .color(Color32::WHITE),
                            )
                            .fill(Color32::from_rgb(59, 130, 246))
                            .rounding(Rounding::same(8.0)),
                        )
                        .clicked()
                    {
                        self.engage_lock(LockMode::KeyboardAndMouse);
                    }
                });

                // Card 2: Keyboard Only
                card_frame().show(&mut cols[1], |ui| {
                    ui.label(
                        RichText::new("⌨ Keyboard-Only Lock")
                            .size(15.0)
                            .strong()
                            .color(Color32::WHITE),
                    );
                    ui.label(
                        RichText::new("Blocks all keys while keeping mouse & trackpad active.")
                            .size(11.5)
                            .color(Color32::from_rgb(148, 163, 184)),
                    );
                    ui.add_space(8.0);
                    draw_keycap_badges(
                        ui,
                        &self.settings.lock_keyboard_only_shortcut.key_tokens(),
                    );
                    ui.add_space(10.0);
                    if ui
                        .add_sized(
                            [ui.available_width(), 32.0],
                            egui::Button::new(
                                RichText::new("Lock Keyboard Only")
                                    .strong()
                                    .color(Color32::WHITE),
                            )
                            .fill(Color32::from_rgb(38, 46, 66))
                            .rounding(Rounding::same(8.0)),
                        )
                        .clicked()
                    {
                        self.engage_lock(LockMode::KeyboardOnly);
                    }
                });
            });
            ui.add_space(12.0);
        }

        // Quick Preferences Card
        card_frame().show(ui, |ui| {
            ui.label(
                RichText::new("Quick Preferences")
                    .size(13.5)
                    .strong()
                    .color(Color32::WHITE),
            );
            ui.add_space(6.0);

            ui.horizontal(|ui| {
                ui.label("Screen Appearance:");
                for style in OverlayStyle::ALL {
                    let selected = self.settings.overlay_style == style;
                    if ui.selectable_label(selected, style.title()).clicked() {
                        self.settings.overlay_style = style;
                        self.settings.save();
                    }
                }
            });

            ui.add_space(4.0);
            if ui
                .checkbox(
                    &mut self.settings.show_unlock_hint_on_screen,
                    "Show Unlock Shortcut & Master Key Hint on Screen while Locked",
                )
                .changed()
            {
                self.settings.save();
            }

            if ui
                .checkbox(
                    &mut self.settings.auto_unlock_timer_enabled,
                    format!(
                        "Enable Automatic Safety Timer ({} min)",
                        self.settings.auto_unlock_minutes
                    ),
                )
                .changed()
            {
                self.settings.save();
            }
        });

        ui.add_space(10.0);
        self.render_master_key_card(ui);
    }

    fn render_shortcuts_tab(&mut self, ui: &mut egui::Ui) {
        card_frame().show(ui, |ui| {
            self.render_shortcut_recorder_row(
                ui,
                "Lock Keyboard & Trackpad",
                "Engages Full Lock across all displays and hides the cursor.",
                ShortcutTarget::LockAll,
                self.settings.lock_all_shortcut.clone(),
            );
            ui.separator();
            self.render_shortcut_recorder_row(
                ui,
                "Lock Keyboard Only",
                "Blocks all keys while allowing mouse clicks to pass through.",
                ShortcutTarget::LockKeyboardOnly,
                self.settings.lock_keyboard_only_shortcut.clone(),
            );
            ui.separator();
            self.render_shortcut_recorder_row(
                ui,
                "Unlock Input",
                "Restores normal keyboard and mouse operation.",
                ShortcutTarget::Unlock,
                self.settings.unlock_shortcut.clone(),
            );
        });

        ui.add_space(10.0);

        card_frame().show(ui, |ui| {
            if ui
                .checkbox(
                    &mut self.settings.allow_toggle_with_lock_shortcut,
                    "Allow Lock Shortcut to Toggle Unlock (auto-repeat protected)",
                )
                .changed()
            {
                self.settings.save();
                self.sync_backend();
            }

            if ui
                .checkbox(
                    &mut self.settings.enable_global_shortcuts,
                    "Enable Global Shortcuts while Unlocked",
                )
                .changed()
            {
                self.settings.save();
                self.sync_backend();
            }
        });

        ui.add_space(10.0);
        self.render_master_key_card(ui);
    }

    fn render_shortcut_recorder_row(
        &mut self,
        ui: &mut egui::Ui,
        title: &str,
        subtitle: &str,
        target: ShortcutTarget,
        combo: KeyCombo,
    ) {
        let is_recording = self.recording_target == Some(target);
        ui.horizontal(|ui| {
            ui.vertical(|ui| {
                ui.label(RichText::new(title).strong().color(Color32::WHITE));
                ui.label(
                    RichText::new(subtitle)
                        .size(11.5)
                        .color(Color32::from_rgb(148, 163, 184)),
                );
            });

            ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
                let btn_label = if is_recording {
                    "Cancel (Esc)"
                } else {
                    "Record"
                };
                if ui.button(btn_label).clicked() {
                    if is_recording {
                        self.cancel_recording();
                    } else {
                        self.start_recording(target);
                    }
                }

                if is_recording {
                    let preview =
                        KeyCombo::new(self.recording_peak_keys.clone(), self.recording_peak_mods);
                    let tokens = preview.key_tokens();
                    if tokens.is_empty() {
                        ui.label(
                            RichText::new("Press keys…")
                                .italics()
                                .color(Color32::from_rgb(96, 165, 250)),
                        );
                    } else {
                        draw_keycap_badges(ui, &tokens);
                    }
                } else {
                    draw_keycap_badges(ui, &combo.key_tokens());
                }
            });
        });

        if let Some((err_target, msg)) = &self.recorder_error {
            if *err_target == target {
                ui.label(
                    RichText::new(format!("⚠ {}", msg))
                        .size(11.5)
                        .color(Color32::from_rgb(248, 113, 113)),
                );
            }
        }
    }

    fn render_safety_tab(&mut self, ui: &mut egui::Ui) {
        // 1. Display Mode Card
        card_frame().show(ui, |ui| {
            ui.label(
                RichText::new("Overlay Appearance")
                    .size(14.0)
                    .strong()
                    .color(Color32::WHITE),
            );
            ui.add_space(4.0);
            for style in OverlayStyle::ALL {
                let selected = self.settings.overlay_style == style;
                ui.horizontal(|ui| {
                    if ui.radio(selected, style.title()).clicked() {
                        self.settings.overlay_style = style;
                        self.settings.save();
                    }
                    ui.label(
                        RichText::new(format!("— {}", style.subtitle()))
                            .size(11.5)
                            .color(Color32::from_rgb(148, 163, 184)),
                    );
                });
            }
        });

        ui.add_space(10.0);

        // 2. Safety Timer Card
        card_frame().show(ui, |ui| {
            ui.horizontal(|ui| {
                ui.vertical(|ui| {
                    ui.label(
                        RichText::new("Automatic Safety Unlock Timer")
                            .size(14.0)
                            .strong()
                            .color(Color32::WHITE),
                    );
                    ui.label(
                        RichText::new("Automatically unlocks if all combinations are forgotten.")
                            .size(11.5)
                            .color(Color32::from_rgb(148, 163, 184)),
                    );
                });
                ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
                    if ui
                        .checkbox(&mut self.settings.auto_unlock_timer_enabled, "Enabled")
                        .changed()
                    {
                        self.settings.save();
                    }
                });
            });

            if self.settings.auto_unlock_timer_enabled {
                ui.add_space(6.0);
                ui.horizontal(|ui| {
                    if ui.button("−").clicked() {
                        let next = self.settings.auto_unlock_minutes.saturating_sub(1).max(1);
                        self.settings.set_auto_unlock_minutes(next);
                    }
                    ui.label(
                        RichText::new(format!("{} minutes", self.settings.auto_unlock_minutes))
                            .monospace()
                            .strong()
                            .color(Color32::WHITE),
                    );
                    if ui.button("+").clicked() {
                        let next = (self.settings.auto_unlock_minutes + 1).min(120);
                        self.settings.set_auto_unlock_minutes(next);
                    }

                    ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
                        for preset in [60, 30, 15, 10, 5] {
                            let active = self.settings.auto_unlock_minutes == preset;
                            if ui
                                .selectable_label(active, format!("{}m", preset))
                                .clicked()
                            {
                                self.settings.set_auto_unlock_minutes(preset);
                            }
                        }
                    });
                });
            }
        });

        ui.add_space(10.0);

        // 3. Software Updates Card
        card_frame().show(ui, |ui| {
            let snap = self.update_checker.snapshot();
            ui.horizontal(|ui| {
                ui.vertical(|ui| {
                    ui.label(
                        RichText::new("Software Updates")
                            .size(14.0)
                            .strong()
                            .color(Color32::WHITE),
                    );
                    ui.label(
                        RichText::new(format!("SwipeIt v{}", CURRENT_APP_VERSION))
                            .size(11.5)
                            .color(Color32::from_rgb(148, 163, 184)),
                    );
                });

                ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
                    let label = if snap.is_checking {
                        "Checking…"
                    } else {
                        "Check for Updates"
                    };
                    if ui
                        .add_enabled(!snap.is_checking, egui::Button::new(label))
                        .clicked()
                    {
                        if let Some(ts) = self
                            .update_checker
                            .check_for_updates(true, self.settings.last_update_check_timestamp)
                        {
                            self.settings.last_update_check_timestamp = ts;
                            self.settings.save();
                        }
                    }
                });
            });

            if ui
                .checkbox(
                    &mut self.settings.automatically_check_for_updates,
                    "Automatically check for updates on startup",
                )
                .changed()
            {
                self.settings.save();
            }

            if let Some(msg) = &snap.status_message {
                ui.label(
                    RichText::new(msg)
                        .size(11.5)
                        .color(Color32::from_rgb(96, 165, 250)),
                );
            }
        });
    }

    fn render_master_key_card(&self, ui: &mut egui::Ui) {
        Frame::none()
            .fill(Color32::from_rgb(234, 179, 8).gamma_multiply(0.10))
            .stroke(Stroke::new(
                1.0_f32,
                Color32::from_rgb(234, 179, 8).gamma_multiply(0.35),
            ))
            .rounding(Rounding::same(10.0))
            .inner_margin(Margin::same(12.0))
            .show(ui, |ui| {
                ui.horizontal(|ui| {
                    ui.vertical(|ui| {
                        ui.label(
                            RichText::new("🔑 Emergency Master Key (\"Combowombo\")")
                                .strong()
                                .color(Color32::from_rgb(250, 204, 21)),
                        );
                        ui.label(
                            RichText::new(
                                "Hold all 4 keys simultaneously at any time to force-unlock:",
                            )
                            .size(11.5)
                            .color(Color32::from_rgb(148, 163, 184)),
                        );
                    });
                    ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
                        draw_keycap_badges(ui, &KeyCombo::master_unlock_key().key_tokens());
                    });
                });
            });
    }

    fn render_footer(&mut self, ui: &mut egui::Ui) {
        ui.horizontal(|ui| {
            ui.label(
                RichText::new(format!(
                    "SwipeIt v{} • Free & Open Source (MIT) • Zero Ads",
                    CURRENT_APP_VERSION
                ))
                .size(11.0)
                .color(Color32::from_rgb(100, 116, 139)),
            );

            ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
                if ui.small_button("Restore Defaults").clicked() {
                    self.settings.reset_to_defaults();
                    self.sync_backend();
                }
            });
        });
    }

    fn render_fullscreen_lock_viewport(&mut self, ctx: &egui::Context) {
        if !self.lock_mode.is_locked() {
            return;
        }

        let style = self.settings.overlay_style;
        let show_hint = self.settings.show_unlock_hint_on_screen;
        let unlock_tokens = self.settings.unlock_shortcut.key_tokens();
        let master_tokens = KeyCombo::master_unlock_key().key_tokens();
        let remaining_str = self.formatted_remaining_time();
        let mode = self.lock_mode;

        // Bug #8 Fix: Mouse pass-through enabled when in KeyboardOnly mode
        let passthrough = mode == LockMode::KeyboardOnly;

        let builder = ViewportBuilder::default()
            .with_title("SwipeIt Lock Overlay")
            .with_fullscreen(true)
            .with_decorations(false)
            .with_always_on_top()
            .with_transparent(true)
            .with_mouse_passthrough(passthrough);

        let mut manual_unlock_clicked = false;

        ctx.show_viewport_immediate(
            ViewportId::from_hash_of("swipeit_lock_overlay"),
            builder,
            |ctx, _class| {
                if mode == LockMode::KeyboardAndMouse {
                    ctx.send_viewport_cmd(ViewportCommand::CursorVisible(false));
                } else {
                    ctx.send_viewport_cmd(ViewportCommand::CursorVisible(true));
                }

                let bg_fill = match style {
                    OverlayStyle::BlackoutCleaning => Color32::BLACK,
                    OverlayStyle::FrostedShield => Color32::from_rgba_unmultiplied(8, 10, 15, 225),
                    OverlayStyle::Invisible => Color32::TRANSPARENT,
                };

                egui::CentralPanel::default()
                    .frame(Frame::none().fill(bg_fill))
                    .show(ctx, |ui| {
                        if show_hint && style != OverlayStyle::Invisible {
                            ui.vertical_centered(|ui| {
                                ui.add_space(ui.available_height() * 0.35);
                                Frame::none()
                                    .fill(Color32::from_rgba_unmultiplied(20, 24, 33, 235))
                                    .stroke(Stroke::new(
                                        1.0_f32,
                                        Color32::from_rgba_unmultiplied(255, 255, 255, 30),
                                    ))
                                    .rounding(Rounding::same(16.0))
                                    .inner_margin(Margin::symmetric(28.0, 22.0))
                                    .show(ui, |ui| {
                                        ui.set_max_width(420.0);
                                        ui.vertical_centered(|ui| {
                                            ui.label(
                                                RichText::new(format!("🔒 {}", mode.title()))
                                                    .size(18.0)
                                                    .strong()
                                                    .color(Color32::WHITE),
                                            );
                                            ui.add_space(6.0);
                                            ui.label(
                                                RichText::new(if mode == LockMode::KeyboardOnly {
                                                    "Keyboard is locked. Mouse clicks pass straight through."
                                                } else {
                                                    "Safe to wipe down your keyboard, palm rest, and screen."
                                                })
                                                .size(12.5)
                                                .color(Color32::from_rgb(148, 163, 184)),
                                            );
                                            ui.add_space(12.0);
                                            ui.label(
                                                RichText::new("Unlock Shortcut:")
                                                    .size(11.5)
                                                    .color(Color32::from_rgb(148, 163, 184)),
                                            );
                                            draw_keycap_badges(ui, &unlock_tokens);
                                            ui.add_space(8.0);
                                            ui.label(
                                                RichText::new("Emergency Master Key:")
                                                    .size(11.0)
                                                    .color(Color32::from_rgb(250, 204, 21)),
                                            );
                                            draw_keycap_badges(ui, &master_tokens);

                                            if let Some(rem) = &remaining_str {
                                                ui.add_space(10.0);
                                                ui.label(
                                                    RichText::new(format!(
                                                        "Auto-unlocks in {}",
                                                        rem
                                                    ))
                                                    .monospace()
                                                    .size(12.0)
                                                    .color(Color32::from_rgb(251, 146, 60)),
                                                );
                                            }

                                            if cfg!(target_os = "macos") {
                                                ui.add_space(10.0);
                                                if ui.button("Exit Preview Lock").clicked() {
                                                    manual_unlock_clicked = true;
                                                }
                                            }
                                        });
                                    });
                            });
                        }
                    });
            },
        );

        if manual_unlock_clicked {
            self.unlock(UnlockReason::ManualUI);
        }
    }
}

impl eframe::App for SwipeItCrossApp {
    fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
        self.apply_custom_dark_theme(ctx);

        // 1. Poll OS low-level input backend events
        for event in self.backend.poll_events() {
            match event {
                BackendEvent::Locked(mode) => self.engage_lock(mode),
                BackendEvent::Unlocked(reason) => self.unlock(reason),
            }
        }

        // 2. Check safety countdown timer expiration
        if self.remaining_lock_seconds() == Some(0) {
            self.unlock(UnlockReason::SafetyTimer);
        }

        // 3. Handle interactive shortcut recorder or in-window unlock keys
        if self.recording_target.is_some() {
            self.handle_shortcut_recording_input(ctx);
        } else {
            self.check_in_window_unlock_keys(ctx);
        }

        // Request periodic repaint while locked (for countdown timer & low-latency hook polling)
        ctx.request_repaint_after(Duration::from_millis(if self.lock_mode.is_locked() {
            100
        } else {
            250
        }));

        // 4. Render Dashboard UI
        egui::CentralPanel::default()
            .frame(
                Frame::none()
                    .fill(Color32::from_rgb(11, 13, 18))
                    .inner_margin(Margin::symmetric(20.0, 16.0)),
            )
            .show(ctx, |ui| {
                self.render_header(ui);
                self.render_update_banner(ui);
                ui.add_space(12.0);
                self.render_tab_bar(ui);
                ui.add_space(12.0);

                egui::ScrollArea::vertical()
                    .id_salt(Id::new("main_tab_scroll"))
                    .max_height(ui.available_height() - 34.0)
                    .show(ui, |ui| match self.selected_tab {
                        SettingsTab::Controls => self.render_controls_tab(ui),
                        SettingsTab::Shortcuts => self.render_shortcuts_tab(ui),
                        SettingsTab::Safety => self.render_safety_tab(ui),
                    });

                ui.with_layout(Layout::bottom_up(Align::LEFT), |ui| {
                    self.render_footer(ui);
                    ui.separator();
                });
            });

        // 5. Render Fullscreen Lock Overlay when locked
        self.render_fullscreen_lock_viewport(ctx);
    }

    fn on_exit(&mut self, _gl: Option<&eframe::glow::Context>) {
        self.backend.stop();
    }
}

fn card_frame() -> Frame {
    Frame::none()
        .fill(Color32::from_rgb(20, 24, 33))
        .stroke(Stroke::new(
            1.0_f32,
            Color32::from_rgba_unmultiplied(255, 255, 255, 20),
        ))
        .rounding(Rounding::same(12.0))
        .inner_margin(Margin::same(14.0))
}

fn draw_keycap_badges(ui: &mut egui::Ui, tokens: &[String]) {
    ui.horizontal_wrapped(|ui| {
        ui.spacing_mut().item_spacing.x = 4.0;
        for (idx, token) in tokens.iter().enumerate() {
            if idx > 0 {
                ui.label(
                    RichText::new("+")
                        .size(11.0)
                        .color(Color32::from_rgb(100, 116, 139)),
                );
            }
            Frame::none()
                .fill(Color32::from_rgb(30, 36, 51))
                .stroke(Stroke::new(1.0_f32, Color32::from_rgb(56, 66, 89)))
                .rounding(Rounding::same(6.0))
                .inner_margin(Margin::symmetric(7.0, 3.0))
                .show(ui, |ui| {
                    ui.label(
                        RichText::new(token)
                            .monospace()
                            .size(11.5)
                            .strong()
                            .color(Color32::from_rgb(226, 232, 240)),
                    );
                });
        }
    });
}

fn egui_key_to_vk(key: Key) -> Option<u16> {
    match key {
        Key::Escape => Some(vk::ESCAPE),
        Key::Space => Some(vk::SPACE),
        Key::Enter => Some(vk::RETURN),
        Key::Tab => Some(vk::TAB),
        Key::Backspace => Some(vk::BACKSPACE),
        Key::Delete => Some(vk::DELETE),
        Key::Insert => Some(vk::INSERT),
        Key::Home => Some(vk::HOME),
        Key::End => Some(vk::END),
        Key::PageUp => Some(vk::PAGE_UP),
        Key::PageDown => Some(vk::PAGE_DOWN),
        Key::ArrowLeft => Some(vk::LEFT),
        Key::ArrowUp => Some(vk::UP),
        Key::ArrowRight => Some(vk::RIGHT),
        Key::ArrowDown => Some(vk::DOWN),
        Key::Num0 => Some(0x30),
        Key::Num1 => Some(0x31),
        Key::Num2 => Some(0x32),
        Key::Num3 => Some(0x33),
        Key::Num4 => Some(0x34),
        Key::Num5 => Some(0x35),
        Key::Num6 => Some(0x36),
        Key::Num7 => Some(0x37),
        Key::Num8 => Some(0x38),
        Key::Num9 => Some(0x39),
        Key::A => Some(0x41),
        Key::B => Some(0x42),
        Key::C => Some(0x43),
        Key::D => Some(0x44),
        Key::E => Some(0x45),
        Key::F => Some(0x46),
        Key::G => Some(0x47),
        Key::H => Some(0x48),
        Key::I => Some(0x49),
        Key::J => Some(0x4A),
        Key::K => Some(0x4B),
        Key::L => Some(0x4C),
        Key::M => Some(0x4D),
        Key::N => Some(0x4E),
        Key::O => Some(0x4F),
        Key::P => Some(0x50),
        Key::Q => Some(0x51),
        Key::R => Some(0x52),
        Key::S => Some(0x53),
        Key::T => Some(0x54),
        Key::U => Some(0x55),
        Key::V => Some(0x56),
        Key::W => Some(0x57),
        Key::X => Some(0x58),
        Key::Y => Some(0x59),
        Key::Z => Some(0x5A),
        Key::F1 => Some(0x70),
        Key::F2 => Some(0x71),
        Key::F3 => Some(0x72),
        Key::F4 => Some(0x73),
        Key::F5 => Some(0x74),
        Key::F6 => Some(0x75),
        Key::F7 => Some(0x76),
        Key::F8 => Some(0x77),
        Key::F9 => Some(0x78),
        Key::F10 => Some(0x79),
        Key::F11 => Some(0x7A),
        Key::F12 => Some(0x7B),
        _ => None,
    }
}
