//
//  HotkeyManager.swift
//  Aoki
//
//  Manages global hotkeys (F17 and Ctrl+1) to activate the app.
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

        os_log("Hotkey listener STARTED successfully. Press F17 or Ctrl+1 to activate.", log: logger, type: .info)
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

        // F17 key (keycode 64)
        if keyCode == Constants.Hotkey.f17KeyCode {
            os_log("F17 detected! Triggering capture...", log: logger, type: .info)
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.hotkeyPressed()
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
    func hotkeyPressed()
}
