//
//  KeyVibeApp.swift
//  KeyVibe
//
//  Velocity-sensitive mechanical keyboard sound engine for macOS.
//  Copyright © 2024 KeyVibe. All rights reserved.
//
//  Main application entry point using SwiftUI App lifecycle.
//  Provides an interactive main dashboard window and an active Menu Bar item.
//

import SwiftUI

@main
struct KeyVibeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup("KeyVibe") {
            MainWindowView()
        }
    }
}
