//
//  SwipeItApp.swift
//  SwipeIt
//
//  Created by Reiwa on 16.10.2026.
//

import SwiftUI

@main
struct SwipeItApp: App {
    @State private var settings: SettingsStore
    @State private var lockManager: LockManager

    init() {
        let store = SettingsStore()
        let manager = LockManager(settings: store)
        _settings = State(initialValue: store)
        _lockManager = State(initialValue: manager)
    }

    var body: some Scene {
        Window("SwipeIt — Keyboard & Trackpad Locker", id: "main-dashboard") {
            ContentView(lockManager: lockManager, settings: settings)
        }
        .defaultSize(width: 640, height: 740)

        MenuBarExtra(
            "SwipeIt",
            systemImage: lockManager.lockMode.systemImage
        ) {
            MenuBarView(lockManager: lockManager, settings: settings)
        }
    }
}
