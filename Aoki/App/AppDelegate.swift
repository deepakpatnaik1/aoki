//
//  AppDelegate.swift
//  Aoki
//
//  Menu bar app that listens for global hotkeys:
//  - Ctrl+1: Capture active window screenshot → Yoink
//  - Ctrl+2: Capture active window screenshot → Warp
//  - Ctrl+3: Capture selected region screenshot
//  - Ctrl+4: Activate scrolling screenshot capture
//

import SwiftUI
import ServiceManagement
import os.log

private let logger = OSLog(subsystem: "com.aoki.scrollingscreenshot", category: "AppDelegate")

class AppDelegate: NSObject, NSApplicationDelegate, HotkeyManagerDelegate {

    // MARK: - Properties

    private let overlayManager = OverlayManager()
    private var hotkeyManager: HotkeyManager?
    private var statusItem: NSStatusItem?

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        os_log("Aoki app launched", log: logger, type: .info)

        setupStatusItem()
        setupHotkeyManager()

        // Check screen recording permission
        Task {
            let hasPermission = await checkScreenRecordingPermission()
            os_log("Screen recording permission: %{public}@", log: logger, type: .info, hasPermission ? "YES" : "NO")
            if !hasPermission {
                await MainActor.run {
                    showPermissionAlert()
                }
            }
        }
    }

    // MARK: - Status Item (Menu Bar Icon)

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            // Use the app icon or a camera symbol
            if let image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Aoki") {
                image.isTemplate = true
                button.image = image
            }
        }

        let menu = NSMenu()

        let windowToYoinkItem = NSMenuItem(title: "Window → Yoink (⌃1)", action: #selector(captureWindowToYoink), keyEquivalent: "")
        windowToYoinkItem.target = self
        menu.addItem(windowToYoinkItem)

        let windowToWarpItem = NSMenuItem(title: "Window → Warp (⌃2)", action: #selector(captureWindowToWarp), keyEquivalent: "")
        windowToWarpItem.target = self
        menu.addItem(windowToWarpItem)

        let regionCaptureItem = NSMenuItem(title: "Region Screenshot (⌃3)", action: #selector(captureRegion), keyEquivalent: "")
        regionCaptureItem.target = self
        menu.addItem(regionCaptureItem)

        let scrollingCaptureItem = NSMenuItem(title: "Scrolling Capture (⌃4)", action: #selector(activateCapture), keyEquivalent: "")
        scrollingCaptureItem.target = self
        menu.addItem(scrollingCaptureItem)

        let restartItem = NSMenuItem(title: "Restart", action: #selector(restartCapture), keyEquivalent: "r")
        restartItem.target = self
        menu.addItem(restartItem)

        menu.addItem(NSMenuItem.separator())

        // Quality mode toggle
        let readingModeItem = NSMenuItem(title: "Reading Mode (Small Files)", action: #selector(setReadingMode(_:)), keyEquivalent: "")
        readingModeItem.target = self
        readingModeItem.state = .on  // Default
        menu.addItem(readingModeItem)

        let designModeItem = NSMenuItem(title: "Design Mode (Lossless)", action: #selector(setDesignMode(_:)), keyEquivalent: "")
        designModeItem.target = self
        designModeItem.state = .off
        menu.addItem(designModeItem)

        menu.addItem(NSMenuItem.separator())

        let openFolderItem = NSMenuItem(title: "Open Save Folder", action: #selector(openSaveFolder), keyEquivalent: "")
        openFolderItem.target = self
        menu.addItem(openFolderItem)

        menu.addItem(NSMenuItem.separator())

        // Launch at Login toggle
        let launchAtLoginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin(_:)), keyEquivalent: "")
        launchAtLoginItem.target = self
        launchAtLoginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(launchAtLoginItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Aoki", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    // MARK: - Launch at Login

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
                sender.state = .off
            } else {
                try SMAppService.mainApp.register()
                sender.state = .on
            }
        } catch {
            print("Failed to toggle launch at login: \(error)")
        }
    }

    // MARK: - Hotkey Manager

    private func setupHotkeyManager() {
        hotkeyManager = HotkeyManager(delegate: self)
        hotkeyManager?.startListening()
    }

    /// Called when Ctrl+1 is pressed - window screenshot → Yoink
    func windowToYoinkHotkeyPressed() {
        os_log("windowToYoinkHotkeyPressed() called", log: logger, type: .info)
        captureWindowToYoink()
    }

    /// Called when Ctrl+2 is pressed - window screenshot → Warp
    func windowToWarpHotkeyPressed() {
        os_log("windowToWarpHotkeyPressed() called", log: logger, type: .info)
        captureWindowToWarp()
    }

    /// Called when Ctrl+3 is pressed - region screenshot
    func regionScreenshotHotkeyPressed() {
        os_log("regionScreenshotHotkeyPressed() called", log: logger, type: .info)
        captureRegion()
    }

    /// Called when Ctrl+4 is pressed - scrolling screenshot
    func scrollingScreenshotHotkeyPressed() {
        os_log("scrollingScreenshotHotkeyPressed() called", log: logger, type: .info)
        activateCapture()
    }

    @objc private func captureWindowToYoink() {
        os_log("captureWindowToYoink() called", log: logger, type: .info)
        Task {
            await captureActiveWindow(destination: .yoink)
        }
    }

    @objc private func captureWindowToWarp() {
        os_log("captureWindowToWarp() called", log: logger, type: .info)
        Task {
            await captureActiveWindow(destination: .warp)
        }
    }

    @objc private func activateCapture() {
        os_log("activateCapture() called - showing overlay", log: logger, type: .info)
        overlayManager.showOverlay()
    }

    @objc private func captureRegion() {
        os_log("captureRegion() called - showing overlay for region capture", log: logger, type: .info)
        overlayManager.showOverlay(mode: .region)
    }

    @objc private func restartCapture() {
        os_log("restartCapture() called - relaunching app", log: logger, type: .info)

        // Spawn a shell process that waits briefly then reopens the app
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.3; open \"\(Bundle.main.bundlePath)\""]
        try? task.run()

        // Quit the app - the shell process survives and relaunches us
        NSApplication.shared.terminate(nil)
    }

    @objc private func openSaveFolder() {
        let url = URL(fileURLWithPath: Constants.saveDirectory)

        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        NSWorkspace.shared.open(url)
    }

    // MARK: - Quality Mode

    @objc private func setReadingMode(_ sender: NSMenuItem) {
        overlayManager.qualityMode = .reading
        updateQualityMenuState()
        os_log("Quality mode set to: Reading", log: logger, type: .info)
    }

    @objc private func setDesignMode(_ sender: NSMenuItem) {
        overlayManager.qualityMode = .design
        updateQualityMenuState()
        os_log("Quality mode set to: Design", log: logger, type: .info)
    }

    private func updateQualityMenuState() {
        guard let menu = statusItem?.menu else { return }

        for item in menu.items {
            if item.title.contains("Reading Mode") {
                item.state = overlayManager.qualityMode == .reading ? .on : .off
            } else if item.title.contains("Design Mode") {
                item.state = overlayManager.qualityMode == .design ? .on : .off
            }
        }
    }

    // MARK: - Permission Handling

    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Screen Recording Permission Required"
        alert.informativeText = "Aoki needs screen recording permission to capture screenshots. Please grant access in System Preferences > Privacy & Security > Screen Recording."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Preferences")
        alert.addButton(withTitle: "Later")

        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
