//
//  AokiApp.swift
//  Aoki
//
//  Menu bar app entry point. All UI is handled via AppDelegate and status item.
//

import SwiftUI

@main
struct AokiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No visible windows - this is a menu bar only app
        Settings { EmptyView() }
    }
}
