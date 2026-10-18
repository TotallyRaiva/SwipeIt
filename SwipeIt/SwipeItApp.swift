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
    @State private var updateChecker: UpdateChecker

    init() {
        let store = SettingsStore()
        let manager = LockManager(settings: store)
        let checker = UpdateChecker()
        _settings = State(initialValue: store)
        _lockManager = State(initialValue: manager)
        _updateChecker = State(initialValue: checker)
    }

    var body: some Scene {
        Window("SwipeIt", id: "main-dashboard") {
            ContentView(lockManager: lockManager, settings: settings, updateChecker: updateChecker)
                .task {
                    // Check for updates in background on launch if enabled
                    await updateChecker.checkForUpdates(manual: false, settings: settings)
                }
        }
        .defaultSize(width: 580, height: 520)

        MenuBarExtra(
            "SwipeIt",
            systemImage: lockManager.lockMode.systemImage
        ) {
            MenuBarView(lockManager: lockManager, settings: settings, updateChecker: updateChecker)
        }
    }
}
