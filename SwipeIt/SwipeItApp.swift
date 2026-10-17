//
//  SwipeItApp.swift
//  SwipeIt
//
//  Created by Reiwa on 16.10.2026.
//

import SwiftUI

@main
@MainActor
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
        Window("SwipeIt", id: "main-dashboard") {
            ContentView(lockManager: lockManager, settings: settings)
        }
        .defaultSize(width: 580, height: 520)

        MenuBarExtra(
            "SwipeIt",
            systemImage: lockManager.lockMode.systemImage
        ) {
            MenuBarView(lockManager: lockManager, settings: settings)
        }
    }
}
