#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod app;
pub mod core;
pub mod input;

use app::SwipeItCrossApp;
use eframe::egui;

fn main() -> eframe::Result<()> {
    let options = eframe::NativeOptions {
        viewport: egui::ViewportBuilder::default()
            .with_title("SwipeIt")
            .with_inner_size([600.0, 540.0])
            .with_min_inner_size([540.0, 480.0]),
        ..Default::default()
    };

    eframe::run_native(
        "SwipeIt",
        options,
        Box::new(|cc| Ok(Box::new(SwipeItCrossApp::new(cc)))),
    )
}
