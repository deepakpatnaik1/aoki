//
//  HotkeyManager.swift
//  Aoki
//
//  Manages global hotkeys:
//  - Ctrl+1: Capture active window screenshot → Yoink
//  - Ctrl+2: Capture active window screenshot → Warp input bar
//  - Ctrl+3: Capture selected region screenshot
//  - Ctrl+4: Activate scrolling screenshot capture
//

import Cocoa
import Carbon.HIToolbox
import os.log

private let logger = OSLog(subsystem: "com.aoki.scrollingscreenshot", category: "HotkeyManager")

class HotkeyManager {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private weak var delegate: HotkeyManagerDelegate?

    init(delegate: HotkeyManagerDelegate) {
        self.delegate = delegate
    }

    /// Starts listening for global hotkeys.
    /// Requires Accessibility permission.
    func startListening() {
        // First check if we have accessibility permission
        let trusted = AXIsProcessTrusted()
        os_log("Accessibility trusted: %{public}@", log: logger, type: .info, trusted ? "YES" : "NO")

        if !trusted {
            os_log("Requesting accessibility permission...", log: logger, type: .info)
            requestAccessibilityPermission()
            // Continue anyway - the tap will fail if not trusted
        }

        let eventMask = (1 << CGEventType.keyDown.rawValue)

        // Create event tap
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passRetained(event) }

                let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()

                if manager.handleKeyEvent(event) {
                    return nil // Consume the event
                }

                return Unmanaged.passRetained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let eventTap = eventTap else {
            os_log("FAILED to create event tap! Accessibility permission likely not granted.", log: logger, type: .error)
            requestAccessibilityPermission()
            return
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)

        os_log("Hotkey listener STARTED successfully. Ctrl+1 window→Yoink, Ctrl+2 window→Warp, Ctrl+3 region, Ctrl+4 scrolling.", log: logger, type: .info)
    }

    /// Stops listening for global hotkeys.
    func stopListening() {
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    /// Handles a key event and returns true if it was a hotkey we consumed.
    private func handleKeyEvent(_ event: CGEvent) -> Bool {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        // Check if Control key is held
        let controlHeld = flags.contains(.maskControl)

        // Ctrl+1: Window screenshot → Yoink
        if controlHeld && keyCode == Constants.Hotkey.oneKeyCode {
            os_log("Ctrl+1 detected! Capturing window → Yoink...", log: logger, type: .info)
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.windowToYoinkHotkeyPressed()
            }
            return true
        }

        // Ctrl+2: Window screenshot → Warp
        if controlHeld && keyCode == Constants.Hotkey.twoKeyCode {
            os_log("Ctrl+2 detected! Capturing window → Warp...", log: logger, type: .info)
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.windowToWarpHotkeyPressed()
            }
            return true
        }

        // Ctrl+4: Scrolling screenshot
        if controlHeld && keyCode == Constants.Hotkey.fourKeyCode {
            os_log("Ctrl+4 detected! Starting scrolling capture...", log: logger, type: .info)
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.scrollingScreenshotHotkeyPressed()
            }
            return true
        }

        // Ctrl+3: Region screenshot
        if controlHeld && keyCode == Constants.Hotkey.threeKeyCode {
            os_log("Ctrl+3 detected! Starting region capture...", log: logger, type: .info)
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.regionScreenshotHotkeyPressed()
            }
            return true
        }

        return false
    }

    /// Requests Accessibility permission from the user.
    private func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    deinit {
        stopListening()
    }
}

/// Protocol for hotkey events.
protocol HotkeyManagerDelegate: AnyObject {
    /// Called when Ctrl+1 is pressed (window screenshot → Yoink)
    func windowToYoinkHotkeyPressed()
    /// Called when Ctrl+2 is pressed (window screenshot → Warp)
    func windowToWarpHotkeyPressed()
    /// Called when Ctrl+3 is pressed (region screenshot)
    func regionScreenshotHotkeyPressed()
    /// Called when Ctrl+4 is pressed (scrolling screenshot)
    func scrollingScreenshotHotkeyPressed()
}
